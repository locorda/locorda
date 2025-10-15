import 'package:locorda_core/locorda_core.dart';
import 'package:locorda_core/src/index/index_rdf_generator.dart';
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
  RemoteSyncOrchestrator({
    required Storage storage,
    required RemoteStorage remoteStorage,
    required SyncGraphConfig config,
    required IndexRdfGenerator indexRdfGenerator,
  })  : _storage = storage,
        _remoteStorage = remoteStorage,
        _config = config,
        _indexRdfGenerator = indexRdfGenerator,
        _merger = RemoteDocumentMerger(storage: storage);

  RemoteId get _remoteId => _remoteStorage.remoteId;

  /// Execute complete remote synchronization cycle.
  ///
  /// Process:
  /// 1. Phase A: Sync indices, download shards, build document queue
  /// 2. Phase B: Process documents, finalize shards
  Future<void> sync(DateTime syncTime, int lastSyncTimestamp) async {
    _log.info('Starting remote synchronization cycle');

    try {
      // Phase A: Metadata Reconciliation & Queue Building
      final syncContext = await _reconcileMetadata();

      // Phase B: Document & Shard Finalization
      await _syncDocumentsAndFinalizeShards(syncContext);

      _log.info('Remote synchronization cycle completed successfully');
    } catch (e, st) {
      _log.severe('Remote synchronization cycle failed', e, st);
      rethrow;
    }
  }

  /// Phase A: Metadata Reconciliation & Queue Building
  ///
  /// Process:
  /// 1. Sync Index Documents (conditional GET + upload loop with retry)
  /// 2. Build Document Sync Queue by comparing local and remote shards
  ///
  /// Returns: SyncContext with document queue and shard state
  Future<SyncContext> _reconcileMetadata() async {
    _log.info('Phase A: Metadata Reconciliation & Queue Building');

    // Step 1: Sync Index Documents
    final allIndices = await _syncIndexDocuments();
    final syncContext = SyncContext(indices: allIndices);

    // Step 2: Build Document Sync Queue
    await _buildDocumentSyncQueue(syncContext);

    _log.info(
        'Phase A complete: ${syncContext.documentQueue.length} documents queued');
    return syncContext;
  }

  /// Phase B: Document & Shard Finalization
  ///
  /// Process:
  /// 1. Process Document Sync Queue (download + merge + upload each document)
  /// 2. Finalize Shards (transactional loop with retry on 412)
  ///
  /// Parameters:
  /// - [syncContext]: Context from Phase A containing document queue and shard state
  Future<void> _syncDocumentsAndFinalizeShards(SyncContext syncContext) async {
    _log.info('Phase B: Document & Shard Finalization');

    // Step 1: Process Document Sync Queue
    await _processDocumentSyncQueue(syncContext);

    // Step 2: Finalize Shards
    await _finalizeShards(syncContext);

    _log.info('Phase B complete');
  }

  /// Step A.1: Sync Index Documents
  ///
  /// For each configured index:
  /// 1. Conditional GET using stored ETag
  /// 2. Handle 200/304/404 responses
  /// 3. Merge if needed
  /// 4. Upload loop with retry on 412 conflict
  Future<List<(IriTerm, ItemFetchPolicy)>> _syncIndexDocuments() async {
    _log.fine('Syncing index documents');

    final fullIndices = _config.resources.expand((resource) =>
        resource.indices.whereType<FullIndexGraphConfig>().map((index) {
          final iri =
              _indexRdfGenerator.generateFullIndexIri(index, resource.typeIri);
          return (iri, index.itemFetchPolicy);
        }));
    final groupIndices = await _storage.getAllSubscribedGroupIndices();
    final indices = <(IriTerm, ItemFetchPolicy)>[
      ...fullIndices,
      ...groupIndices
    ];

    for (final (indexIri, _) in indices) {
      await _syncSingleIndexDocument(indexIri);
    }
    return indices;
  }

  /// Sync a single index document with retry loop on 412
  Future<void> _syncSingleIndexDocument(IriTerm indexIri) async {
    _log.fine('Syncing index: $indexIri');

    while (true) {
      try {
        // 1. Conditional GET
        final indexDocumentIri = indexIri.getDocumentIri();
        final cachedETag = await _storage.getRemoteETag(
          _remoteId,
          indexDocumentIri,
        );

        final downloadResult = await _remoteStorage.download(
          indexDocumentIri,
          ifNoneMatch: cachedETag,
        );

        RdfGraph? preparedIndex;

        // 2. Handle response cases
        if (downloadResult.notModified) {
          // Case: 304 Not Modified
          _log.fine('Index $indexIri unchanged (304)');
          // TODO: Determine if local index needs upload (check index items table)
          // For now, assume no local changes needed - index is up-to-date
          break;
        } else if (downloadResult.graph != null) {
          // Case: 200 OK - Remote changed
          _log.fine('Index $indexIri changed remotely');
          final localIndex = await _getLocalIndexDocument(indexIri);

          // CRDT merge local + remote
          final mergeResult = await _merger.merge(
            documentIri: indexIri,
            localGraph: localIndex,
            remoteGraph: downloadResult.graph,
          );

          preparedIndex = mergeResult.mergedGraph;

          // Update ETag cache
          if (downloadResult.etag != null) {
            await _storage.setRemoteETag(
                _remoteId, indexDocumentIri, downloadResult.etag!);
          }
        } else {
          // Case: 404 Not Found - New index
          _log.fine('Index $indexIri not found remotely (404)');
          preparedIndex = await _getLocalIndexDocument(indexIri);
        }

        // 3. Upload loop (if needed)
        if (preparedIndex != null) {
          final uploadSuccess = await _uploadWithRetry(
            path: indexDocumentIri,
            graph: preparedIndex,
            etag: downloadResult.etag,
          );

          if (uploadSuccess) {
            break; // Success
          }
          // If upload returned false, we got 412 - retry entire step
          _log.fine('Got 412 conflict, restarting index sync for $indexIri');
          continue;
        }

        break; // No upload needed
      } catch (e, st) {
        _log.warning('Error syncing index $indexIri', e, st);
        rethrow;
      }
    }
  }

  /// Step A.2: Build Document Sync Queue
  ///
  /// For each shard in each index:
  /// 1. Conditional GET for shard
  /// 2. Create merged_shell (current_local_shard_state merged with remote)
  /// 3. Populate document queue based on differences
  Future<void> _buildDocumentSyncQueue(SyncContext context) async {
    _log.fine('Building document sync queue');

    // TODO: Get shards from processed indices
    final shards = <IriTerm>[];
    _log.warning('TODO: Get shards from processed indices');

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
        await _storage.getRemoteETag(_remoteId, shardDocumentIri);

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

      // CRDT merge current_local_shard_state with remote
      final mergeResult = await _merger.merge(
        documentIri: shardIri,
        localGraph: localShardDoc?.document,
        remoteGraph: downloadResult.graph,
      );

      mergedShell = mergeResult.mergedGraph;

      // Update ETag cache
      if (downloadResult.etag != null) {
        await _storage.setRemoteETag(
            _remoteId, shardDocumentIri, downloadResult.etag!);
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
  Future<void> _processDocumentSyncQueue(SyncContext context) async {
    _log.fine('Processing ${context.documentQueue.length} documents');

    for (final documentIri in context.documentQueue) {
      await _processDocument(documentIri, context);
    }
  }

  /// Process a single document: download, merge, save, upload
  Future<void> _processDocument(
      IriTerm documentIri, SyncContext context) async {
    _log.fine('Processing document: $documentIri');

    // 1. Conditional GET

    final cachedETag = await _storage.getRemoteETag(_remoteId, documentIri);

    RemoteDownloadResult downloadResult;
    try {
      downloadResult = await _remoteStorage.download(
        documentIri,
        ifNoneMatch: cachedETag,
      );
    } catch (e) {
      // Treat as 404 - new document
      downloadResult = RemoteDownloadResult(graph: null, etag: null);
    }

    // 2. Get local version
    final localDoc = await _storage.getDocument(documentIri);

    RdfGraph? mergedGraph;
    bool needsUpload = false;

    // 3. Handle response cases
    if (downloadResult.notModified) {
      // Case: 304 Not Modified - purely local change
      _log.fine('Document $documentIri unchanged remotely (304)');
      mergedGraph = localDoc?.document;
      needsUpload = true;
    } else if (downloadResult.graph != null) {
      // Case: 200 OK - remote changed
      _log.fine('Document $documentIri changed remotely');

      // CRDT merge
      final mergeResult = await _merger.merge(
        documentIri: documentIri,
        localGraph: localDoc?.document,
        remoteGraph: downloadResult.graph,
      );

      mergedGraph = mergeResult.mergedGraph;
      needsUpload = mergeResult.hasLocalChanges;

      // Update ETag
      if (downloadResult.etag != null) {
        await _storage.setRemoteETag(
            _remoteId, documentIri, downloadResult.etag!);
      }
    } else {
      // Case: 404 Not Found - new local document
      _log.fine('Document $documentIri not found remotely (404)');
      mergedGraph = localDoc?.document;
      needsUpload = true;
    }

    // 4. Save merged result locally
    if (mergedGraph != null) {
      // TODO: Save to local storage and update index items table
      _log.warning('TODO: Save merged document $documentIri to storage');
    }

    // 5. Upload if needed (with retry loop)
    if (needsUpload && mergedGraph != null) {
      await _uploadDocumentWithRetry(
        documentIri: documentIri,
        graph: mergedGraph,
        etag: downloadResult.etag,
      );
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
              _remoteId, shardDocumentIri, uploadResult.etag!);
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
  Future<bool> _uploadWithRetry({
    required IriTerm path,
    required RdfGraph graph,
    String? etag,
  }) async {
    final uploadResult = await _remoteStorage.upload(
      path,
      graph,
      ifMatch: etag,
    );

    if (uploadResult.conflict) {
      return false; // Signal caller to retry
    }

    // Success - cache new ETag
    if (uploadResult.etag != null) {
      await _storage.setRemoteETag(_remoteId, path, uploadResult.etag!);
    }

    return true;
  }

  /// Upload document with retry loop on 412
  Future<void> _uploadDocumentWithRetry({
    required IriTerm documentIri,
    required RdfGraph graph,
    String? etag,
  }) async {
    final remotePath = documentIri;

    while (true) {
      final uploadResult = await _remoteStorage.upload(
        remotePath,
        graph,
        ifMatch: etag,
      );

      if (uploadResult.conflict) {
        // 412 - re-fetch and re-merge
        _log.fine('Got 412 on document $documentIri, retrying');

        final downloadResult = await _remoteStorage.download(remotePath);
        final localDoc = await _storage.getDocument(documentIri);

        final mergeResult = await _merger.merge(
          documentIri: documentIri,
          localGraph: localDoc?.document,
          remoteGraph: downloadResult.graph,
        );

        // Retry upload with new merged state
        graph = mergeResult.mergedGraph;
        etag = downloadResult.etag;
        continue;
      }

      // Success
      if (uploadResult.etag != null) {
        await _storage.setRemoteETag(_remoteId, remotePath, uploadResult.etag!);
      }
      break;
    }
  }

  /// Get local index document from storage
  Future<RdfGraph?> _getLocalIndexDocument(IriTerm indexIri) async {
    final doc = await _storage.getDocument(indexIri);
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
