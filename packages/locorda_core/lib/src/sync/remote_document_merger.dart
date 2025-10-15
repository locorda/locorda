import 'package:locorda_core/src/storage/storage_interface.dart';
import 'package:logging/logging.dart';
import 'package:rdf_core/rdf_core.dart';

final _log = Logger('RemoteDocumentMerger');

/// Result of merging local and remote document states.
class MergeResult {
  /// The merged document (may be same as local if remote had no new changes).
  final RdfGraph mergedGraph;

  /// Whether the merged result differs from local state (needs upload).
  final bool hasLocalChanges;

  /// Whether the merged result differs from remote state (was updated from remote).
  final bool hasRemoteChanges;

  MergeResult({
    required this.mergedGraph,
    required this.hasLocalChanges,
    required this.hasRemoteChanges,
  });
}

/// Handles CRDT-based merging of local and remote document states.
///
/// This is a placeholder implementation. The actual CRDT merge logic
/// will be implemented later based on merge contracts.
class RemoteDocumentMerger {
  // Storage will be needed for property change history during actual merge
  // ignore: unused_field
  final Storage _storage;

  RemoteDocumentMerger({required Storage storage}) : _storage = storage;

  /// Merge local document with remote version using CRDT rules.
  ///
  /// Process:
  /// 1. Compare HLCs to determine if merge is needed
  /// 2. If remote is newer: Apply CRDT merge rules per property
  /// 3. If local is newer: Return local version with upload flag
  /// 4. If concurrent: Merge using property-specific CRDT algorithms
  ///
  /// Parameters:
  /// - [documentIri]: The document being synchronized
  /// - [localGraph]: Current local state (may be null if new from remote)
  /// - [remoteGraph]: Remote state (may be null if deleted remotely)
  ///
  /// Returns: Merge result indicating merged state and sync direction.
  Future<MergeResult> merge({
    required IriTerm documentIri,
    required RdfGraph? localGraph,
    required RdfGraph? remoteGraph,
  }) async {
    _log.fine('Merging document $documentIri');

    // TODO: Implement actual CRDT merge logic
    // For now, use simple last-write-wins based on physical clock

    if (remoteGraph == null) {
      // Remote was deleted or never existed
      _log.fine('Remote is null - keeping local');
      return MergeResult(
        mergedGraph: localGraph!,
        hasLocalChanges: true, // Need to upload
        hasRemoteChanges: false,
      );
    }

    if (localGraph == null) {
      // New document from remote
      _log.fine('Local is null - accepting remote');
      return MergeResult(
        mergedGraph: remoteGraph,
        hasLocalChanges: false,
        hasRemoteChanges: true, // Need to save locally
      );
    }

    // Both exist - placeholder: just return local for now
    // TODO: Compare HLCs and apply CRDT merge rules
    _log.warning(
        'PLACEHOLDER: Returning local version without actual CRDT merge');
    return MergeResult(
      mergedGraph: localGraph,
      hasLocalChanges: false,
      hasRemoteChanges: false,
    );
  }
}
