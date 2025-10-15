import 'package:locorda_core/locorda_core.dart';
import 'package:locorda_core/src/storage/remote_storage.dart';
import 'package:rdf_core/rdf_core.dart';

class InMemoryBackend implements Backend {
  String get name => 'test';
  final List<RemoteStorage> _remotes;

  InMemoryBackend()
      : _remotes = [InMemoryRemoteStorage(RemoteId('test', 'in-memory'))];

  @override
  List<RemoteStorage> get remotes => _remotes;
}

/// In-memory implementation of RemoteStorage for testing.
///
/// Provides full ETag support with correct HTTP conditional request semantics:
/// - If-None-Match: * (create only)
/// - If-Match: <etag> (update only if unchanged)
/// - If-None-Match: <etag> (download only if changed)
class InMemoryRemoteStorage implements RemoteStorage {
  @override
  final RemoteId remoteId;

  /// Storage: documentIri -> (graph, etag)
  final Map<String, _StoredDocument> _documents = {};

  /// Counter for generating unique ETags
  int _etagCounter = 0;

  InMemoryRemoteStorage(this.remoteId);

  @override
  Future<RemoteDownloadResult> download(IriTerm documentIri,
      {String? ifNoneMatch}) async {
    final iri = documentIri.value;
    final stored = _documents[iri];

    // Document doesn't exist
    if (stored == null) {
      return RemoteDownloadResult(
        graph: null,
        etag: null,
        notModified: false,
      );
    }

    // If-None-Match: check if document changed
    if (ifNoneMatch != null && ifNoneMatch == stored.etag) {
      // 304 Not Modified
      return RemoteDownloadResult.notModified(etag: stored.etag);
    }

    // 200 OK - return document
    return RemoteDownloadResult(
      graph: stored.graph,
      etag: stored.etag,
      notModified: false,
    );
  }

  @override
  Future<RemoteUploadResult> upload(IriTerm documentIri, RdfGraph graph,
      {String? ifMatch}) async {
    final iri = documentIri.value;
    final stored = _documents[iri];

    // ifMatch: null → If-None-Match: * (create only)
    if (ifMatch == null) {
      if (stored != null) {
        // 409 Conflict - document already exists
        return RemoteUploadResult.conflict();
      }

      // Create new document with new ETag
      final newEtag = _generateETag();
      _documents[iri] = _StoredDocument(graph: graph, etag: newEtag);

      return RemoteUploadResult(etag: newEtag);
    }

    // ifMatch: <etag> → If-Match: <etag> (update only if unchanged)
    if (stored == null) {
      // 412 Precondition Failed - document doesn't exist
      return RemoteUploadResult.conflict();
    }

    if (stored.etag != ifMatch) {
      // 412 Precondition Failed - ETag mismatch
      return RemoteUploadResult.conflict();
    }

    // Update document with new ETag
    final newEtag = _generateETag();
    _documents[iri] = _StoredDocument(graph: graph, etag: newEtag);

    return RemoteUploadResult(etag: newEtag);
  }

  @override
  Future<void> delete(IriTerm documentIri, {String? ifMatch}) async {
    final iri = documentIri.value;
    final stored = _documents[iri];

    // If document doesn't exist, delete is idempotent (no-op)
    if (stored == null) {
      return;
    }

    // If-Match provided: check ETag
    if (ifMatch != null && stored.etag != ifMatch) {
      throw Exception('412 Precondition Failed - ETag mismatch on delete');
    }

    // Delete document
    _documents.remove(iri);
  }

  @override
  Future<bool> isAvailable() async {
    // In-memory storage is always available
    return true;
  }

  /// Generate a new unique ETag
  String _generateETag() {
    return '"etag-${++_etagCounter}"';
  }

  /// Clear all stored documents (for testing)
  void clear() {
    _documents.clear();
    _etagCounter = 0;
  }

  /// Check if document exists (for testing)
  bool hasDocument(IriTerm documentIri) {
    return _documents.containsKey(documentIri.value);
  }

  /// Get stored ETag for document (for testing)
  String? getETag(IriTerm documentIri) {
    return _documents[documentIri.value]?.etag;
  }
}

/// Internal storage structure for documents
class _StoredDocument {
  final RdfGraph graph;
  final String etag;

  _StoredDocument({
    required this.graph,
    required this.etag,
  });
}
