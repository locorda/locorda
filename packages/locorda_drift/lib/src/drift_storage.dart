/// Drift-based implementation of Storage interface.
library;

import 'dart:convert';

import 'package:drift_flutter/drift_flutter.dart';
import 'package:locorda_core/locorda_core.dart';
import 'package:locorda_core/src/storage/storage_interface.dart' as storage;
import 'package:rdf_core/rdf_core.dart';

import 'sync_database.dart';

/// Drift-based implementation of the Storage interface.
///
/// Provides cross-platform SQLite storage for RDF documents, CRDT metadata,
/// and property-level change tracking using the Drift ORM.
class DriftStorage implements Storage {
  final SyncDocumentDao documentDao;
  final SyncPropertyChangeDao propertyChangeDao;
  final IndexDao indexDao;
  final RemoteSyncStateDao remoteSyncStateDao;
  final SyncDatabase _database;
  final RdfGraphCodec _codec;
  final IriTermFactory _iriTermFactory;

  bool _initialized = false;

  DriftStorage._({
    required this.documentDao,
    required this.propertyChangeDao,
    required this.indexDao,
    required this.remoteSyncStateDao,
    required SyncDatabase database,
    IriTermFactory iriTermFactory = IriTerm.validated,
  })  : _database = database,
        _iriTermFactory = iriTermFactory,
        _codec = TurtleCodec(iriTermFactory: iriTermFactory);

  /// Create DriftStorage with database options
  factory DriftStorage({
    DriftWebOptions? web,
    DriftNativeOptions? native,
    IriTermFactory iriTermFactory = IriTerm.validated,
  }) {
    final database = SyncDatabase(web: web, native: native);

    return DriftStorage._(
        documentDao: database.syncDocumentDao,
        propertyChangeDao: database.syncPropertyChangeDao,
        indexDao: database.indexDao,
        remoteSyncStateDao: database.remoteSyncStateDao,
        database: database,
        iriTermFactory: iriTermFactory);
  }

  /// Create DriftStorage with custom database instance (for testing)
  factory DriftStorage.withDatabase(
    SyncDatabase database, {
    IriTermFactory iriTermFactory = IriTerm.validated,
  }) {
    return DriftStorage._(
      documentDao: database.syncDocumentDao,
      propertyChangeDao: database.syncPropertyChangeDao,
      indexDao: database.indexDao,
      remoteSyncStateDao: database.remoteSyncStateDao,
      database: database,
      iriTermFactory: iriTermFactory,
    );
  }

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
  }

  @override
  Future<void> close() async {
    if (_initialized) {
      await _database.close();
      _initialized = false;
    }
  }

  @override
  Future<SaveDocumentResult> saveDocument(
      IriTerm documentIri,
      IriTerm typeIri,
      RdfGraph document,
      DocumentMetadata metadata,
      List<PropertyChange> changes) async {
    return await _database.transaction(() async {
      // Get previous cursor for this type
      final previousTimestamp =
          await documentDao.getMaxUpdatedAtForType(typeIri.value);
      final previousCursor = previousTimestamp?.toString();

      // Validate that new timestamp is greater than existing max
      if (previousTimestamp != null &&
          metadata.updatedAt <= previousTimestamp) {
        throw ArgumentError(
            'New document updatedAt (${metadata.updatedAt}) must be greater than '
            'existing max updatedAt ($previousTimestamp) for type ${typeIri.value}');
      }

      // Serialize RDF graph to Turtle
      final content = _codec.encode(document, baseUri: documentIri.value);

      // Save document with metadata and get the document ID
      final documentId = await documentDao.saveDocument(
        documentIri: documentIri.value,
        typeIri: typeIri.value,
        content: content,
        ourPhysicalClock: metadata.ourPhysicalClock,
        updatedAt: metadata.updatedAt,
      );

      // Save property changes in batch
      if (changes.isNotEmpty) {
        await propertyChangeDao.recordPropertyChangesBatch(
          documentId: documentId,
          changes: changes,
        );
      }

      return SaveDocumentResult(
        previousCursor: previousCursor,
        currentCursor: metadata.updatedAt.toString(),
      );
    });
  }

  @override
  Future<StoredDocument?> getDocument(
    IriTerm documentIri, {
    int? ifChangedSincePhysicalClock,
  }) async {
    final document = await documentDao.getDocument(
      documentIri.value,
      ifChangedSincePhysicalClock: ifChangedSincePhysicalClock,
    );
    if (document == null) return null;

    // Parse RDF content
    final graph =
        _codec.decode(document.documentContent, documentUrl: documentIri.value);

    return StoredDocument(
      documentIri: documentIri,
      document: graph,
      metadata: DocumentMetadata(
        ourPhysicalClock: document.ourPhysicalClock,
        updatedAt: document.updatedAt,
      ),
    );
  }

  @override
  Future<List<PropertyChange>> getPropertyChanges(IriTerm documentIri,
      {int? sinceLogicalClock}) async {
    final documentId = await documentDao.getDocumentId(documentIri.value);
    if (documentId == null) return [];

    final changes = await propertyChangeDao.getPropertyChanges(
      documentId,
      sinceLogicalClock: sinceLogicalClock,
    );

    return changes
        .map((change) => PropertyChange(
              resourceIri: _iriTermFactory(change.resourceIri),
              propertyIri: _iriTermFactory(change.propertyIri),
              changedAtMs: change.changedAtMs,
              changeLogicalClock: change.changeLogicalClock,
              isFrameworkProperty: change.isFrameworkProperty,
            ))
        .toList();
  }

  @override
  Future<DocumentsResult> getDocumentsModifiedSince(
      IriTerm typeIri, String? minCursor,
      {required int limit}) async {
    final documents = await documentDao
        .getDocumentsModifiedSince(typeIri.value, minCursor, limit: limit);
    final storedDocuments = _convertToStoredDocuments(documents);

    // currentCursor: last document's timestamp, or minCursor if no documents found
    // This ensures the cursor never goes backwards
    final currentCursor = storedDocuments.isNotEmpty
        ? storedDocuments.last.metadata.updatedAt.toString()
        : minCursor;

    // hasNext: true if we got a full batch (might be more data available)
    final hasNext = documents.length >= limit;

    return DocumentsResult(
      documents: storedDocuments,
      currentCursor: currentCursor,
      hasNext: hasNext,
    );
  }

  @override
  Future<DocumentsResult> getDocumentsChangedByUsSince(
      IriTerm typeIri, String? minCursor,
      {required int limit}) async {
    final documents = await documentDao
        .getDocumentsChangedByUsSince(typeIri.value, minCursor, limit: limit);
    final storedDocuments = _convertToStoredDocuments(documents);

    // currentCursor: last document's timestamp, or minCursor if no documents found
    // This ensures the cursor never goes backwards
    final currentCursor = storedDocuments.isNotEmpty
        ? storedDocuments.last.metadata.ourPhysicalClock.toString()
        : minCursor;

    // hasNext: true if we got a full batch (might be more data available)
    final hasNext = documents.length >= limit;

    return DocumentsResult(
      documents: storedDocuments,
      currentCursor: currentCursor,
      hasNext: hasNext,
    );
  }

  @override
  Stream<DocumentsResult> watchDocumentsModifiedSince(
      IriTerm typeIri, String? minCursor) {
    return documentDao
        .watchDocumentsModifiedSince(typeIri.value, minCursor)
        .map((documents) {
      final storedDocuments = _convertToStoredDocuments(documents);

      // For watch streams: currentCursor is the latest data, or minCursor if no docs
      // hasNext is always false for streams (they don't paginate)
      final cursor = storedDocuments.isNotEmpty
          ? storedDocuments.last.metadata.updatedAt.toString()
          : minCursor;

      return DocumentsResult(
        documents: storedDocuments,
        currentCursor: cursor,
        hasNext: false,
      );
    });
  }

  @override
  Stream<DocumentsResult> watchDocumentsChangedByUsSince(
      IriTerm typeIri, String? minCursor) async* {
    await for (final documents in documentDao.watchDocumentsChangedByUsSince(
        typeIri.value, minCursor)) {
      final storedDocuments = _convertToStoredDocuments(documents);

      // For watch streams: currentCursor is the latest data, or minCursor if no docs
      // hasNext is always false for streams (they don't paginate)
      final cursor = storedDocuments.isNotEmpty
          ? storedDocuments.last.metadata.ourPhysicalClock.toString()
          : minCursor;

      yield DocumentsResult(
        documents: storedDocuments,
        currentCursor: cursor,
        hasNext: false,
      );
    }
  }

  @override
  Future<Map<String, String>> getSettings(Iterable<String> keys) async {
    if (keys.isEmpty) return {};

    final results = await (_database.select(_database.syncSettings)
          ..where((s) => s.key.isIn(keys.toList())))
        .get();

    return {for (final setting in results) setting.key: setting.value};
  }

  @override
  Future<void> setSetting(String key, String value) async {
    await _database
        .into(_database.syncSettings)
        .insertOnConflictUpdate(SyncSettingsCompanion.insert(
          key: key,
          value: value,
        ));
  }

  // ========================================================================
  // Index Management
  // ========================================================================

  /// Internal helper: Get or create IRI ID from SyncIris table
  /// IndexDao has IriBatchLoader mixin which provides these methods
  Future<int> _getOrCreateIriId(String iri) async {
    return (await indexDao.getOrCreateIriIdsBatch({iri}))[iri]!;
  }

  /// Internal helper: Batch get IRI IDs

  Future<Set<int>> _getOrCreateIriIds(Iterable<String> iris) async {
    return (await indexDao.getOrCreateIriIdsBatch(iris)).values.toSet();
  }

  Future<Map<String, int>> _getOrCreateIriIdsMap(Iterable<String> iris) async {
    return (await indexDao.getOrCreateIriIdsBatch(iris));
  }

  /// Internal helper: Batch get IRIs from IDs
  Future<Map<int, String>> _getIris(Set<int> ids) async {
    return await indexDao.getIrisBatch(ids);
  }

  @override
  Future<storage.IndexEntriesPage> getIndexEntries({
    required Iterable<IriTerm> indexIris,
    int? cursorTimestamp,
    int limit = 100,
  }) async {
    // Translate index IRIs to IDs internally
    final indexIds = await _getOrCreateIriIds(
      indexIris.map((iri) => iri.value),
    );

    // Query directly by index IDs
    final page = await indexDao.getIndexEntries(
      indexIds: indexIds,
      cursorTimestamp: cursorTimestamp,
      limit: limit,
    );

    return storage.IndexEntriesPage(
      entries: page.entries
          .map((e) => storage.IndexEntryWithIri(
                resourceIri: _iriTermFactory(e.resourceIri),
                clockHash: e.entry.clockHash,
                headerProperties: e.entry.headerProperties,
                updatedAt: e.entry.updatedAt,
                isDeleted: e.entry.isDeleted,
                ourPhysicalClock: e.entry.ourPhysicalClock,
              ))
          .toList(),
      hasMore: page.hasMore,
      lastCursor: page.lastCursor,
    );
  }

  @override
  Stream<List<storage.IndexEntryWithIri>> watchIndexEntries({
    required Iterable<IriTerm> indexIris,
    int? cursorTimestamp,
  }) async* {
    // Translate index IRIs to IDs internally
    final indexIds = await _getOrCreateIriIds(
      indexIris.map((iri) => iri.value),
    );

    // Watch using internal IDs
    yield* indexDao
        .watchIndexEntries(
          indexIds: indexIds,
          cursorTimestamp: cursorTimestamp,
        )
        .map((entries) => entries
            .map((e) => storage.IndexEntryWithIri(
                  resourceIri: _iriTermFactory(e.resourceIri),
                  clockHash: e.entry.clockHash,
                  headerProperties: e.entry.headerProperties,
                  updatedAt: e.entry.updatedAt,
                  ourPhysicalClock: e.entry.ourPhysicalClock,
                  isDeleted: e.entry.isDeleted,
                ))
            .toList());
  }

  @override
  Future<void> saveGroupIndexSubscription({
    required IriTerm groupIndexIri,
    required IriTerm groupIndexTemplateIri,
    required ItemFetchPolicy itemFetchPolicy,
    required int createdAt,
  }) async {
    // Translate group index IRI to ID internally
    final ids = await _getOrCreateIriIdsMap(
      [groupIndexIri.value, groupIndexTemplateIri.value],
    );
    final groupIndexIriId = ids[groupIndexIri.value]!;
    final groupIndexTemplateIriId = ids[groupIndexTemplateIri.value]!;
    return indexDao.saveGroupIndexSubscription(
      groupIndexIriId: groupIndexIriId,
      groupIndexTemplateIriId: groupIndexTemplateIriId,
      itemFetchPolicy: json.encode(itemFetchPolicy.toMap()),
      createdAt: createdAt,
    );
  }

  @override
  Future<List<(IriTerm, ItemFetchPolicy)>>
      getAllSubscribedGroupIndices() async {
    final subscriptions = await indexDao.getAllSubscribedGroupIndices();

    return subscriptions.map((subscription) {
      final indexIri = _iriTermFactory(subscription.groupIndexIri);
      final fetchPolicy = ItemFetchPolicy.fromMap(
        json.decode(subscription.itemFetchPolicy),
      );
      return (indexIri, fetchPolicy);
    }).toList();
  }

  @override
  Stream<Set<IriTerm>> watchSubscribedGroupIndexIris(
      IriTerm templateIri) async* {
    // Translate template IRI to ID
    final templateId = await _getOrCreateIriId(templateIri.value);

    // Watch subscribed index IDs from DAO
    await for (final indexIds
        in indexDao.watchSubscribedGroupIndexIds(templateId)) {
      // Translate IDs back to IRIs
      if (indexIds.isEmpty) {
        yield const {};
      } else {
        final idToIri = await _getIris(indexIds);
        yield idToIri.values.map((iri) => _iriTermFactory(iri)).toSet();
      }
    }
  }

  @override
  Future<int> ensureIndexSetVersion({
    required Set<IriTerm> indexIris,
    required int createdAt,
  }) async {
    // Translate index IRIs to IDs internally
    final indexIds = await _getOrCreateIriIds(
      indexIris.map((iri) => iri.value),
    );

    // Store version with IDs (implementation detail)
    return indexDao.ensureIndexIdSetVersion(
      indexIds: indexIds,
      createdAt: createdAt,
    );
  }

  @override
  Future<Set<IriTerm>> getIndexIrisForVersion(int versionId) async {
    // Get index IDs from DAO
    final indexIds = await indexDao.getIndexIriIdsForVersion(versionId);

    // Translate IDs back to IRIs
    if (indexIds.isEmpty) return const {};

    final idToIri = await _getIris(indexIds.toSet());
    return idToIri.values.map((iri) => _iriTermFactory(iri)).toSet();
  }

  @override
  Future<void> saveIndexEntry({
    required IriTerm shardIri,
    required IriTerm indexIri,
    required IriTerm resourceIri,
    required String clockHash,
    String? headerProperties,
    bool isDeleted = false,
    required int ourPhysicalClock,
    required int updatedAt,
  }) async {
    // Translate IRIs to IDs
    final iriIds = await _getOrCreateIriIdsMap([
      shardIri.value,
      indexIri.value,
      resourceIri.value,
    ]);

    final shardIriId = iriIds[shardIri.value]!;
    final indexIriId = iriIds[indexIri.value]!;
    final resourceIriId = iriIds[resourceIri.value]!;

    // Save entry to database
    await indexDao.saveIndexEntry(
      shardIriId: shardIriId,
      indexIriId: indexIriId,
      resourceIriId: resourceIriId,
      clockHash: clockHash,
      headerProperties: headerProperties,
      isDeleted: isDeleted,
      ourPhysicalClock: ourPhysicalClock,
      updatedAt: updatedAt,
    );
  }

  @override
  Future<List<storage.IndexEntryWithIri>> getActiveIndexEntriesForShard(
      IriTerm shardIri) async {
    // Translate shard IRI to ID
    final iriIds = await _getOrCreateIriIdsMap([shardIri.value]);
    final shardIriId = iriIds[shardIri.value]!;

    // Get entries from DAO
    final driftEntries =
        await indexDao.getActiveIndexEntriesForShard(shardIriId);

    // Convert to Storage interface type
    return driftEntries
        .map((driftEntry) => storage.IndexEntryWithIri(
              resourceIri: _iriTermFactory(driftEntry.resourceIri),
              clockHash: driftEntry.entry.clockHash,
              headerProperties: driftEntry.entry.headerProperties,
              updatedAt: driftEntry.entry.updatedAt,
              ourPhysicalClock: driftEntry.entry.ourPhysicalClock,
              isDeleted: driftEntry.entry.isDeleted,
            ))
        .toList();
  }

  @override
  Future<List<(IriTerm iri, int maxPhysicalClock)>> getShardsToUpdate(
      int sinceTimestamp) async {
    final shardIris = await indexDao.getShardsToUpdate(sinceTimestamp);
    return shardIris.map((iri) => (_iriTermFactory(iri.$1), iri.$2)).toList();
  }

  // Note: Sync timestamp helpers are provided by SyncTimestampStorage extension
  // from locorda_core. No need to duplicate them here.

  // ========================================================================
  // Remote ETag Management (Multi-Remote Support)
  // ========================================================================
  // All methods take RemoteId parameter to enable synchronization with
  // multiple remote endpoints simultaneously.

  @override
  Future<String?> getRemoteETag(RemoteId remoteId, IriTerm documentIri) async {
    final documentIriId = await _getOrCreateIriId(documentIri.value);
    final remoteIdInt = await remoteSyncStateDao.getOrCreateRemoteId(
        remoteId.backend, remoteId.id);

    return await remoteSyncStateDao.getETag(
      documentIriId: documentIriId,
      remoteId: remoteIdInt,
    );
  }

  @override
  Future<void> setRemoteETag(
      RemoteId remoteId, IriTerm documentIri, String etag) async {
    final documentIriId = await _getOrCreateIriId(documentIri.value);
    final remoteIdInt = await remoteSyncStateDao.getOrCreateRemoteId(
        remoteId.backend, remoteId.id);

    await remoteSyncStateDao.setETag(
      documentIriId: documentIriId,
      remoteId: remoteIdInt,
      etag: etag,
    );
  }

  @override
  Future<void> clearRemoteETag(RemoteId remoteId, IriTerm documentIri) async {
    final documentIriId = await _getOrCreateIriId(documentIri.value);
    final remoteIdInt = await remoteSyncStateDao.getOrCreateRemoteId(
        remoteId.backend, remoteId.id);

    await remoteSyncStateDao.clearETag(
      documentIriId: documentIriId,
      remoteId: remoteIdInt,
    );
  }

  List<StoredDocument> _convertToStoredDocuments(
      List<DocumentWithIri> documents) {
    return documents.map((doc) {
      final graph =
          _codec.decode(doc.document.documentContent, documentUrl: doc.iri);

      return StoredDocument(
        documentIri: _iriTermFactory(doc.iri),
        document: graph,
        metadata: DocumentMetadata(
          ourPhysicalClock: doc.document.ourPhysicalClock,
          updatedAt: doc.document.updatedAt,
        ),
      );
    }).toList();
  }

  @override
  Future<int> getLastRemoteSyncTimestamp(RemoteId remoteId) async {
    final id = await remoteSyncStateDao.getOrCreateRemoteId(
        remoteId.backend, remoteId.id);
    return remoteSyncStateDao.getRemoteLastSyncTimestamp(id);
  }

  @override
  Future<void> updateLastRemoteSyncTimestamp(
      RemoteId remoteId, int timestamp) async {
    final id = await remoteSyncStateDao.getOrCreateRemoteId(
        remoteId.backend, remoteId.id);
    await remoteSyncStateDao.updateRemoteLastSyncTimestamp(id, timestamp);
  }
}
