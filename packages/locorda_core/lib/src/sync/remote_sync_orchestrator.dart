import 'package:collection/collection.dart';
import 'package:locorda_core/locorda_core.dart';
import 'package:locorda_core/src/index/index_config_base.dart';
import 'package:locorda_core/src/local_document_merger.dart';
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
import 'package:locorda_core/src/sync/shard_document_generator.dart';
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

/// Partial shard sync for foreign indices.
/// Only syncs specific resources from the shard (upload-only, no prefetch).
final class PartialShardSync extends ShardSyncSpec {
  /// Specific resource IRIs to sync in this shard
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
  final LocalDocumentMerger _localDocumentMerger;
  final ShardDocumentGenerator _shardDocumentGenerator;

  RemoteSyncOrchestrator({
    required RemoteStorage remoteStorage,
    required Storage storage,
    required RemoteDocumentMerger merger,
    required SyncGraphConfig config,
    required IndexRdfGenerator indexRdfGenerator,
    required IndexManager indexManager,
    required ShardDeterminer shardDeterminer,
    required HlcService hlcService,
    required MergeContractLoader mergeContractLoader,
    required LocalDocumentMerger localDocumentMerger,
    required ShardDocumentGenerator shardDocumentGenerator,
  })  : _remoteStorage = remoteStorage,
        _storage = storage,
        _merger = merger,
        _config = config,
        _indexRdfGenerator = indexRdfGenerator,
        _indexManager = indexManager,
        _shardDeterminer = shardDeterminer,
        _hlcService = hlcService,
        _mergeContractLoader = mergeContractLoader,
        _localDocumentMerger = localDocumentMerger,
        _shardDocumentGenerator = shardDocumentGenerator;

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
        await _syncResourceType(resourceType, lastSyncTimestamp, syncTime);
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

    final configuredIndices = <IndexSyncSpec>[
      ...fullIndices,
      ...groupIndexTuples,
    ];

    // Collect configured index IRIs for deduplication
    final configuredIndexIris =
        configuredIndices.map((spec) => spec.indexIri).toSet();

    // Find foreign indices: indices with dirty/uncovered entries but not configured
    final foreignIndices = await _findForeignIndices(
      resourceType: resourceType,
      configuredIndexIris: configuredIndexIris,
    );

    final indices = <IndexSyncSpec>[
      ...configuredIndices,
      ...foreignIndices,
    ];

    _log.fine(
        'Found ${configuredIndices.length} configured indices and ${foreignIndices.length} foreign indices for ${resourceType.debug}');

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
      final governanceIris = _mergeContractLoader.getMergedGovernanceIris([
        if (localDocument != null) localDocument,
        if (downloadResult.graph != null) downloadResult.graph!
      ], documentIri);
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
            await _reconcileDocumentShards(
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
          debugName: debugName,
        );
      } on ConcurrentUpdateException {
        // Conflict detected during upload or local save - retry entire download+merge+upload
        _log.fine('Conflict detected while syncing $debugName, retrying...');
        rethrow;
      } catch (e, st) {
        _log.warning('Error syncing $debugName', e, st);
        rethrow;
      }
    }, debugOperationName: 'syncing $debugName');
  }

  Future<
      (
        IriTerm typeIri,
        RdfGraph document,
        CurrentCrdtClock clock,
        List<MissingGroupIndex> missingGroupIndices
      )> _reconcileDocumentShards(
    IriTerm documentIri,
    RdfGraph mergedDocument,
    MergeContract mergeContract,
  ) async {
    final resourceIri = mergedDocument.expectSingleObject<IriTerm>(
        documentIri, SyncManagedDocument.foafPrimaryTopic)!;
    final typeIri =
        mergedDocument.expectSingleObject<IriTerm>(resourceIri, Rdf.type)!;
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
    final document = await _localDocumentMerger.replaceInDocument(
        documentIri: documentIri,
        document: mergedDocument,
        mergeContract: mergeContract,
        physicalClock: clock.physicalTime,
        changes: [
          (
            subject: documentIri,
            subjectTypeIri: SyncManagedDocument.classIri,
            predicate: SyncManagedDocument.idxBelongsToIndexShard,
            newObjects: shards.shards,
          )
        ]);
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
    final updatedAtTimestamp = syncTime.millisecondsSinceEpoch;
    // save locally with optimistic lock - retry if conflict detected
    try {
      await _storage.saveDocument(
        documentIri,
        typeIri,
        documentToUpload,
        DocumentMetadata(
            ourPhysicalClock: physicalTime, updatedAt: updatedAtTimestamp),
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

    // TODO: how do we assure that the updateIndices call is also
    // executed if sync was aborted shortly before here (e.g. app crash)?
    await _indexManager.updateIndices(
      document: documentToUpload,
      documentIri: documentIri,
      physicalTime: physicalTime,
      resourceTypeIri: typeIri,
      missingGroupIndices: missingGroupIndices,
      updatedAt: updatedAtTimestamp,
    );
    // Success
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
  ///
  /// Implements the 3-category system from the specification:
  /// 1. Local entries not in remote (new local documents)
  /// 2. Entries in both with different clockHash (concurrent changes)
  /// 3. Remote entries not in local (eager synced indices only)
  Future<Set<IriTerm>> _buildDocumentQueue(
    ShardSyncSpec shard,
    RdfGraph? originalRemoteShard,
  ) async {
    // FIXME: I believe that the save_36 bug is somewhere around here
    // Apparently, the documents from the original remote shard are not returned
    // correctly, leading to missing entries in the document queue.
    switch (shard) {
      case PartialShardSync():
        print(
            'PartialShardSync for ${shard.shardIri.debug} - syncing ${shard.resourceIris.length} resources ${shard.resourceIris.map((iri) => iri.debug).join(', ')}');
        // For partial shard sync, just enqueue the specified resource IRIs
        return shard.resourceIris
            .map((resourceIri) => resourceIri.getDocumentIri())
            .toSet();
      case FullShardSync():
        // Continue to full sync logic below
        break;
    }
    final filter = shard.fetchPolicy is PrefetchFiltered
        ? (shard.fetchPolicy as PrefetchFiltered)
        : null;
    final shardIri = shard.shardIri;
    final documentQueue = <IriTerm>{};

    // Parse local entries from index items table
    final localEntries = <IriTerm,
        (
      String clockHash,
      Set<RdfObject>? filterValues
    )>{}; // resourceIri -> clockHash
    final localIndexEntries =
        await _storage.getActiveIndexEntriesForShard(shardIri);
    for (final entry in localIndexEntries) {
      final Set<RdfObject>? filterValues;
      if (filter != null && entry.headerProperties != null) {
        final graph = turtle.decode(entry.headerProperties!);
        filterValues = graph.getMultiValueObjects(
            entry.resourceIri, filter.filterPredicate);
      } else {
        filterValues = null;
      }
      localEntries[entry.resourceIri] = (entry.clockHash, filterValues);
    }

    // Parse remote entries from original remote shard document
    final remoteEntries = <IriTerm,
        (
      String hash,
      Set<RdfObject>? filterValues
    )>{}; // resourceIri -> clockHash
    if (originalRemoteShard != null) {
      // Find all idx:containsEntry links (shardIri is the resource IRI)
      for (final entryIri in originalRemoteShard
          .getMultiValueObjectList<IriTerm>(shardIri, IdxShard.containsEntry)) {
        // Extract idx:resource and cm:clockHash from entry
        final resourceIri = originalRemoteShard.expectSingleObject<IriTerm>(
            entryIri, IdxShardEntry.resource);
        final clockHash = originalRemoteShard.expectSingleObject<LiteralTerm>(
            entryIri, IdxShardEntry.crdtClockHash);
        if (resourceIri != null && clockHash != null) {
          Set<RdfObject>? filterValues = filter == null
              ? null
              : originalRemoteShard.getMultiValueObjects<RdfObject>(
                  entryIri, filter.filterPredicate);
          remoteEntries[resourceIri] = (clockHash.value, filterValues);
        }
      }
    }

    for (final localIri in localEntries.keys) {
      // Category 1: Local but not in remote (new local documents)
      if (!remoteEntries.containsKey(localIri)) {
        documentQueue.add(localIri.getDocumentIri());
      } else if (remoteEntries[localIri]?.$1 != localEntries[localIri]?.$1) {
        // Category 2: In both but different clockHash (concurrent changes)
        documentQueue.add(localIri.getDocumentIri());
      }
    }

    // Category 3: For eager synced indices: Remote but not local
    if (shard.fetchPolicy is Prefetch ||
        shard.fetchPolicy is PrefetchFiltered) {
      for (final remoteIri in remoteEntries.keys) {
        if (!localEntries.containsKey(remoteIri)) {
          if (filter == null ||
              (remoteEntries[remoteIri]?.$2?.any(
                      (value) => filter.acceptedObjectValues.contains(value)) ==
                  true)) {
            documentQueue.add(remoteIri.getDocumentIri());
          }
        }
      }
    }

    print(
        'Document queue for shard ${shard.shardIri.debug}: ${documentQueue.map((iri) => iri.debug).join(', ')}');
    return documentQueue;
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

  /// Get final entry set for a shard from index items table
  Future<Set<IndexEntryWithIri>> _getFinalEntrySet(IriTerm shardIri,
      {Set<IriTerm>? limitToResourceIris}) async {
    final entries = await _storage.getActiveIndexEntriesForShard(shardIri);

    // For partial shard sync, filter to only the specified resources
    if (limitToResourceIris != null) {
      return entries
          .where((entry) => limitToResourceIris.contains(entry.resourceIri))
          .toSet();
    }

    return entries.toSet();
  }

  /// Find foreign indices that need partial sync for a given resource type.
  ///
  /// Foreign indices are those not explicitly configured/subscribed but containing
  /// items that:
  /// 1. Were modified locally (dirty entries need upload)
  /// 2. Are present in our local DB but not covered by any configured shard
  ///
  /// Returns PartialIndexSync specs for each foreign index with its shards.
  Future<List<PartialIndexSync>> _findForeignIndices({
    required IriTerm resourceType,
    required Set<IriTerm> configuredIndexIris,
  }) async {
    // Get last sync timestamp to find dirty entries
    final lastSync =
        await _storage.getLastRemoteSyncTimestamp(_remoteStorage.remoteId);

    // Query for foreign index shards
    // This finds indices (not in configured set) with:
    // - Entries modified since last sync (dirty), OR
    // - Entries in shards not yet synced (uncovered)
    final foreignIndexShards = await _storage.getForeignIndexShardsToSync(
      sinceTimestamp: lastSync,
      resourceType: resourceType,
      excludeIndexIris: configuredIndexIris,
    );
    print(
        'Configured indices: ${configuredIndexIris.map((e) => e.debug).join(', ')} for resource type ${resourceType.debug}');
    print(
        'Foreign index shards to sync: ${foreignIndexShards.entries.map((e) => e.key.debug).join(', ')}');
    // Convert to PartialIndexSync specs
    final foreignIndices = foreignIndexShards.entries
        .map((entry) => PartialIndexSync(
              indexIri: entry.key,
              shardItems: entry.value,
            ))
        .toList();

    if (foreignIndices.isNotEmpty) {
      final totalShards = foreignIndices
          .map((i) => i.shardItems.length)
          .reduce((a, b) => a + b);
      _log.info(
          'Found ${foreignIndices.length} foreign indices with $totalShards shards to sync for ${resourceType.debug}');
    }

    return foreignIndices;
  }

  Future<void> _syncResourceType(
      IriTerm resourceType, int lastSyncTimestamp, DateTime syncTime) async {
    _log.info('Syncing resource type: ${resourceType.debug}');

    // Step 1: Sync Index Documents for this type
    final allIndices =
        await _syncIndexDocuments(resourceType, lastSyncTimestamp, syncTime);

    // Step 2: For each index, sync its shards and documents
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
    await retryOnConflict(() async {
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

      final documentQueue = await _buildDocumentQueue(
        shard,
        originalRemoteShard,
      );

      // sync all the documents in the queue right away
      for (final documentIri in documentQueue) {
        print(
            'Syncing document: ${documentIri.debug} for shard ${shardIri.debug}');
        await _syncDocument(documentIri, lastSyncTimestamp, syncTime,
            debugName:
                'Document ${documentIri.debug} (as part of ${debugName})');
      }

      // Phase B: Document & Shard Finalization for this type
      // 1. Determine final_entry_set from index items table
      //
      // For full shard sync: Use all entries from index items table
      // For partial shard sync (foreign indices): Only use entries for resources
      // we explicitly synced (from documentQueue). This ensures we don't remove
      // remote entries we haven't seen - we only update our own items.
      final Set<IriTerm>? limitToResources = switch (shard) {
        FullShardSync(fetchPolicy: Prefetch()) => null, // All entries
        FullShardSync(fetchPolicy: OnRequest() || PrefetchFiltered()) =>
          documentQueue, // Only synced resources
        PartialShardSync() => documentQueue, // Only synced resources
      };

      final finalEntrySet = await _getFinalEntrySet(shardIri,
          limitToResourceIris: limitToResources);
      //print('Final entry set for shard ${shardIri.debug}: '
      //    '${finalEntrySet.map((e) => e.resourceIri.debug).toList()}\n limitToResources: ${limitToResources?.map((e) => e.debug).toList()}');

      // 2. Generate shard nodes from final entry set
      //
      // For partial sync, we need to merge these with existing remote entries
      // rather than replacing everything
      final newShardNodes = _shardDocumentGenerator.generateShardNodes(
          shardDocumentIri: shardDocumentIri,
          shardResourceIri: shardIri,
          entries: finalEntrySet);

      final RdfGraph updatedShardDocument;
      final entriesToKeep = _computeEntriesToKeep(
          limitToResources, merged.mergedDocument, shardIri);

      // Build document with kept entries but without the other old ones
      final withoutEntries = merged.mergedDocument.subgraph(
        shardDocumentIri,
        filter: (triple, depth) {
          if (triple.predicate == IdxShard.containsEntry &&
              (entriesToKeep == null ||
                  !entriesToKeep.contains(triple.object))) {
            return TraversalDecision.skip;
          }
          return TraversalDecision.include;
        },
      );

      // Add new/current entries
      updatedShardDocument = withoutEntries.withNodes(
          shardIri, IdxShard.containsEntry, newShardNodes);

      // Determine if we need to increment the clock for this shard.
      // Shard documents contain derived state from index items, but they participate
      // in CRDT synchronization. We increment our clock when we have local changes
      // to reflect in the shard - i.e., when any of our local index entries are
      // newer than the merged shard's current clock.
      final ourCurrentShardClock =
          _hlcService.getCurrentClock(merged.mergedDocument, shardDocumentIri);

      // Check if any of our final entry set items have a higher physical clock
      // than our current clock entry in the merged shard document.
      // This indicates we have local changes that need to be reflected.
      final bool hasLocalChanges = finalEntrySet.any((entry) =>
          entry.ourPhysicalClock > ourCurrentShardClock.physicalTime);

      final clock = hasLocalChanges
          ? _hlcService.createOrIncrementClock(
              merged.mergedDocument, shardDocumentIri)
          : ourCurrentShardClock;

// FIXME: is this correct?
      final (oldBlankNodes: _, newBlankNodes: _, metadata: metadata) =
          _localDocumentMerger.generateMetadata(
        shardDocumentIri,
        updatedShardDocument,
        merged.mergedDocument,
        merged.mergedDocument,
        merged.mergeContract,
        clock,
        appDataTypeIri: IdxShard.classIri,
        // optimization: shard documents should not have blank nodes
        computeCanonicalBlankNodes: false,
      );
      final finalShardDocument = _applyMetadataToDocument(
          updatedShardDocument, metadata, shardDocumentIri);

      final (_, documentToUpload, clock2, missingGroupIndices) =
          await _reconcileDocumentShards(
        shardDocumentIri,
        finalShardDocument,
        merged.mergeContract,
      );

      // 3. Upload with conditional PUT - this might throw ConcurrentUpdateException
      await _applyAndStoreMergedDocument(
        documentIri: shardDocumentIri,
        clock: clock2,
        documentToUpload: documentToUpload,
        localUpdatedAt: merged.localUpdatedAt,
        missingGroupIndices: missingGroupIndices,
        syncTime: syncTime,
        typeIri: resourceType,
        etag: merged.etag,
        debugName: debugName,
      );
    }, debugOperationName: 'syncing ${debugName}');
  }

  Set<IriTerm>? _computeEntriesToKeep(
      Set<IriTerm>? limitToResources, RdfGraph document, IriTerm shardIri) {
    if (limitToResources != null) {
      final Set<IriTerm> entriesToKeep = {};
      // Partial sync: Keep remote entries for resources not in our sync set
      // Only update/remove entries for resources we explicitly synced

      // Extract existing entries from merged document, keeping only those
      // not in our synced set
      final existingEntries = document.getMultiValueObjects<IriTerm>(
          shardIri, IdxShard.containsEntry);

      for (final entryIri in existingEntries) {
        final resourceIri = document.expectSingleObject<IriTerm>(
            entryIri, IdxShardEntry.resource);
        if (resourceIri != null && !limitToResources.contains(resourceIri)) {
          // Keep this remote entry - it's not one we synced
          entriesToKeep.add(entryIri);
        }
      }
      return entriesToKeep;
    }
    return null;
  }

  RdfGraph _applyMetadataToDocument(RdfGraph document,
      CrdtMetadataResult metadata, IriTerm shardDocumentIri) {
    if (metadata.triplesToRemove.isEmpty && metadata.statements.isEmpty) {
      return document;
    }
    final finalShardDocumentTriples = document.triples.toSet();
    finalShardDocumentTriples.removeAll(metadata.triplesToRemove);
    finalShardDocumentTriples.addNodes(shardDocumentIri,
        SyncManagedDocument.hasStatement, metadata.statements);
    final finalShardDocument = RdfGraph.fromTriples(finalShardDocumentTriples);
    return finalShardDocument;
  }
}
