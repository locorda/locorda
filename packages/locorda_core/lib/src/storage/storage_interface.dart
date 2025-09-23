/// Abstract storage interface for CRDT sync operations.
///
/// This interface defines the contract for local storage backends
/// that support CRDT synchronization with offline-first capabilities.
library;

import 'package:rdf_core/rdf_core.dart';

abstract interface class Storage {
  /// Save a document with content, metadata, and property changes atomically.
  ///
  /// Storage handles RDF serialization and persists all data in a single transaction.
  Future<void> saveDocument(
    IriTerm documentIri,
    RdfGraph document,
    DocumentMetadata metadata,
    List<PropertyChange> changes
  );

  /// Get document with content and metadata by IRI.
  Future<StoredDocument?> getDocument(IriTerm documentIri);

  /// Get property changes for a document, optionally filtered by logical clock.
  ///
  /// [sinceLogicalClock] - Only return changes with changeLogicalClock > this value.
  /// Used during merge operations to get changes since a specific HLC state.
  Future<List<PropertyChange>> getPropertyChanges(
    IriTerm documentIri,
    {int? sinceLogicalClock}
  );

  /// Get documents modified since timestamp (local OR remote changes), ordered by updatedAt ascending.
  ///
  /// Used for hydration - loading changes in chronological order with pagination.
  /// Returns documents modified by any source (local changes, remote merges).
  Future<List<StoredDocument>> getDocumentsModifiedSince(
    int timestamp,
    {required int limit}
  );

  /// Get documents changed by us since timestamp (local changes only), ordered by ourPhysicalClock ascending.
  ///
  /// Used for sync to remote - uploading our changes with pagination.
  /// Returns only documents with ourPhysicalClock > timestamp.
  Future<List<StoredDocument>> getDocumentsChangedByUsSince(
    int timestamp,
    {required int limit}
  );

  /// Initialize the storage backend.
  Future<void> initialize();

  /// Close the storage backend and free resources.
  Future<void> close();
}

/// Document with content and metadata retrieved from storage.
class StoredDocument {
  final IriTerm documentIri;
  final RdfGraph document;
  final DocumentMetadata metadata;

  StoredDocument({
    required this.documentIri,
    required this.document,
    required this.metadata
  });
}

/// Document metadata managed by sync layer and storage.
class DocumentMetadata {
  final int ourPhysicalClock;   // When we last changed this document (from sync layer)
  final int updatedAt;          // When document was last updated - local or remote (set by storage)

  DocumentMetadata({
    required this.ourPhysicalClock,
    required this.updatedAt
  });
}

/// Property-level change information for fine-grained conflict resolution.
class PropertyChange {
  final IriTerm resourceIri;    // Resource within the document (e.g., doc#it, doc#nutrition)
  final IriTerm propertyIri;    // Property that changed (e.g., schema:name)
  final int changedAtMs;        // Real timestamp when change was made
  final int changeLogicalClock; // Logical clock assigned to this change

  PropertyChange({
    required this.resourceIri,
    required this.propertyIri,
    required this.changedAtMs,
    required this.changeLogicalClock,
  });
}
