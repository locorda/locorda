/// Type-safe identifier for remote sync endpoints.
///
/// Wraps a remote Identifier (for example a Solid Pod base URL) to provide type safety
/// and validation for multi-remote synchronization scenarios.
///
/// Example:
/// ```dart
/// final podId = RemoteId('solid', 'https://alice.pod.example/');
/// await storage.getRemoteETag(documentIri, podId);
/// ```
library;

/// Type-safe identifier for a remote instance.
///
/// Might represent a Solid Pod base URL or other remote storage location.
class RemoteId {
  final String backend;
  final String id;

  /// Creates a RemoteId from a string.
  ///
  /// Throws [ArgumentError] if the String is empty or invalid.
  RemoteId(String backend, String value)
      : backend = backend,
        id = value {
    if (backend.isEmpty) {
      throw ArgumentError('Backend identifier cannot be empty');
    }
    if (value.isEmpty) {
      throw ArgumentError('Remote identifier cannot be empty');
    }
    // Additional validation can be added here if needed
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RemoteId &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          backend == other.backend;

  @override
  int get hashCode => id.hashCode ^ backend.hashCode;

  @override
  String toString() => 'RemoteId($backend, $id)';
}
