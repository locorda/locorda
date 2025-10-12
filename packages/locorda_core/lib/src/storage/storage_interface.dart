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
  /// Returns cursor information including the previous cursor for gap detection.
  Future<SaveDocumentResult> saveDocument(
      IriTerm documentIri,
      IriTerm typeIri,
      RdfGraph document,
      DocumentMetadata metadata,
      List<PropertyChange> changes);

  /// Get document with content and metadata by IRI.
  Future<StoredDocument?> getDocument(IriTerm documentIri);

  /// Get property changes for a document, optionally filtered by logical clock.
  ///
  /// [sinceLogicalClock] - Only return changes with changeLogicalClock > this value.
  /// Used during merge operations to get changes since a specific HLC state.
  Future<List<PropertyChange>> getPropertyChanges(IriTerm documentIri,
      {int? sinceLogicalClock});

  /// Get documents of a specific type modified since cursor (local OR remote changes).
  ///
  /// Returns a Future with a batch of documents for pagination during initial loading.
  /// Used for batch loading existing documents before switching to reactive watch.
  ///
  /// Parameters:
  /// - [typeIri]: The type of documents to query
  /// - [minCursor]: Only return documents with updatedAt > minCursor (null = from beginning)
  /// - [limit]: Maximum number of documents to return (for pagination)
  ///
  /// Returns documents with updatedAt > minCursor, ordered by updatedAt ascending.
  /// If result.nextCursor is not null, more data is available and should be fetched.
  Future<DocumentsResult> getDocumentsModifiedSince(
      IriTerm typeIri, String? minCursor,
      {required int limit});

  /// Get documents of a specific type changed by us since cursor (local changes only).
  ///
  /// Returns a Future with a batch of documents for pagination during initial sync.
  /// Used for batch loading local changes before switching to reactive watch.
  ///
  /// Parameters:
  /// - [typeIri]: The type of documents to query
  /// - [minCursor]: Only return documents with ourPhysicalClock > minCursor (null = from beginning)
  /// - [limit]: Maximum number of documents to return (for pagination)
  ///
  /// Returns documents we changed with ourPhysicalClock > minCursor,
  /// ordered by ourPhysicalClock ascending.
  Future<DocumentsResult> getDocumentsChangedByUsSince(
      IriTerm typeIri, String? minCursor,
      {required int limit});

  /// Watch documents of a specific type modified since cursor (local OR remote changes).
  ///
  /// Emits DocumentsResult whenever documents of the given type change in the database.
  /// Used for reactive hydration - automatically receiving updates when data changes.
  ///
  /// The stream emits:
  /// - Initial data immediately upon subscription
  /// - New DocumentsResult whenever relevant data changes in the database
  ///
  /// Parameters:
  /// - [typeIri]: The type of documents to watch
  /// - [minCursor]: Only emit documents with updatedAt > minCursor (null = from beginning)
  ///
  /// Returns a stream that emits all documents of the type with updatedAt > minCursor,
  /// ordered by updatedAt ascending. The stream automatically updates when documents change.
  Stream<DocumentsResult> watchDocumentsModifiedSince(
      IriTerm typeIri, String? minCursor);

  /// Watch documents of a specific type changed by us since cursor (local changes only).
  ///
  /// Emits DocumentsResult whenever documents that we changed are modified in the database.
  /// Used for reactive sync to remote - automatically detecting local changes to upload.
  ///
  /// The stream emits:
  /// - Initial data immediately upon subscription
  /// - New DocumentsResult whenever relevant local changes occur
  ///
  /// Parameters:
  /// - [typeIri]: The type of documents to watch
  /// - [minCursor]: Only emit documents with ourPhysicalClock > minCursor (null = from beginning)
  ///
  /// Returns a stream that emits all documents we changed with ourPhysicalClock > minCursor,
  /// ordered by ourPhysicalClock ascending.
  Stream<DocumentsResult> watchDocumentsChangedByUsSince(
      IriTerm typeIri, String? minCursor);

  /// Initialize the storage backend.
  Future<void> initialize();

  /// Close the storage backend and free resources.
  Future<void> close();

  /// Get multiple settings by keys in a single database request.
  ///
  /// Returns a map of key-value pairs. Missing keys are omitted from the result.
  /// Used during startup to efficiently load multiple settings together.
  Future<Map<String, String>> getSettings(Iterable<String> keys);

  /// Set a single setting value.
  ///
  /// Creates or updates the setting. Used to persist configuration values
  /// like installation IRI and flags.
  Future<void> setSetting(String key, String value);
}

/// Document with content and metadata retrieved from storage.
class StoredDocument {
  final IriTerm documentIri;
  final RdfGraph document;
  final DocumentMetadata metadata;

  StoredDocument(
      {required this.documentIri,
      required this.document,
      required this.metadata});
}

/// Result of saving a document, including cursor information for gap detection.
class SaveDocumentResult {
  final String?
      previousCursor; // The highest cursor for this type before this save (null if first)
  final String currentCursor; // The cursor for this save operation

  SaveDocumentResult({
    required this.previousCursor,
    required this.currentCursor,
  });
}

/// Result of querying documents with pagination support.
class DocumentsResult {
  final List<StoredDocument> documents;

  /// The cursor representing the current position in the document stream.
  /// This represents how far we've processed and should be used to resume
  /// hydration after app restart.
  ///
  /// - If documents were returned: cursor of the last document
  /// - If no documents were returned: the minCursor that was passed in (never goes backwards)
  /// - Never null after initialization (represents "beginning" as empty string if needed)
  final String? currentCursor;

  /// Whether there are more documents available for pagination.
  /// True means another batch should be fetched with the currentCursor.
  /// False means all documents have been loaded.
  final bool hasNext;

  DocumentsResult({
    required this.documents,
    required this.currentCursor,
    required this.hasNext,
  });
}

/// Document metadata managed by sync layer and storage.
class DocumentMetadata {
  final int
      ourPhysicalClock; // When we last changed this document (from sync layer)
  final int
      updatedAt; // When document was last updated - local or remote (set by storage)

  DocumentMetadata({required this.ourPhysicalClock, required this.updatedAt});
}

/// Property-level change information for fine-grained conflict resolution.
class PropertyChange {
  final IriTerm
      resourceIri; // Resource within the document (e.g., doc#it, doc#nutrition)
  final RdfPredicate propertyIri; // Property that changed (e.g., schema:name)
  final int changedAtMs; // Real timestamp when change was made
  final int changeLogicalClock; // Logical clock assigned to this change
  final bool
      isFrameworkProperty; // Whether this is a framework metadata property (sync:logicalTime, sync:resourceHash, etc.) or app data property

  PropertyChange({
    required this.resourceIri,
    required this.propertyIri,
    required this.changedAtMs,
    required this.changeLogicalClock,
    this.isFrameworkProperty = false,
  });
}
