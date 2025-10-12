/// Drift-based implementation of Storage interface.
library;

import 'package:drift_flutter/drift_flutter.dart';
import 'package:locorda_core/locorda_core.dart';
import 'package:rdf_core/rdf_core.dart';

import 'sync_database.dart';

/// Drift-based implementation of the Storage interface.
///
/// Provides cross-platform SQLite storage for RDF documents, CRDT metadata,
/// and property-level change tracking using the Drift ORM.
class DriftStorage implements Storage {
  final SyncDocumentDao documentDao;
  final SyncPropertyChangeDao propertyChangeDao;
  final SyncDatabase _database;
  final RdfGraphCodec _codec;
  final IriTermFactory _iriTermFactory;

  bool _initialized = false;

  DriftStorage._({
    required this.documentDao,
    required this.propertyChangeDao,
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
        database: database,
        iriTermFactory: iriTermFactory);
  }

  /// Create DriftStorage with custom database instance (for testing)
  factory DriftStorage.withDatabase(SyncDatabase database,
      {IriTermFactory iriTermFactory = IriTerm.validated}) {
    return DriftStorage._(
      documentDao: database.syncDocumentDao,
      propertyChangeDao: database.syncPropertyChangeDao,
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
  Future<StoredDocument?> getDocument(IriTerm documentIri) async {
    final document = await documentDao.getDocument(documentIri.value);
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
      IriTerm typeIri, String? minCursor) async* {
    await for (final documents
        in documentDao.watchDocumentsModifiedSince(typeIri.value, minCursor)) {
      final storedDocuments = _convertToStoredDocuments(documents);

      // For watch streams: currentCursor is the latest data, or minCursor if no docs
      // hasNext is always false for streams (they don't paginate)
      final cursor = storedDocuments.isNotEmpty
          ? storedDocuments.last.metadata.updatedAt.toString()
          : minCursor;

      yield DocumentsResult(
        documents: storedDocuments,
        currentCursor: cursor,
        hasNext: false,
      );
    }
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
}
