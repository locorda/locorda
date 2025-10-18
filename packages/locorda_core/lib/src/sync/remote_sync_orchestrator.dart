import 'package:collection/collection.dart';
import 'package:locorda_core/locorda_core.dart';
import 'package:locorda_core/src/generated/_index.dart';
import 'package:locorda_core/src/hlc_service.dart';
import 'package:locorda_core/src/index/index_manager.dart';
import 'package:locorda_core/src/index/index_rdf_generator.dart';
import 'package:locorda_core/src/index/shard_determiner.dart';
import 'package:locorda_core/src/mapping/merge_contract.dart';
import 'package:locorda_core/src/mapping/merge_contract_loader.dart';
import 'package:locorda_core/src/rdf/rdf_extensions.dart';
import 'package:locorda_core/src/storage/remote_storage.dart';
import 'package:locorda_core/src/storage/storage_interface.dart';
import 'package:locorda_core/src/sync/remote_document_merger.dart';
import 'package:logging/logging.dart';
import 'package:rdf_core/rdf_core.dart';

final _log = Logger('RemoteSyncOrchestrator');

/// Orchestrates remote synchronization following the revised algorithm.
///
/// Implements the process from "Synchronization Algorithm Sketch.md":
/// - Phase A: Metadata Reconciliation & Queue Building
/// - Phase B: Document & Shard Finalization
///
/// Assumes Phase 0 (Sync Preparation) has already been completed by
/// _ensureShardDocumentsAreUpToDate, which materialized shard state in DB.
class RemoteSyncOrchestrator {
  final Storage _storage;
  final RemoteStorage _remoteStorage;
  final RemoteDocumentMerger _merger;
  final SyncGraphConfig _config;
  final IndexRdfGenerator _indexRdfGenerator;
  final IndexManager _indexManager;
  final ShardDeterminer _shardDeterminer;
  final HlcService _hlcService;
  final MergeContractLoader _mergeContractLoader;

  RemoteSyncOrchestrator({
    required Storage storage,
    required RemoteStorage remoteStorage,
    required SyncGraphConfig config,
    required IndexRdfGenerator indexRdfGenerator,
    required ShardDeterminer shardDeterminer,
    required IndexManager indexManager,
    required HlcService hlcService,
    required MergeContractLoader mergeContractLoader,
  })  : _storage = storage,
        _remoteStorage = remoteStorage,
        _config = config,
        _indexRdfGenerator = indexRdfGenerator,
        _merger = RemoteDocumentMerger(storage: storage),
        _indexManager = indexManager,
        _shardDeterminer = shardDeterminer,
        _hlcService = hlcService,
        _mergeContractLoader = mergeContractLoader;

  /// Execute complete remote synchronization cycle.
  ///
  /// Process (per resource type in canonical order):
  /// 1. Phase A: Sync indices, download shards, build document queue
  /// 2. Phase B: Process documents, finalize shards
  ///
  /// Resource types are processed in order:
  /// - Index-of-indices first (idx:FullIndex, idx:GroupIndexTemplate)
  /// - Then other types in alphabetical order
  ///
  /// This ensures that indices are fully synced before the resources they
  /// index, preventing broken references and enabling correct shard determination.
  Future<void> sync(DateTime syncTime, int lastSyncTimestamp) async {
    _log.info('Starting remote synchronization cycle');

    try {
      // Sync each resource type completely before moving to next
      for (final resourceType
          in _config.resourcesInSyncOrder.map((r) => r.typeIri)) {
        _log.info('Syncing resource type: ${resourceType.debug}');

        // Phase A: Metadata Reconciliation & Queue Building for this type
        final syncContext =
            await _reconcileMetadata(resourceType, lastSyncTimestamp, syncTime);

        // Phase B: Document & Shard Finalization for this type
        await _syncDocumentsAndFinalizeShards(
          resourceType,
          syncContext,
          lastSyncTimestamp,
          syncTime,
        );

        _log.info('Completed sync for resource type: ${resourceType.debug}');
      }

      _log.info('Remote synchronization cycle completed successfully');
    } catch (e, st) {
      _log.severe('Remote synchronization cycle failed', e, st);
      rethrow;
    }
  }

  /// Phase A: Metadata Reconciliation & Queue Building for a resource type.
  ///
  /// Process:
  /// 1. Sync Index Documents for this type (conditional GET + upload loop with retry)
  /// 2. Build Document Sync Queue by comparing local and remote shards
  ///
  /// Returns: SyncContext with document queue and shard state for this type
  Future<SyncContext> _reconcileMetadata(
    IriTerm resourceType,
    int lastSyncTimestamp,
    DateTime syncTime,
  ) async {
    _log.info(
        'Phase A: Metadata Reconciliation & Queue Building for ${resourceType.debug}');

    // Step 1: Sync Index Documents for this type
    final allIndices =
        await _syncIndexDocuments(resourceType, lastSyncTimestamp, syncTime);
    final syncContext = SyncContext(indices: allIndices);

    // Step 2: Build Document Sync Queue for this type
    await _buildDocumentSyncQueue(resourceType, syncContext);

    _log.info(
        'Phase A complete for ${resourceType.debug}: ${syncContext.documentQueue.length} documents queued');
    return syncContext;
  }

  /// Phase B: Document & Shard Finalization for a resource type.
  ///
  /// Process:
  /// 1. Process Document Sync Queue (download + merge + upload each document)
  /// 2. Finalize Shards (transactional loop with retry on 412)
  ///
  /// Parameters:
  /// - [resourceType]: The resource type being synced
  /// - [syncContext]: Context from Phase A containing document queue and shard state
  /// - [lastSyncTimestamp]: Timestamp of last successful sync
  Future<void> _syncDocumentsAndFinalizeShards(
    IriTerm resourceType,
    SyncContext syncContext,
    int lastSyncTimestamp,
    DateTime syncTime,
  ) async {
    _log.info(
        'Phase B: Document & Shard Finalization for ${resourceType.debug}');

    // Step 1: Process Document Sync Queue for this type
    await _processDocumentSyncQueue(syncContext, lastSyncTimestamp, syncTime);

    // Step 2: Finalize Shards for this type
    await _finalizeShards(syncContext);

    _log.info('Phase B complete for ${resourceType.debug}');
  }

  /// Step A.1: Sync Index Documents for a specific resource type.
  ///
  /// For each configured index of this type:
  /// 1. Conditional GET using stored ETag
  /// 2. Handle 200/304/404 responses
  /// 3. Merge if needed
  /// 4. Upload loop with retry on 412 conflict
  ///
  /// Returns list of (indexIri, fetchPolicy) tuples for this type.
  Future<List<(IriTerm, ItemFetchPolicy)>> _syncIndexDocuments(
    IriTerm resourceType,
    int lastSyncTimestamp,
    DateTime syncTime,
  ) async {
    _log.fine('Syncing index documents for ${resourceType.debug}');

    // Get resource config for this type
    final resourceConfig =
        _config.resources.firstWhere((r) => r.typeIri == resourceType);

    // Collect FullIndex IRIs for this type
    final fullIndices =
        resourceConfig.indices.whereType<FullIndexGraphConfig>().map((index) {
      final iri = _indexRdfGenerator.generateFullIndexIri(index, resourceType);
      return (iri, index.itemFetchPolicy);
    }).toList();

    // Collect subscribed GroupIndex IRIs for this type
    // Storage now filters by indexed type automatically
    final groupIndices = await _storage.getSubscribedGroupIndices(resourceType);

    // Convert from 3-tuple to 2-tuple (drop indexedType since we know it)
    final groupIndexTuples = groupIndices
        .map((tuple) => (tuple.$1, tuple.$3)) // (indexIri, fetchPolicy)
        .toList();

    final indices = <(IriTerm, ItemFetchPolicy)>[
      ...fullIndices,
      ...groupIndexTuples,
    ];

    _log.fine('Found ${indices.length} indices for ${resourceType.debug}');

    // Sync each index document
    for (final (indexIri, _) in indices) {
      final documentIri = indexIri.getDocumentIri();
      await _syncDocument(
        documentIri,
        lastSyncTimestamp,
        syncTime,
        debugName: 'Index ${documentIri.debug}',
      );
    }

    return indices;
  }

  /// Sync a single document with retry loop on 412
  Future<void> _syncDocument(
    IriTerm documentIri,
    int lastSyncTimestamp,
    DateTime syncTime, {
    String debugName = '',
  }) async {
    _log.fine('Syncing ${debugName}');

    while (true) {
      try {
        // 1. Conditional GET
        final cachedETag = await _storage.getRemoteETag(
          _remoteStorage.remoteId,
          documentIri,
        );

        final downloadResult = await _remoteStorage.download(
          documentIri,
          ifNoneMatch: cachedETag,
        );

        RdfGraph? documentToUpload;
        MergeContract? mergeContract;

        // 2. Handle response cases
        if (downloadResult.notModified) {
          // Case: 304 Not Modified
          _log.fine('$debugName unchanged (304)');
          final localDocument = await _getLocalDocument(documentIri,
              ifChangedSincePhysicalClock: lastSyncTimestamp);
          if (localDocument != null) {
            documentToUpload = localDocument;
            mergeContract = await _mergeContractLoader.load(_mergeContractLoader
                .extractGovernanceIris(localDocument, documentIri));
          } else {
            _log.fine('Local $debugName has no changes since last sync');
          }
          break;
        } else if (downloadResult.graph != null) {
          // Case: 200 OK - Remote changed
          _log.fine('$debugName changed remotely');
          // Theoretically, we could skip merge if local unchanged since last sync
          // but just to be safe, always merge if remote changed
          final localDocument = await _getLocalDocument(documentIri);
          final governanceIris = _getMergedGovernanceIris(
              localDocument, documentIri, downloadResult);
          mergeContract = await _mergeContractLoader.load(governanceIris);
          // CRDT merge local + remote
          final mergeResult = await _merger.merge(
            mergeContract: mergeContract,
            documentIri: documentIri,
            localGraph: localDocument,
            remoteGraph: downloadResult.graph,
          );
          final actualGovernanceIris = _mergeContractLoader
              .extractGovernanceIris(mergeResult.mergedGraph, documentIri);
          if (!ListEquality().equals(actualGovernanceIris, governanceIris)) {
            _log.severe('Governance IRIs mismatch after merge for $debugName. '
                'Expected: $governanceIris, '
                'Found: $actualGovernanceIris');
          }

          documentToUpload = mergeResult.mergedGraph;
          // Update ETag cache
          if (downloadResult.etag != null) {
            await _storage.setRemoteETag(
              _remoteStorage.remoteId,
              documentIri,
              downloadResult.etag!,
            );
          }
        } else {
          // Case: 404 Not Found - New index
          _log.fine('$debugName not found remotely (404)');
          documentToUpload = await _getLocalDocument(documentIri);
          if (documentToUpload != null) {
            mergeContract = await _mergeContractLoader.load(_mergeContractLoader
                .extractGovernanceIris(documentToUpload, documentIri));
          }
        }

        // 3. Upload loop (if needed)
        if (documentToUpload != null) {
          if (mergeContract == null) {
            _log.severe('No merge contract available for uploading $debugName');
            throw StateError('Missing merge contract for $debugName');
          }
          final resourceIri = documentToUpload.expectSingleObject<IriTerm>(
              documentIri, SyncManagedDocument.foafPrimaryTopic)!;
          final typeIri = documentToUpload.expectSingleObject<IriTerm>(
              documentIri, Rdf.type)!;
          final shards = await _shardDeterminer.determineShards(
            typeIri,
            resourceIri,
            // app data is requested here, but since this is an rdf graph
            // we can simply pass in the full document which contains the app data (amongst the framework data)
            documentToUpload,
            // Important: we really have to be able to compute all shards here, better be strict and fail early.
            mode: ShardDeterminationMode.strict,
          );
          final clock =
              _hlcService.getCurrentClock(documentToUpload, documentIri);
          // FIXME: how do we cleanly apply the shards to the documentToUpload (with cleanly I mean: so that it complies with merging rules and creates & adds metadata where possible)?
          var uploadSuccess = await _uploadIfNoConflict(
            documentIri: documentIri,
            graph: documentToUpload,
            etag: downloadResult.etag,
          );
          if (uploadSuccess) {
            final int physicalTime = clock.physicalTime;
            // save locally - and really important: perform the index updates afterwards!
            await _storage.saveDocument(
              documentIri,
              typeIri,
              documentToUpload,
              DocumentMetadata(
                  ourPhysicalClock: physicalTime,
                  updatedAt: syncTime.millisecondsSinceEpoch),
              // no property changes - this is a concept for user-triggered edits
              // that is supposed to help us with crdt merges, so we leave it empty here
              const <PropertyChange>[],
            );
            await _indexManager.updateIndices(
              document: documentToUpload,
              documentIri: documentIri,
              physicalTime: physicalTime,
              missingGroupIndices: shards.missingGroupIndices,
            );
          }
          if (uploadSuccess) {
            break; // Success
          }
          // If upload returned false, we got 412 - retry entire step
          _log.fine('Got 412 conflict, restarting sync for $debugName');
          continue;
        }

        break; // No upload needed
      } catch (e, st) {
        _log.warning('Error syncing $debugName', e, st);
        rethrow;
      }
    }
  }

  List<IriTerm> _getMergedGovernanceIris(RdfGraph? localDocument,
      IriTerm documentIri, RemoteDownloadResult downloadResult) {
    final localGovernanceIris = localDocument == null
        ? const <IriTerm>[]
        : _mergeContractLoader.extractGovernanceIris(
            localDocument, documentIri);
    final remoteGovernanceIris = _mergeContractLoader.extractGovernanceIris(
        downloadResult.graph!, documentIri);
    final remoteGovernanceIrisSet = remoteGovernanceIris.toSet();
    final governanceIris = [
      ...remoteGovernanceIris,
      ...localGovernanceIris
          .where((element) => !remoteGovernanceIrisSet.contains(element))
    ];
    return governanceIris;
  }

  /// Step A.2: Build Document Sync Queue for a specific resource type.
  ///
  /// For each shard in each index of this type:
  /// 1. Conditional GET for shard
  /// 2. Create merged_shell (current_local_shard_state merged with remote)
  /// 3. Populate document queue based on differences
  Future<void> _buildDocumentSyncQueue(
    IriTerm resourceType,
    SyncContext context,
  ) async {
    _log.fine('Building document sync queue for ${resourceType.debug}');

    // Context indices were already filtered by resourceType in _reconcileMetadata
    // Extract shards from all synced indices
    final shards = <IriTerm>[];
    for (final (indexIri, _) in context.indices) {
      final indexDocumentIri = indexIri.getDocumentIri();
      final indexDoc = await _storage.getDocument(indexDocumentIri);

      if (indexDoc == null) {
        _log.warning('Index document not found: $indexDocumentIri');
        continue;
      }

      // Parse idx:hasShard triples from index document
      // Both FullIndex and GroupIndex use IdxIndex.hasShard
      final shardTriples = indexDoc.document.triples.where(
        (t) => t.subject == indexIri && t.predicate == IdxIndex.hasShard,
      );

      for (final triple in shardTriples) {
        if (triple.object is IriTerm) {
          shards.add(triple.object as IriTerm);
        }
      }
    }

    _log.fine('Found ${shards.length} shards for ${resourceType.debug}');

    for (final shardIri in shards) {
      await _processSingleShard(shardIri, context);
    }
  }

  /// Process a single shard to build queue and merged_shell
  Future<void> _processSingleShard(
      IriTerm shardIri, SyncContext context) async {
    _log.fine('Processing shard: $shardIri');

    final shardDocumentIri = shardIri.getDocumentIri();

    // 1. Get current_local_shard_state (from DB after Phase 0)
    final localShardDoc = await _storage.getDocument(shardDocumentIri);

    // 2. Conditional GET for remote shard
    final cachedETag =
        await _storage.getRemoteETag(_remoteStorage.remoteId, shardDocumentIri);

    final downloadResult = await _remoteStorage.download(
      shardDocumentIri,
      ifNoneMatch: cachedETag,
    );

    RdfGraph mergedShell;
    RdfGraph? originalRemoteShard;

    // 3. Handle response and create merged_shell
    if (downloadResult.notModified) {
      // Case: 304 Not Modified
      _log.fine('Shard $shardIri unchanged (304)');
      mergedShell = localShardDoc!.document;
      originalRemoteShard = localShardDoc.document; // Remote hasn't changed
    } else if (downloadResult.graph != null) {
      // Case: 200 OK - Remote changed
      _log.fine('Shard $shardIri changed remotely');
      originalRemoteShard = downloadResult.graph;
      final govIris = _getMergedGovernanceIris(
          localShardDoc?.document, shardDocumentIri, downloadResult);
      final mergeContract = await _mergeContractLoader.load(govIris);
      // CRDT merge current_local_shard_state with remote
      final mergeResult = await _merger.merge(
        mergeContract: mergeContract,
        documentIri: shardIri,
        localGraph: localShardDoc?.document,
        remoteGraph: downloadResult.graph,
      );

      mergedShell = mergeResult.mergedGraph;

      // Update ETag cache
      if (downloadResult.etag != null) {
        await _storage.setRemoteETag(
          _remoteStorage.remoteId,
          shardDocumentIri,
          downloadResult.etag!,
        );
      }
    } else if (localShardDoc != null) {
      // Case: 404 Not Found with local entries
      _log.fine('Shard $shardIri not found remotely, using local');
      mergedShell = localShardDoc.document;
      originalRemoteShard = null;
    } else {
      // Case: 404 with no local entries - skip
      _log.fine('Shard $shardIri does not exist yet, skipping');
      return;
    }

    // 4. Store merged_shell for Phase B
    context.mergedShells[shardIri] = mergedShell;
    context.shardETags[shardIri] = downloadResult.etag;

    // 5. Populate document queue
    await _populateDocumentQueue(
      shardIri,
      originalRemoteShard,
      context,
    );
  }

  /// Populate document queue by comparing local and remote shard entries
  Future<void> _populateDocumentQueue(
    IriTerm shardIri,
    RdfGraph? originalRemoteShard,
    SyncContext context,
  ) async {
    // TODO: Parse entries from local index items table
    final localEntries = <IriTerm, String>{}; // resourceIri -> clockHash
    _log.warning('TODO: Parse local index entries for shard $shardIri');

    // TODO: Parse entries from original remote shard
    final remoteEntries = <IriTerm, String>{}; // resourceIri -> clockHash
    _log.warning('TODO: Parse remote shard entries');

    // Add documents to queue based on differences:

    // 1. Local but not in remote (new local documents)
    for (final localIri in localEntries.keys) {
      if (!remoteEntries.containsKey(localIri)) {
        context.documentQueue.add(localIri.getDocumentIri());
      }
    }

    // 2. In both but different clockHash (concurrent changes)
    for (final localIri in localEntries.keys) {
      if (remoteEntries.containsKey(localIri) &&
          remoteEntries[localIri] != localEntries[localIri]) {
        context.documentQueue.add(localIri.getDocumentIri());
      }
    }

    // 3. For eager synced indices: Remote but not local
    // TODO: Check if index is eager synced
    final isEagerSynced = true; // Placeholder
    if (isEagerSynced) {
      for (final remoteIri in remoteEntries.keys) {
        if (!localEntries.containsKey(remoteIri)) {
          context.documentQueue.add(remoteIri.getDocumentIri());
        }
      }
    }
  }

  /// Step B.1: Process Document Sync Queue
  ///
  /// For each document in queue:
  /// 1. Download & merge
  /// 2. Save locally
  /// 3. Upload if needed
  Future<void> _processDocumentSyncQueue(
    SyncContext context,
    int lastSyncTimestamp,
    DateTime syncTime,
  ) async {
    _log.fine('Processing ${context.documentQueue.length} documents');

    for (final documentIri in context.documentQueue) {
      await _syncDocument(documentIri, lastSyncTimestamp, syncTime,
          debugName: 'Document ${documentIri.debug}');
    }
  }

  /// Step B.2: Finalize Shards
  ///
  /// For each shard:
  /// 1. Determine final_entry_set from updated index items table
  /// 2. Reconcile merged_shell with final_entry_set
  /// 3. Upload with retry loop on 412
  Future<void> _finalizeShards(SyncContext context) async {
    _log.fine('Finalizing ${context.mergedShells.length} shards');

    for (final entry in context.mergedShells.entries) {
      await _finalizeSingleShard(entry.key, entry.value, context);
    }
  }

  /// Finalize a single shard with transactional retry loop
  Future<void> _finalizeSingleShard(
    IriTerm shardIri,
    RdfGraph mergedShell,
    SyncContext context,
  ) async {
    _log.fine('Finalizing shard: $shardIri');

    while (true) {
      try {
        // 1. Determine final_entry_set from index items table
        final finalEntrySet = await _getFinalEntrySet(shardIri);

        // 2. Reconcile merged_shell with final_entry_set
        final finalShardDocument = await _reconcileShardWithEntries(
          mergedShell,
          finalEntrySet,
        );

        // 3. Upload with conditional PUT
        final shardDocumentIri = shardIri.getDocumentIri();
        final etag = context.shardETags[shardIri];

        final uploadResult = await _remoteStorage.upload(
          shardDocumentIri,
          finalShardDocument,
          ifMatch: etag,
        );

        if (uploadResult.conflict) {
          // Got 412 - restart from Phase A.2 for this shard
          _log.warning('Got 412 conflict on shard $shardIri, restarting');
          await _processSingleShard(shardIri, context);
          continue;
        }

        // Success - update ETag
        if (uploadResult.etag != null) {
          await _storage.setRemoteETag(
            _remoteStorage.remoteId,
            shardDocumentIri,
            uploadResult.etag!,
          );
        }

        _log.fine('Shard $shardIri finalized successfully');
        break;
      } catch (e, st) {
        _log.warning('Error finalizing shard $shardIri', e, st);
        rethrow;
      }
    }
  }

  // =========================================================================
  // Helper Methods
  // =========================================================================

  /// Upload with retry loop on 412 conflict
  ///
  /// Returns true on success, false on 412 (caller should retry entire step)
  Future<bool> _uploadIfNoConflict({
    required IriTerm documentIri,
    required RdfGraph graph,
    String? etag,
  }) async {
    final uploadResult = await _remoteStorage.upload(
      documentIri,
      graph,
      ifMatch: etag,
    );

    if (uploadResult.conflict) {
      return false; // Signal caller to retry
    }

    // Success - cache new ETag
    if (uploadResult.etag != null) {
      await _storage.setRemoteETag(
        _remoteStorage.remoteId,
        documentIri,
        uploadResult.etag!,
      );
    }

    return true;
  }

  /// Get local document from storage
  Future<RdfGraph?> _getLocalDocument(IriTerm documentIri,
      {int? ifChangedSincePhysicalClock}) async {
    final doc = await _storage.getDocument(
      documentIri,
      ifChangedSincePhysicalClock: ifChangedSincePhysicalClock,
    );
    return doc?.document;
  }

  /// Get final entry set for a shard from index items table
  Future<Set<IndexEntryWithIri>> _getFinalEntrySet(IriTerm shardIri) async {
    final entries = await _storage.getActiveIndexEntriesForShard(shardIri);
    return entries.toSet();
  }

  /// Reconcile merged_shell with final_entry_set
  ///
  /// Applies final entries to merged_shell:
  /// - Add/update entries from final_entry_set
  /// - Create tombstones for entries NOT in final_entry_set
  Future<RdfGraph> _reconcileShardWithEntries(
    RdfGraph mergedShell,
    Set<IndexEntryWithIri> finalEntrySet,
  ) async {
    // TODO: Implement shard reconciliation
    // 1. Parse existing entries from merged_shell
    // 2. Add/update entries from final_entry_set
    // 3. Create tombstones for removed entries
    _log.warning('TODO: Implement shard reconciliation');
    return mergedShell; // Placeholder
  }
}

/// Context object carrying state through sync phases
class SyncContext {
  final List<(IriTerm, ItemFetchPolicy)> indices;

  /// Documents that need to be processed (IRI set)
  final Set<IriTerm> documentQueue = {};

  /// Merged shard shells created in Phase A (shardIri -> merged RDF)
  final Map<IriTerm, RdfGraph> mergedShells = {};

  /// ETags for shards from Phase A (shardIri -> ETag)
  final Map<IriTerm, String?> shardETags = {};

  SyncContext({List<(IriTerm, ItemFetchPolicy)> indices = const []})
      : indices = List.unmodifiable(indices);
}
