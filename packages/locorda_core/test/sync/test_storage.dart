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

  @override
  Future<DocumentsResult> getDocumentsModifiedSince(
      IriTerm typeIri, String? cursor,
      {required int limit}) async {
    // Simple implementation - filter by updatedAt > cursor
    final cursorTimestamp = cursor != null ? int.parse(cursor) : 0;
    final filtered = _documents.values
        .where((doc) => _isType(doc, typeIri))
        .where((doc) => doc.metadata.updatedAt > cursorTimestamp)
        .toList()
      ..sort((a, b) => a.metadata.updatedAt.compareTo(b.metadata.updatedAt));

    final page = filtered.take(limit).toList();
    final nextCursor = page.length < filtered.length
        ? page.last.metadata.updatedAt.toString()
        : null;

    return DocumentsResult(documents: page, nextCursor: nextCursor);
  }

  bool _isType(StoredDocument doc, IriTerm typeIri) {
    final managedResourceType = doc.document.findSingleObject<IriTerm>(
        doc.documentIri, SyncManagedDocument.managedResourceType);
    return managedResourceType == typeIri;
  }

  @override
  Future<DocumentsResult> getDocumentsChangedByUsSince(
      IriTerm typeIri, String? cursor,
      {required int limit}) async {
    // Simple implementation - filter by ourPhysicalClock > cursor
    final cursorTimestamp = cursor != null ? int.parse(cursor) : 0;
    final filtered = _documents.values
        .where((doc) => _isType(doc, typeIri))
        .where((doc) => doc.metadata.ourPhysicalClock > cursorTimestamp)
        .toList()
      ..sort((a, b) =>
          a.metadata.ourPhysicalClock.compareTo(b.metadata.ourPhysicalClock));

    final page = filtered.take(limit).toList();
    final nextCursor = page.length < filtered.length
        ? page.last.metadata.ourPhysicalClock.toString()
        : null;

    return DocumentsResult(documents: page, nextCursor: nextCursor);
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
