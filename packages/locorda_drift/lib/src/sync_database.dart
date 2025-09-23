/// Drift database schema for Locorda sync storage.
library;

import 'dart:math' as math;
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:locorda_core/locorda_core.dart';

part 'sync_database.g.dart';

/// IRI lookup table for normalized storage
class SyncIris extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get iri => text().unique()();
}

/// Document storage table
class SyncDocuments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get documentIriId => integer().references(SyncIris, #id).unique()();
  TextColumn get documentContent => text()();
  IntColumn get ourPhysicalClock => integer()();
  IntColumn get updatedAt => integer()();
}

/// Property-level change tracking table
class SyncPropertyChanges extends Table {
  IntColumn get documentId => integer().references(SyncDocuments, #id)();

  @ReferenceName('resourceIri')
  IntColumn get resourceIriId => integer().references(SyncIris, #id)();

  @ReferenceName('propertyIri')
  IntColumn get propertyIriId => integer().references(SyncIris, #id)();

  IntColumn get changedAtMs => integer()();
  IntColumn get changeLogicalClock => integer()();

  @override
  Set<Column> get primaryKey =>
      {documentId, resourceIriId, propertyIriId, changeLogicalClock};
}

/// Mixin for efficient IRI batch loading and creation
mixin IriBatchLoader on DatabaseAccessor<SyncDatabase> {
  /// Efficiently load multiple IRIs by their IDs with automatic batching
  Future<Map<int, String>> getIrisBatch(Set<int> iriIds) async {
    if (iriIds.isEmpty) return {};

    const batchSize = 999; // SQLite's default SQLITE_MAX_VARIABLE_NUMBER - 1
    final result = <int, String>{};

    // Process in batches
    final iriIdsList = iriIds.toList();
    for (int i = 0; i < iriIdsList.length; i += batchSize) {
      final batch =
          iriIdsList.sublist(i, math.min(i + batchSize, iriIdsList.length));

      final iris =
          await (select(db.syncIris)..where((iri) => iri.id.isIn(batch))).get();
      result.addAll({for (final iri in iris) iri.id: iri.iri});
    }

    return result;
  }

  /// Efficiently get/create multiple IRI IDs in batch
  Future<Map<String, int>> getOrCreateIriIdsBatch(Set<String> iris) async {
    if (iris.isEmpty) return {};

    // 1. First try to get all existing IRIs
    final existing = await _getExistingIriIds(iris);
    final result = Map<String, int>.from(existing);

    // 2. Find IRIs that don't exist yet
    final missing = iris.where((iri) => !existing.containsKey(iri)).toSet();

    // 3. Batch create missing IRIs
    if (missing.isNotEmpty) {
      final created = await _createMissingIris(missing);
      result.addAll(created);
    }

    return result;
  }

  /// Get existing IRI → ID mappings for the given IRIs
  Future<Map<String, int>> _getExistingIriIds(Set<String> iris) async {
    if (iris.isEmpty) return {};

    const batchSize = 999;
    final result = <String, int>{};

    // Process in batches
    final irisList = iris.toList();
    for (int i = 0; i < irisList.length; i += batchSize) {
      final batch =
          irisList.sublist(i, math.min(i + batchSize, irisList.length));

      final existingIris = await (select(db.syncIris)
            ..where((iri) => iri.iri.isIn(batch)))
          .get();
      result.addAll({for (final iri in existingIris) iri.iri: iri.id});
    }

    return result;
  }

  /// Create missing IRIs and return their IDs
  Future<Map<String, int>> _createMissingIris(Set<String> iris) async {
    if (iris.isEmpty) return {};

    final result = <String, int>{};

    // Create IRIs one by one to get their auto-generated IDs
    // Note: Drift doesn't support batch insert with returning IDs easily
    for (final iri in iris) {
      final id =
          await into(db.syncIris).insert(SyncIrisCompanion(iri: Value(iri)));
      result[iri] = id;
    }

    return result;
  }
}

/// Data Access Object for document storage
@DriftAccessor(tables: [SyncDocuments, SyncIris])
class SyncDocumentDao extends DatabaseAccessor<SyncDatabase>
    with _$SyncDocumentDaoMixin, IriBatchLoader {
  SyncDocumentDao(super.db);

  /// Save a document with content and timestamps, returning the document ID
  Future<int> saveDocument({
    required String documentIri,
    required String content,
    required int ourPhysicalClock,
    required int updatedAt,
  }) async {
    // Use the mixin for consistency
    final iriToIdMap = await getOrCreateIriIdsBatch({documentIri});
    final documentIriId = iriToIdMap[documentIri]!;

    // Try to get existing document first
    final existingDocument = await (select(syncDocuments)
          ..where((d) => d.documentIriId.equals(documentIriId)))
        .getSingleOrNull();

    if (existingDocument != null) {
      // Update existing document
      await (update(syncDocuments)
            ..where((d) => d.id.equals(existingDocument.id)))
          .write(SyncDocumentsCompanion(
        documentContent: Value(content),
        ourPhysicalClock: Value(ourPhysicalClock),
        updatedAt: Value(updatedAt),
      ));
      return existingDocument.id;
    } else {
      // Insert new document
      return await into(syncDocuments).insert(
        SyncDocumentsCompanion(
          documentIriId: Value(documentIriId),
          documentContent: Value(content),
          ourPhysicalClock: Value(ourPhysicalClock),
          updatedAt: Value(updatedAt),
        ),
      );
    }
  }

  /// Get document content by IRI
  Future<String?> getDocumentContent(String documentIri) async {
    // For read operations, we should only get existing IRIs, not create them
    final existingIriIds = await _getExistingIriIds({documentIri});
    final documentIriId = existingIriIds[documentIri];
    if (documentIriId == null) return null;

    final document = await (select(syncDocuments)
          ..where((d) => d.documentIriId.equals(documentIriId)))
        .getSingleOrNull();

    return document?.documentContent;
  }

  /// Get document with metadata by IRI
  Future<SyncDocument?> getDocument(String documentIri) async {
    // For read operations, we should only get existing IRIs, not create them
    final existingIriIds = await _getExistingIriIds({documentIri});
    final documentIriId = existingIriIds[documentIri];
    if (documentIriId == null) return null;

    return await (select(syncDocuments)
          ..where((d) => d.documentIriId.equals(documentIriId)))
        .getSingleOrNull();
  }

  /// Get document ID by IRI (for property changes)
  Future<int?> getDocumentId(String documentIri) async {
    // For read operations, we should only get existing IRIs, not create them
    final existingIriIds = await _getExistingIriIds({documentIri});
    final documentIriId = existingIriIds[documentIri];
    if (documentIriId == null) return null;

    final document = await (select(syncDocuments)
          ..where((d) => d.documentIriId.equals(documentIriId)))
        .getSingleOrNull();

    return document?.id;
  }

  /// Get documents modified since timestamp (local OR remote changes), ordered by updatedAt ascending
  Future<List<DocumentWithIri>> getDocumentsModifiedSince(int timestamp,
      {required int limit}) async {
    final documents = await (select(syncDocuments)
          ..where((d) => d.updatedAt.isBiggerThanValue(timestamp))
          ..orderBy([(d) => OrderingTerm(expression: d.updatedAt)])
          ..limit(limit))
        .get();

    return _convertDocumentsWithIris(documents);
  }

  /// Get documents changed by us since timestamp (local changes only), ordered by ourPhysicalClock ascending
  Future<List<DocumentWithIri>> getDocumentsChangedByUsSince(int timestamp,
      {required int limit}) async {
    final documents = await (select(syncDocuments)
          ..where((d) => d.ourPhysicalClock.isBiggerThanValue(timestamp))
          ..orderBy([(d) => OrderingTerm(expression: d.ourPhysicalClock)])
          ..limit(limit))
        .get();

    return _convertDocumentsWithIris(documents);
  }

  /// Convert documents with IRI resolution using batching
  Future<List<DocumentWithIri>> _convertDocumentsWithIris(
      List<SyncDocument> documents) async {
    if (documents.isEmpty) return [];

    // Batch load all document IRIs
    final iriIds = documents.map((d) => d.documentIriId).toSet();
    final iriMap = await getIrisBatch(iriIds);

    return documents
        .map((doc) => DocumentWithIri(
              iri: iriMap[doc.documentIriId]!,
              document: doc,
            ))
        .toList();
  }
}

/// Data Access Object for property change tracking
@DriftAccessor(tables: [SyncPropertyChanges, SyncIris])
class SyncPropertyChangeDao extends DatabaseAccessor<SyncDatabase>
    with _$SyncPropertyChangeDaoMixin, IriBatchLoader {
  SyncPropertyChangeDao(super.db);

  /// Record multiple property changes efficiently in batch
  Future<void> recordPropertyChangesBatch({
    required int documentId,
    required List<PropertyChange> changes,
  }) async {
    if (changes.isEmpty) return;

    // Collect all unique IRIs that need IDs
    final allIris = changes
        .expand((change) => [
              change.resourceIri.value,
              change.propertyIri.value,
            ])
        .toSet();

    // Batch get/create all IRI IDs using the mixin
    final iriToIdMap = await getOrCreateIriIdsBatch(allIris);

    // Batch insert all property changes
    final companions = changes
        .map((change) => SyncPropertyChangesCompanion(
              documentId: Value(documentId),
              resourceIriId: Value(iriToIdMap[change.resourceIri.value]!),
              propertyIriId: Value(iriToIdMap[change.propertyIri.value]!),
              changedAtMs: Value(change.changedAtMs),
              changeLogicalClock: Value(change.changeLogicalClock),
            ))
        .toList();

    await batch((batch) {
      batch.insertAll(syncPropertyChanges, companions);
    });
  }

  /// Get property changes for a document, optionally filtered by logical clock
  Future<List<PropertyChangeInfo>> getPropertyChanges(int documentId,
      {int? sinceLogicalClock}) async {
    // 1. Get all property changes
    var query = select(syncPropertyChanges)
      ..where((c) => c.documentId.equals(documentId));
    if (sinceLogicalClock != null) {
      query = query
        ..where(
            (c) => c.changeLogicalClock.isBiggerThanValue(sinceLogicalClock));
    }
    final changes = await query.get();

    // 2. Collect all unique IRI IDs that need resolution
    final iriIds = <int>{};
    for (final change in changes) {
      iriIds.add(change.resourceIriId);
      iriIds.add(change.propertyIriId);
    }

    // 3. Batch load all IRIs in one query
    final iriMap = await getIrisBatch(iriIds);

    // 4. Build results using the cached IRI map
    return changes
        .map((change) => PropertyChangeInfo(
              resourceIri: iriMap[change.resourceIriId]!,
              propertyIri: iriMap[change.propertyIriId]!,
              changedAtMs: change.changedAtMs,
              changeLogicalClock: change.changeLogicalClock,
            ))
        .toList();
  }
}

/// Property change information
class PropertyChangeInfo {
  final String resourceIri;
  final String propertyIri;
  final int changedAtMs;
  final int changeLogicalClock;

  PropertyChangeInfo({
    required this.resourceIri,
    required this.propertyIri,
    required this.changedAtMs,
    required this.changeLogicalClock,
  });
}

/// Document with IRI for batch operations
class DocumentWithIri {
  final String iri;
  final SyncDocument document;

  DocumentWithIri({
    required this.iri,
    required this.document,
  });
}

/// Main sync database class
@DriftDatabase(
  tables: [SyncIris, SyncDocuments, SyncPropertyChanges],
  daos: [SyncDocumentDao, SyncPropertyChangeDao],
)
class SyncDatabase extends _$SyncDatabase {
  SyncDatabase({DriftWebOptions? web, DriftNativeOptions? native})
      : super(_openConnection(web: web, native: native));

  /// Internal constructor for test subclasses
  SyncDatabase.forExecutor(QueryExecutor executor) : super(executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();

          // Create indices for performance
          await m.database.customStatement('''
        CREATE INDEX IF NOT EXISTS idx_sync_documents_iri
        ON sync_documents(document_iri_id);
      ''');

          await m.database.customStatement('''
        CREATE INDEX IF NOT EXISTS idx_sync_documents_updated
        ON sync_documents(updated_at DESC);
      ''');

          await m.database.customStatement('''
        CREATE INDEX IF NOT EXISTS idx_sync_iris_iri
        ON sync_iris(iri);
      ''');

          await m.database.customStatement('''
        CREATE INDEX IF NOT EXISTS idx_property_changes_document
        ON sync_property_changes(document_id);
      ''');
        },
      );
}

/// Create database connection based on platform
QueryExecutor _openConnection(
    {DriftWebOptions? web, DriftNativeOptions? native}) {
  return driftDatabase(name: 'locorda_sync', web: web, native: native);
}
