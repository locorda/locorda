import 'package:locorda_core/locorda_core.dart';
import 'package:locorda_core/src/generated/_index.dart';
import 'package:locorda_core/src/rdf/rdf_extensions.dart';
import 'package:rdf_core/rdf_core.dart';

/// Simple in-memory storage for testing.
class TestStorage implements Storage {
  final Map<IriTerm, StoredDocument> _documents = {};
  final Map<IriTerm, IriTerm> _documentTypes = {}; // documentIri -> typeIri
  final Map<IriTerm, List<PropertyChange>> _propertyChanges = {};
  final Map<String, String> _settings = {};

  @override
  Future<void> initialize() async {
    // No-op for in-memory storage
  }

  @override
  Future<void> close() async {
    // No-op for in-memory storage
  }

  @override
  Future<StoredDocument?> getDocument(IriTerm documentIri) async {
    return _documents[documentIri];
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
}
