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
  Future<void> saveDocument(IriTerm documentIri, RdfGraph document,
      DocumentMetadata metadata, List<PropertyChange> changes) async {
    await _database.transaction(() async {
      // Serialize RDF graph to Turtle
      final content = _codec.encode(document, baseUri: documentIri.value);

      // Save document with metadata and get the document ID
      final documentId = await documentDao.saveDocument(
        documentIri: documentIri.value,
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
            ))
        .toList();
  }

  @override
  Future<List<StoredDocument>> getDocumentsModifiedSince(int timestamp,
      {required int limit}) async {
    final documents =
        await documentDao.getDocumentsModifiedSince(timestamp, limit: limit);
    return _convertToStoredDocuments(documents);
  }

  @override
  Future<List<StoredDocument>> getDocumentsChangedByUsSince(int timestamp,
      {required int limit}) async {
    final documents =
        await documentDao.getDocumentsChangedByUsSince(timestamp, limit: limit);
    return _convertToStoredDocuments(documents);
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
