/// Exception thrown when an optimistic concurrency check fails during storage
/// operations. Used by storage backends to signal a concurrent update.
class ConcurrentUpdateException implements Exception {
  final String? message;

  ConcurrentUpdateException([this.message]);

  @override
  String toString() => 'ConcurrentUpdateException: ${message ?? ''}';
}
