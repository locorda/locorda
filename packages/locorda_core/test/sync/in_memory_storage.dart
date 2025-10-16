import 'package:locorda_core/locorda_core.dart';
import 'package:locorda_core/src/generated/_index.dart';
import 'package:locorda_core/src/rdf/rdf_extensions.dart';
import 'package:locorda_core/src/storage/storage_interface.dart';
import 'package:rdf_core/rdf_core.dart';

final _debug = false;
final _print = _debug ? print : (Object? _) {};

/// Simple in-memory storage for testing.
class InMemoryStorage implements Storage {
  final Map<IriTerm, StoredDocument> _documents = {};
  final Map<IriTerm, IriTerm> _documentTypes = {}; // documentIri -> typeIri
  final Map<IriTerm, List<PropertyChange>> _propertyChanges = {};
  final Map<String, String> _settings = {};

  // Index entry storage
  final Map<String, _IndexEntry> _indexEntries =
      {}; // key: "$shardIri|$resourceIri"

  // Note: Sync timestamps now stored in _settings via SyncTimestampStorage extension
  // Remote ETags also stored in _settings

  // Group index subscription storage
  final Map<IriTerm, _GroupIndexSubscription> _groupIndexSubscriptions = {};

  // Index set version storage
  final Map<int, Set<IriTerm>> _indexSetVersions =
      {}; // versionId -> Set<IriTerm>
  final Map<String, int> _indexSetVersionKeys =
      {}; // sorted iris key -> versionId
  int _nextVersionId = 1;

  @override
  Future<void> initialize() async {
    // No-op for in-memory storage
  }

  @override
  Future<void> close() async {
    // No-op for in-memory storage
  }

  @override
  Future<StoredDocument?> getDocument(IriTerm documentIri,
      {int? ifChangedSincePhysicalClock}) async {
    final doc = _documents[documentIri];
    if (doc == null) return null;
    if (ifChangedSincePhysicalClock != null &&
        doc.metadata.ourPhysicalClock <= ifChangedSincePhysicalClock) {
      return null;
    }
    return doc;
  }

  /// Get max updatedAt for all documents of a specific type.
  int? _getMaxUpdatedAtForType(IriTerm typeIri) {
    final docsOfType = _documentTypes.entries
        .where((e) => e.value == typeIri)
        .map((e) => _documents[e.key])
        .whereType<StoredDocument>();

    if (docsOfType.isEmpty) return null;

    return docsOfType
        .map((doc) => doc.metadata.updatedAt)
        .reduce((a, b) => a > b ? a : b);
  }

  @override
  Future<SaveDocumentResult> saveDocument(
      IriTerm documentIri,
      IriTerm typeIri,
      RdfGraph document,
      DocumentMetadata metadata,
      List<PropertyChange> changes) async {
    // Get previous max cursor for this type (not for this document!)
    final previousTimestamp = _getMaxUpdatedAtForType(typeIri);
    final previousCursor = previousTimestamp?.toString();

    _documents[documentIri] = StoredDocument(
      documentIri: documentIri,
      document: document,
      metadata: metadata,
    );
    _documentTypes[documentIri] = typeIri;

    _propertyChanges[documentIri] = [
      ...(_propertyChanges[documentIri] ?? []),
      ...changes
    ];

    return SaveDocumentResult(
      previousCursor: previousCursor,
      currentCursor: metadata.updatedAt.toString(),
    );
  }

  @override
  Future<List<PropertyChange>> getPropertyChanges(IriTerm documentIri,
      {int? sinceLogicalClock}) async {
    final changes = _propertyChanges[documentIri] ?? [];
    if (sinceLogicalClock == null) return changes;

    return changes
        .where((c) => c.changeLogicalClock > sinceLogicalClock)
        .toList();
  }

  void resetPropertyChanges() {
    _propertyChanges.clear();
  }

  @override
  Future<DocumentsResult> getDocumentsModifiedSince(
      IriTerm typeIri, String? minCursor,
      {required int limit}) async {
    return _getDocuments(
      typeIri: typeIri,
      minCursor: minCursor,
      limit: limit,
      timestampExtractor: (doc) => doc.metadata.updatedAt,
    );
  }

  @override
  Future<DocumentsResult> getDocumentsChangedByUsSince(
      IriTerm typeIri, String? minCursor,
      {required int limit}) async {
    return _getDocuments(
      typeIri: typeIri,
      minCursor: minCursor,
      limit: limit,
      timestampExtractor: (doc) => doc.metadata.ourPhysicalClock,
    );
  }

  @override
  Stream<DocumentsResult> watchDocumentsModifiedSince(
      IriTerm typeIri, String? minCursor) async* {
    yield _getDocuments(
      typeIri: typeIri,
      minCursor: minCursor,
      limit: null, // No limit for watch,
      timestampExtractor: (doc) => doc.metadata.updatedAt,
    );
  }

  @override
  Stream<DocumentsResult> watchDocumentsChangedByUsSince(
      IriTerm typeIri, String? minCursor) async* {
    yield _getDocuments(
      typeIri: typeIri,
      minCursor: minCursor,
      limit: null, // No limit for watch,
      timestampExtractor: (doc) => doc.metadata.ourPhysicalClock,
    );
  }

  /// Shared implementation for GET operations with pagination.
  DocumentsResult _getDocuments({
    required IriTerm typeIri,
    required String? minCursor,
    required int? limit,
    required int Function(StoredDocument) timestampExtractor,
  }) {
    final cursorTimestamp = minCursor != null ? int.parse(minCursor) : 0;
    final allFiltered = _documents.values
        .where((doc) => _isType(doc, typeIri))
        .where((doc) => timestampExtractor(doc) > cursorTimestamp)
        .toList()
      ..sort((a, b) => timestampExtractor(a).compareTo(timestampExtractor(b)));

    // Apply limit for pagination
    final filtered =
        limit != null ? allFiltered.take(limit).toList() : allFiltered;

    // currentCursor: last document's timestamp, or minCursor if no documents found
    // This ensures the cursor never goes backwards
    final currentCursor = filtered.isNotEmpty
        ? timestampExtractor(filtered.last).toString()
        : minCursor;

    // hasNext: true if we got a full batch (might be more data available)
    final hasNext = limit == null ? false : filtered.length >= limit;

    return DocumentsResult(
        documents: filtered, currentCursor: currentCursor, hasNext: hasNext);
  }

  bool _isType(StoredDocument doc, IriTerm typeIri) {
    final managedResourceType = doc.document.findSingleObject<IriTerm>(
        doc.documentIri, SyncManagedDocument.managedResourceType);
    return managedResourceType == typeIri;
  }

  @override
  Future<Map<String, String>> getSettings(Iterable<String> keys) async {
    return {
      for (final key in keys)
        if (_settings.containsKey(key)) key: _settings[key]!
    };
  }

  @override
  Future<void> setSetting(String key, String value) async {
    _settings[key] = value;
  }

  // Index-related methods - stubs for basic testing
  @override
  Future<IndexEntriesPage> getIndexEntries({
    required Iterable<IriTerm> indexIris,
    int? cursorTimestamp,
    int limit = 100,
  }) async {
    return IndexEntriesPage(entries: [], hasMore: false, lastCursor: null);
  }

  @override
  Stream<List<IndexEntryWithIri>> watchIndexEntries({
    required Iterable<IriTerm> indexIris,
    int? cursorTimestamp,
  }) {
    return Stream.value([]);
  }

  @override
  Future<void> saveGroupIndexSubscription({
    required int createdAt,
    required IriTerm groupIndexIri,
    required IriTerm groupIndexTemplateIri,
    required ItemFetchPolicy itemFetchPolicy,
  }) async {
    _groupIndexSubscriptions[groupIndexIri] = _GroupIndexSubscription(
      groupIndexIri: groupIndexIri,
      groupIndexTemplateIri: groupIndexTemplateIri,
      itemFetchPolicy: itemFetchPolicy,
      createdAt: createdAt,
    );
  }

  @override
  Stream<Set<IriTerm>> watchSubscribedGroupIndexIris(IriTerm templateIri) {
    // Return subscribed index IRIs for this template
    final subscribed = _groupIndexSubscriptions.values
        .where((sub) => sub.groupIndexTemplateIri == templateIri)
        .map((sub) => sub.groupIndexIri)
        .toSet();
    return Stream.value(subscribed);
  }

  @override
  Future<List<(IriTerm, ItemFetchPolicy)>>
      getAllSubscribedGroupIndices() async {
    return _groupIndexSubscriptions.values
        .map((sub) => (sub.groupIndexIri, sub.itemFetchPolicy))
        .toList();
  }

  @override
  Future<int> ensureIndexSetVersion({
    required Set<IriTerm> indexIris,
    required int createdAt,
  }) async {
    // Sort IRIs for consistent key generation
    final sortedIris = indexIris.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final key = sortedIris.map((iri) => iri.value).join(',');

    // Check if this set already has a version
    if (_indexSetVersionKeys.containsKey(key)) {
      return _indexSetVersionKeys[key]!;
    }

    // Create new version
    final versionId = _nextVersionId++;
    _indexSetVersions[versionId] = indexIris;
    _indexSetVersionKeys[key] = versionId;

    return versionId;
  }

  @override
  Future<Set<IriTerm>> getIndexIrisForVersion(int versionId) async {
    return _indexSetVersions[versionId] ?? {};
  }

  @override
  Future<void> saveIndexEntry({
    required IriTerm shardIri,
    required IriTerm indexIri,
    required IriTerm resourceIri,
    required String clockHash,
    String? headerProperties,
    bool isDeleted = false,
    required int updatedAt,
    required int ourPhysicalClock,
  }) async {
    final key = '${shardIri.value}|${resourceIri.value}';
    _print(
        'TestStorage.saveIndexEntry: shard=$shardIri, resource=$resourceIri, clock=$ourPhysicalClock');
    _indexEntries[key] = _IndexEntry(
      shardIri: shardIri,
      indexIri: indexIri,
      resourceIri: resourceIri,
      clockHash: clockHash,
      headerProperties: headerProperties,
      isDeleted: isDeleted,
      updatedAt: updatedAt,
      ourPhysicalClock: ourPhysicalClock,
    );
  }

  @override
  Future<List<IndexEntryWithIri>> getActiveIndexEntriesForShard(
      IriTerm shardIri) async {
    _print(
        'TestStorage.getActiveIndexEntriesForShard: looking for shard=$shardIri');
    _print('TestStorage: Total entries in storage: ${_indexEntries.length}');
    for (final entry in _indexEntries.values) {
      _print(
          '  - shard=${entry.shardIri}, resource=${entry.resourceIri}, deleted=${entry.isDeleted}');
    }
    final result = _indexEntries.values
        .where(
            (entry) => entry.shardIri == shardIri && entry.isDeleted == false)
        .map((entry) => IndexEntryWithIri(
              resourceIri: entry.resourceIri,
              clockHash: entry.clockHash,
              headerProperties: entry.headerProperties,
              updatedAt: entry.updatedAt,
              ourPhysicalClock: entry.ourPhysicalClock,
              isDeleted: entry.isDeleted,
            ))
        .toList();
    _print('TestStorage: Found ${result.length} active entries for this shard');
    return result;
  }

  @override
  Future<List<(IriTerm iri, int maxPhysicalClock)>> getShardsToUpdate(
      int sinceTimestamp) async {
    // Find max(ourPhysicalClock) per shard, then filter shards where max > sinceTimestamp
    final shardMaxClocks = <IriTerm, int>{};

    // Calculate max physical clock for each shard
    for (final entry in _indexEntries.values) {
      final currentMax = shardMaxClocks[entry.shardIri] ?? 0;
      if (entry.ourPhysicalClock > currentMax) {
        shardMaxClocks[entry.shardIri] = entry.ourPhysicalClock;
      }
    }

    // Filter shards where max > sinceTimestamp and return as list of tuples
    return shardMaxClocks.entries
        .where((e) => e.value > sinceTimestamp)
        .map((e) => (e.key, e.value))
        .toList();
  }

  // Sync timestamps now handled by SyncTimestampStorage extension using _settings

  // ========================================================================
  // Remote ETag Management (Multi-Remote Support)
  // ========================================================================

  @override
  Future<String?> getRemoteETag(RemoteId remoteId, IriTerm documentIri) async {
    return _settings[
        'remote.etag.${remoteId.backend}.${remoteId.id}.${documentIri.value}'];
  }

  @override
  Future<void> setRemoteETag(
      RemoteId remoteId, IriTerm documentIri, String etag) async {
    _settings[
            'remote.etag.${remoteId.backend}.${remoteId.id}.${documentIri.value}'] =
        etag;
  }

  @override
  Future<void> clearRemoteETag(RemoteId remoteId, IriTerm documentIri) async {
    _settings.remove(
        'remote.etag.${remoteId.backend}.${remoteId.id}.${documentIri.value}');
  }

  @override
  Future<int> getLastRemoteSyncTimestamp(RemoteId remoteId) async {
    final lastSyncTimestamp =
        _settings['sync.lastRemote.${remoteId.backend}.${remoteId.id}'];
    return lastSyncTimestamp != null ? int.parse(lastSyncTimestamp) : 0;
  }

  @override
  Future<void> updateLastRemoteSyncTimestamp(
      RemoteId remoteId, int timestamp) async {
    _settings['sync.lastRemote.${remoteId.backend}.${remoteId.id}'] =
        timestamp.toString();
  }
}

/// Internal class to store index entries in memory.
class _IndexEntry {
  final IriTerm shardIri;
  final IriTerm indexIri;
  final IriTerm resourceIri;
  final String clockHash;
  final String? headerProperties;
  final bool isDeleted;
  final int updatedAt;
  final int ourPhysicalClock;

  _IndexEntry({
    required this.shardIri,
    required this.indexIri,
    required this.resourceIri,
    required this.clockHash,
    this.headerProperties,
    required this.isDeleted,
    required this.updatedAt,
    required this.ourPhysicalClock,
  });
}

/// Internal class to store group index subscriptions in memory.
class _GroupIndexSubscription {
  final IriTerm groupIndexIri;
  final IriTerm groupIndexTemplateIri;
  final ItemFetchPolicy itemFetchPolicy;
  final int createdAt;

  _GroupIndexSubscription({
    required this.groupIndexIri,
    required this.groupIndexTemplateIri,
    required this.itemFetchPolicy,
    required this.createdAt,
  });
}
