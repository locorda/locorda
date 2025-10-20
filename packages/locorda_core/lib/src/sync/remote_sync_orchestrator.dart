import 'package:collection/collection.dart';
import 'package:locorda_core/locorda_core.dart';
import 'package:locorda_core/src/crdt/crdt_types.dart';
import 'package:locorda_core/src/generated/_index.dart';
import 'package:locorda_core/src/hlc_service.dart';
import 'package:locorda_core/src/index/index_manager.dart';
import 'package:locorda_core/src/index/index_rdf_generator.dart';
import 'package:locorda_core/src/index/shard_determiner.dart';
import 'package:locorda_core/src/mapping/framework_iri_generator.dart';
import 'package:locorda_core/src/mapping/identified_blank_node_builder.dart';
import 'package:locorda_core/src/mapping/merge_contract.dart';
import 'package:locorda_core/src/mapping/merge_contract_loader.dart';
import 'package:locorda_core/src/mapping/metadata_generator.dart';
import 'package:locorda_core/src/rdf/rdf_extensions.dart';
import 'package:locorda_core/src/storage/remote_storage.dart';
import 'package:locorda_core/src/storage/storage_interface.dart';
import 'package:locorda_core/src/sync/remote_document_merger.dart';
import 'package:locorda_core/src/util/retry.dart';
import 'package:logging/logging.dart';
import 'package:rdf_core/rdf_core.dart';

final _log = Logger('RemoteSyncOrchestrator');

/// Specification for syncing an index with its shards
sealed class IndexSyncSpec {
  /// The IRI of the index to sync
  final IriTerm indexIri;

  const IndexSyncSpec({required this.indexIri});
}

/// Full index sync: Download all shards and apply fetch policy for new items
final class FullIndexSync extends IndexSyncSpec {
  /// Policy determining which items to download from remote
  final ItemFetchPolicy fetchPolicy;

  const FullIndexSync(
    IriTerm indexIri,
    this.fetchPolicy,
  ) : super(indexIri: indexIri);
}

/// Partial index sync: Upload-only for specific shards containing known items
final class PartialIndexSync extends IndexSyncSpec {
  /// Map of shard IRIs to the set of resource IRIs we need to sync in that shard
  /// Only these specific items will be synced (upload local changes, no remote downloads)
  final Map<IriTerm /*shardIri*/, Set<IriTerm /*resourceIri*/ >> shardItems;

  const PartialIndexSync({
    required super.indexIri,
    required this.shardItems,
  });
}

sealed class ShardSyncSpec {
  final IriTerm shardIri;

  const ShardSyncSpec({required this.shardIri});
}

final class FullShardSync extends ShardSyncSpec {
  final ItemFetchPolicy fetchPolicy;
  const FullShardSync({required super.shardIri, required this.fetchPolicy});
}

final class PartialShardSync extends ShardSyncSpec {
  final Set<IriTerm> resourceIris;

  const PartialShardSync({
    required super.shardIri,
    required this.resourceIris,
  });
}

typedef _DownloadAndMergeResult = ({
  RdfGraph mergedDocument,
  RdfGraph? originalLocalDocument,
  RdfGraph? originalRemoteDocument,
  MergeContract mergeContract,
  String? etag,
  int? localUpdatedAt
});

typedef PreparedShardSync = ({
  IriTerm shardIri,
  _DownloadAndMergeResult merged,
  ShardSyncSpec shardSpec,
});

/// Orchestrates remote synchronization following the revised algorithm.
///
/// Implements the process from "Synchronization Algorithm Sketch.md":
/// - Phase A: Metadata Reconciliation & Queue Building
/// - Phase B: Document & Shard Finalization
///
/// Assumes Phase 0 (Sync Preparation) has already been completed by
/// _ensureShardDocumentsAreUpToDate, which materialized shard state in DB.
class RemoteSyncOrchestrator {
  final RemoteStorage _remoteStorage;
  final Storage _storage;
  final RemoteDocumentMerger _merger;
  final SyncGraphConfig _config;
  final IndexRdfGenerator _indexRdfGenerator;
  final IndexManager _indexManager;
  final ShardDeterminer _shardDeterminer;
  final HlcService _hlcService;
  final MergeContractLoader _mergeContractLoader;
  final CrdtTypeRegistry _crdtTypeRegistry;
  final FrameworkIriGenerator _iriGenerator;
  final MetadataGenerator _metadataGenerator;

  RemoteSyncOrchestrator(
      {required RemoteStorage remoteStorage,
      required Storage storage,
      required RemoteDocumentMerger merger,
      required SyncGraphConfig config,
      required IndexRdfGenerator indexRdfGenerator,
      required IndexManager indexManager,
      required ShardDeterminer shardDeterminer,
      required HlcService hlcService,
      required MergeContractLoader mergeContractLoader,
      required CrdtTypeRegistry crdtTypeRegistry,
      required FrameworkIriGenerator iriGenerator,
      required MetadataGenerator metadataGenerator})
      : _remoteStorage = remoteStorage,
        _storage = storage,
        _merger = merger,
        _config = config,
        _indexRdfGenerator = indexRdfGenerator,
        _indexManager = indexManager,
        _shardDeterminer = shardDeterminer,
        _hlcService = hlcService,
        _mergeContractLoader = mergeContractLoader,
        _crdtTypeRegistry = crdtTypeRegistry,
        _iriGenerator = iriGenerator,
        _metadataGenerator = metadataGenerator;

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
        _syncResourceType(resourceType, lastSyncTimestamp, syncTime);
      }

      _log.info('Remote synchronization cycle completed successfully');
    } catch (e, st) {
      // TODO: should we catch the exception per resource type and continue with others?
      _log.severe('Remote synchronization cycle failed', e, st);
      rethrow;
    }
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
  Future<List<IndexSyncSpec>> _syncIndexDocuments(
    IriTerm resourceType,
    int lastSyncTimestamp,
    DateTime syncTime,
  ) async {
    _log.fine('Syncing index documents for ${resourceType.debug}');

    // Get resource config for this type
    final resourceConfig =
        _config.resources.firstWhere((r) => r.typeIri == resourceType);

    // Index and Shard Sync Strategy:
    //
    // Current Implementation Status:
    // We currently sync only configured/subscribed indices and their complete shard sets.
    // This approach is insufficient - we also need partial sync for foreign indices.
    //
    // 1. Foreign Index Sync Requirements:
    //    Items may belong to multiple indices (configured + foreign).
    //    We must sync shards from foreign indices when:
    //    - They contain items we modified locally (dirty entries need upload)
    //    - They contain items present in our local DB not yet covered by any synced shard
    //
    // 2. Partial Index Sync Strategy:
    //    For foreign indices (not explicitly configured/subscribed):
    //
    //    a) Index Metadata Discovery (IMPLEMENTED):
    //       - Index documents obtained via index-of-indices with filtered prefetch
    //       - Enables shard-to-index association for items
    //
    //    b) Selective Shard Sync (TODO - NOT IMPLEMENTED):
    //       - Sync only shards containing specific items from our index items table
    //       - Shard selection criteria:
    //         * Shards with dirty entries (local changes need upload)
    //         * Shards with entries present in local DB not yet covered by any synced shard
    //       - Important: Among multiple foreign indices containing same item,
    //         syncing one shard is sufficient (avoid redundant syncs)
    //
    // 3. Implementation Requirements:
    //    a) Query index items table for all referenced shards (not just configured indices)
    //    b) Distinguish sync modes per index:
    //       - Full sync: All shards, with ItemFetchPolicy (download new remote items)
    //       - Partial sync: Selected shards only, no ItemFetchPolicy (upload-only for known items)
    //    c) Track which items are already covered by synced shards to avoid redundant syncs
    //
    // TODO: Determine and include partial sync indices in our indices list below

    // Collect FullIndex IRIs for this type
    final fullIndices =
        resourceConfig.indices.whereType<FullIndexGraphConfig>().map((index) {
      final iri = _indexRdfGenerator.generateFullIndexIri(index, resourceType);
      return FullIndexSync(iri, index.itemFetchPolicy);
    }).toList();

    // Collect subscribed GroupIndex IRIs for this type
    // Storage now filters by indexed type automatically
    final groupIndices = await _storage.getSubscribedGroupIndices(resourceType);

    // Convert from 3-tuple to 2-tuple (drop indexedType since we know it)
    final groupIndexTuples = groupIndices
        .map((tuple) =>
            FullIndexSync(tuple.$1, tuple.$3)) // (indexIri, fetchPolicy)
        .toList();

    final indices = <IndexSyncSpec>[
      ...fullIndices,
      ...groupIndexTuples,
    ];

    _log.fine('Found ${indices.length} indices for ${resourceType.debug}');

    // Make sure each index document is synced - this should not actually do much
    // in most cases because the index-of-indices sync should already have
    // ensured that the index documents are up to date, but we do it here for completeness
    // and to be on the safe side.
    for (final spec in indices) {
      final documentIri = spec.indexIri.getDocumentIri();
      await _syncDocument(
        documentIri,
        lastSyncTimestamp,
        syncTime,
        debugName: 'Index ${documentIri.debug}',
      );
    }

    return indices;
  }

  Future<_DownloadAndMergeResult?> _downloadAndMerge(
    IriTerm documentIri,
    int lastSyncTimestamp, {
    String debugName = '',
  }) async {
    // 1. Conditional GET
    final cachedETag = await _storage.getRemoteETag(
      _remoteStorage.remoteId,
      documentIri,
    );

    final downloadResult = await _remoteStorage.download(
      documentIri,
      ifNoneMatch: cachedETag,
    );

    late final RdfGraph documentToUpload;
    late final MergeContract mergeContract;
    StoredDocument?
        loadedLocalDocument; // Track loaded document with metadata for optimistic locking

    // 2. Handle response cases
    if (downloadResult.notModified) {
      // Case: 304 Not Modified
      _log.fine('$debugName unchanged (304)');
      loadedLocalDocument = await _getLocalDocumentWithMetadata(documentIri,
          ifChangedSincePhysicalClock: lastSyncTimestamp);
      if (loadedLocalDocument != null) {
        documentToUpload = loadedLocalDocument.document;
        mergeContract = await _mergeContractLoader.load(_mergeContractLoader
            .extractGovernanceIris(loadedLocalDocument.document, documentIri));
      } else {
        _log.fine('Local $debugName has no changes since last sync');
      }
      // Return null to indicate no changes
      return null;
    } else if (downloadResult.graph != null) {
      // Case: 200 OK - Remote changed
      _log.fine('$debugName changed remotely');
      // Theoretically, we could skip merge if local unchanged since last sync
      // but just to be safe, always merge if remote changed
      loadedLocalDocument = await _getLocalDocumentWithMetadata(documentIri);
      final localDocument = loadedLocalDocument?.document;
      final governanceIris =
          _getMergedGovernanceIris(localDocument, documentIri, downloadResult);
      mergeContract = await _mergeContractLoader.load(governanceIris);
      // CRDT merge local + remote
      final mergeResult = await _merger.merge(
        mergeContract: mergeContract,
        documentIri: documentIri,
        localGraph: localDocument,
        remoteGraph: downloadResult.graph,
      );
      final actualGovernanceIris = _mergeContractLoader.extractGovernanceIris(
          mergeResult.mergedGraph, documentIri);
      if (!ListEquality().equals(actualGovernanceIris, governanceIris)) {
        _log.severe('Governance IRIs mismatch after merge for $debugName. '
            'Expected: $governanceIris, '
            'Found: $actualGovernanceIris');
      }

      documentToUpload = mergeResult.mergedGraph;
    } else {
      // Case: 404 Not Found - New index
      _log.fine('$debugName not found remotely (404)');
      loadedLocalDocument = await _getLocalDocumentWithMetadata(documentIri);
      if (loadedLocalDocument == null) {
        _log.warning(
            '$debugName was found neither remotely nor locally, will skip');
        return null; // Nothing to upload
      }
      documentToUpload = loadedLocalDocument.document;
      mergeContract = await _mergeContractLoader.load(_mergeContractLoader
          .extractGovernanceIris(documentToUpload, documentIri));
    }

    return (
      mergedDocument: documentToUpload,
      originalLocalDocument: loadedLocalDocument?.document,
      originalRemoteDocument: downloadResult.graph,
      mergeContract: mergeContract,
      etag: downloadResult.etag,
      localUpdatedAt: loadedLocalDocument?.metadata.updatedAt
    );
  }

  /// Sync a single document with retry loop on 412
  Future<void> _syncDocument(
    IriTerm documentIri,
    int lastSyncTimestamp,
    DateTime syncTime, {
    String debugName = '',
  }) async {
    _log.fine('Syncing ${debugName}');

    await retryOnConflict(() async {
      try {
        final merged = await _downloadAndMerge(documentIri, lastSyncTimestamp,
            debugName: debugName);
        if (merged == null) {
          return; // No changes, nothing to do
        }
        final (typeIri, documentToUpload, clock, missingGroupIndices) =
            await _reconcileDocument(
          documentIri,
          merged.mergedDocument,
          merged.mergeContract,
        );

        // Will throw [ConcurrentUpdateException] on conflict
        await _applyAndStoreMergedDocument(
          documentIri: documentIri,
          clock: clock,
          documentToUpload: documentToUpload,
          localUpdatedAt: merged.localUpdatedAt,
          missingGroupIndices: missingGroupIndices,
          syncTime: syncTime,
          typeIri: typeIri,
          etag: merged.etag,
        );
      } on ConcurrentUpdateException {
        // Conflict detected during upload or local save - retry entire download+merge+upload
        _log.fine('Conflict detected while syncing $debugName, retrying...');
        rethrow;
      } catch (e, st) {
        _log.warning('Error syncing $debugName', e, st);
        rethrow;
      }
    });
  }

  Future<
      (
        IriTerm typeIri,
        RdfGraph document,
        CurrentCrdtClock clock,
        List<MissingGroupIndex> missingGroupIndices
      )> _reconcileDocument(
    IriTerm documentIri,
    RdfGraph mergedDocument,
    MergeContract mergeContract,
  ) async {
    final resourceIri = mergedDocument.expectSingleObject<IriTerm>(
        documentIri, SyncManagedDocument.foafPrimaryTopic)!;
    final typeIri =
        mergedDocument.expectSingleObject<IriTerm>(documentIri, Rdf.type)!;
    final shards = await _shardDeterminer.determineShards(
      typeIri,
      resourceIri,
      // app data is requested here, but since this is an rdf graph
      // we can simply pass in the full document which contains the app data (amongst the framework data)
      mergedDocument,
      // Important: we really have to be able to compute all shards here, better be strict and fail early.
      mode: ShardDeterminationMode.strict,
    );
    final clock = _hlcService.getCurrentClock(mergedDocument, documentIri);

    // Replace shards in the document and generate metadata for the change
    final document = await _replaceShardsInDocument(
      documentIri: documentIri,
      document: mergedDocument,
      resourceIri: resourceIri,
      newShards: shards.shards,
      mergeContract: mergeContract,
      physicalClock: clock.physicalTime,
    );
    return (typeIri, document, clock, shards.missingGroupIndices);
  }

  ///
  /// Throws [ConcurrentUpdateException] on conflict
  Future<void> _applyAndStoreMergedDocument({
    required IriTerm typeIri,
    required IriTerm documentIri,
    required RdfGraph documentToUpload,
    required String? etag,
    required CurrentCrdtClock clock,
    required int? localUpdatedAt,
    required Iterable<MissingGroupIndex> missingGroupIndices,
    required DateTime syncTime,
    String debugName = '',
  }) async {
    final uploadResult = await _remoteStorage.upload(
      documentIri,
      documentToUpload,
      ifMatch: etag,
    );

    final String mergedETag = switch (uploadResult) {
      ConflictUploadResult() => throw ConcurrentUpdateException(
          'Remote document $debugName changed during upload'),
      SuccessUploadResult() => uploadResult.etag,
    };

    final int physicalTime = clock.physicalTime;

    // Optimistic locking for local save: prevent lost updates from concurrent local changes
    // Use updatedAt as version marker - it's updated on EVERY save (local + remote),
    // unlike ourPhysicalClock which only changes when WE modify the document.
    // This ensures we catch conflicts even if the concurrent change was a remote merge.
    final expectedUpdatedAt = localUpdatedAt;

    // save locally with optimistic lock - retry if conflict detected
    try {
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
        ifMatchUpdatedAt: expectedUpdatedAt,
      );
    } on ConcurrentUpdateException {
      // Local conflict detected! Document was modified locally since we read it.
      // This can happen if user edits document while sync is running - rethrow it
      rethrow;
    }

    // Now that the locally stored document is based on the remote version,
    // we need to update the stored ETag for future conditional requests.
    // Success - cache new ETag
    await _storage.setRemoteETag(
      _remoteStorage.remoteId,
      documentIri,
      mergedETag,
    );

    // FIXME: how do we assure that the updateIndices call is also
    // executed if sync was aborted shortly before here (e.g. app crash)?
    await _indexManager.updateIndices(
      document: documentToUpload,
      documentIri: documentIri,
      physicalTime: physicalTime,
      missingGroupIndices: missingGroupIndices,
    );
    // Success
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

  Future<List<ShardSyncSpec>> _buildShardSyncSpecs(
    IndexSyncSpec idxSpec,
  ) async {
    // Context indices were already filtered by resourceType in _reconcileMetadata
    // Extract shards from all synced indices
    return switch (idxSpec) {
      FullIndexSync() =>
        (await _storage.getDocument(idxSpec.indexIri.getDocumentIri()))!
            .document // we synced it at least once already, must be present
            .getMultiValueObjects<IriTerm>(idxSpec.indexIri, IdxIndex.hasShard)
            .map((shardIri) => FullShardSync(
                shardIri: shardIri, fetchPolicy: idxSpec.fetchPolicy))
            .toList(),
      PartialIndexSync() => Future.value(idxSpec.shardItems.entries
          .map((entry) =>
              PartialShardSync(shardIri: entry.key, resourceIris: entry.value))
          .toList()),
    };
  }

  /// Populate document queue by comparing local and remote shard entries
  Iterable<IriTerm> _buildDocumentQueue(
    IriTerm shardIri,
    RdfGraph? originalRemoteShard,
  ) sync* {
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
        yield localIri.getDocumentIri();
      }
    }

    // 2. In both but different clockHash (concurrent changes)
    for (final localIri in localEntries.keys) {
      if (remoteEntries.containsKey(localIri) &&
          remoteEntries[localIri] != localEntries[localIri]) {
        yield localIri.getDocumentIri();
      }
    }

    // 3. For eager synced indices: Remote but not local
    // TODO: Check if index is eager synced
    final isEagerSynced = true; // Placeholder
    if (isEagerSynced) {
      for (final remoteIri in remoteEntries.keys) {
        if (!localEntries.containsKey(remoteIri)) {
          yield remoteIri.getDocumentIri();
        }
      }
    }
  }

  // =========================================================================
  // Helper Methods
  // =========================================================================

  /// Get local document with metadata from storage
  Future<StoredDocument?> _getLocalDocumentWithMetadata(IriTerm documentIri,
      {int? ifChangedSincePhysicalClock}) async {
    return await _storage.getDocument(
      documentIri,
      ifChangedSincePhysicalClock: ifChangedSincePhysicalClock,
    );
  }

  /// Replaces shard references in a document and generates appropriate CRDT metadata.
  ///
  /// This method:
  /// 1. Extracts old shard references from the document
  /// 2. Compares with new shard list
  /// 3. Generates CRDT metadata for the change (using the merge contract's algorithm)
  /// 4. Applies metadata changes (add new statements, remove old tombstones)
  /// 5. Updates the document with new shard references
  ///
  /// Returns a new RdfGraph with updated shards and proper CRDT metadata.
  Future<RdfGraph> _replaceShardsInDocument({
    required IriTerm documentIri,
    required RdfGraph document,
    required IriTerm resourceIri,
    required Iterable<IriTerm> newShards,
    required MergeContract mergeContract,
    required int physicalClock,
  }) async {
    // Extract old shards
    final oldShards = document
        .findTriples(
          subject: documentIri,
          predicate: SyncManagedDocument.idxBelongsToIndexShard,
        )
        .map((t) => t.object as IriTerm)
        .toList();

    // If shards haven't changed, return original document
    final oldShardsSet = oldShards.toSet();
    final newShardsSet = newShards.toSet();
    if (SetEquality().equals(oldShardsSet, newShardsSet)) {
      return document;
    }

    // Get the resource type
    final typeIri = document.expectSingleObject<IriTerm>(
        documentIri, SyncManagedDocument.managedResourceType)!;

    // Determine CRDT algorithm for idx:belongsToIndexShard
    final algorithmIri = mergeContract.getEffectiveMergeWith(
        typeIri, SyncManagedDocument.idxBelongsToIndexShard);
    final crdtType = _crdtTypeRegistry.getType(algorithmIri);

    // Generate CRDT metadata for the shard change
    final metadata = crdtType.localValueChange(
      oldPropertyValue: oldShards.isNotEmpty
          ? (
              documentIri: documentIri,
              appData:
                  document, // Using document as appData since shards are framework metadata
              blankNodes: IdentifiedBlankNodes.empty<IriTerm>(),
              subject: documentIri,
              predicate: SyncManagedDocument.idxBelongsToIndexShard,
              values: oldShards.cast<RdfObject>(),
            )
          : null,
      newPropertyValue: (
        documentIri: documentIri,
        appData: document,
        blankNodes: IdentifiedBlankNodes.empty<IriTerm>(),
        subject: documentIri,
        predicate: SyncManagedDocument.idxBelongsToIndexShard,
        values: newShards.cast<RdfObject>().toList(),
      ),
      oldFrameworkGraph: document,
      mergeContext: CrdtMergeContext(
        iriGenerator: _iriGenerator,
        metadataGenerator: _metadataGenerator,
      ),
      physicalClock: physicalClock,
    );

    // Build updated document
    final updatedTriples = document.triples.toList();

    // Remove old shard triples
    updatedTriples.removeWhere((t) =>
        t.subject == documentIri &&
        t.predicate == SyncManagedDocument.idxBelongsToIndexShard);

    // Add new shard triples
    updatedTriples.addAll(newShards.map((shard) => Triple(
        documentIri, SyncManagedDocument.idxBelongsToIndexShard, shard)));

    // Apply metadata changes
    for (final node in metadata.statementsToAdd) {
      updatedTriples
          .addNodes(documentIri, SyncManagedDocument.hasStatement, [node]);
    }
    for (final triple in metadata.triplesToRemove) {
      updatedTriples.remove(triple);
    }

    return RdfGraph.fromTriples(updatedTriples);
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

  Future<void> _syncResourceType(
      IriTerm resourceType, int lastSyncTimestamp, DateTime syncTime) async {
    _log.info('Syncing resource type: ${resourceType.debug}');

    // Step 1: Sync Index Documents for this type
    final allIndices =
        await _syncIndexDocuments(resourceType, lastSyncTimestamp, syncTime);
    for (final index in allIndices) {
      await _syncIndex(resourceType, index, lastSyncTimestamp, syncTime);
    }

    _log.info('Completed sync for resource type: ${resourceType.debug}');
  }

  Future<void> _syncIndex(IriTerm resourceType, IndexSyncSpec index,
      int lastSyncTimestamp, DateTime syncTime) async {
    _log.fine('Syncing index: ${index.indexIri.debug}');

    final allShards = await _buildShardSyncSpecs(index);
    for (final shard in allShards) {
      await _syncShard(resourceType, index, shard, lastSyncTimestamp, syncTime);
    }

    _log.info('Completed sync for index: ${index.indexIri.debug}');
  }

  Future<void> _syncShard(IriTerm resourceType, IndexSyncSpec index,
      ShardSyncSpec shard, int lastSyncTimestamp, DateTime syncTime) async {
    final shardIri = shard.shardIri;
    final debugName = 'Shard ${shardIri.debug}';
    _log.fine('Syncing: ${debugName}');
    retryOnConflict(() async {
      // Build Document Sync Queue for this type
      final shardDocumentIri = shardIri.getDocumentIri();
      final merged = await _downloadAndMerge(
          shardDocumentIri, lastSyncTimestamp,
          debugName: debugName);
      if (merged == null) {
        // We do ensure the shards are up to date in Phase 0 of sync function, so
        // we can assume that if there are no changes here, the local and remote shards are
        // already up to date.
        // No changes, nothing to do
        return;
      }
      final originalRemoteShard = merged.originalRemoteDocument;

      final documentQueue = _buildDocumentQueue(
        shardIri,
        originalRemoteShard,
      );

      // sync all the documents in the queue right away
      for (final documentIri in documentQueue) {
        await _syncDocument(documentIri, lastSyncTimestamp, syncTime,
            debugName:
                'Document ${documentIri.debug} (as part of shard ${shardIri.debug})');
      }

      // Phase B: Document & Shard Finalization for this type
      // 1. Determine final_entry_set from index items table
      final finalEntrySet = await _getFinalEntrySet(shardIri);

      // 2. Reconcile merged_shell with final_entry_set
      final finalShardDocument = await _reconcileShardWithEntries(
        merged.mergedDocument,
        finalEntrySet,
      );

      // TODO: is this clock correct? I guess not actually...
      final (_, documentToUpload, clock, missingGroupIndices) =
          await _reconcileDocument(
        shardDocumentIri,
        finalShardDocument,
        merged.mergeContract,
      );

      // 3. Upload with conditional PUT - this might throw ConcurrentUpdateException
      await _applyAndStoreMergedDocument(
        documentIri: shardDocumentIri,
        clock: clock,
        documentToUpload: documentToUpload,
        localUpdatedAt: merged.localUpdatedAt,
        missingGroupIndices: missingGroupIndices,
        syncTime: syncTime,
        typeIri: resourceType,
        etag: merged.etag,
      );
    });
  }
}
