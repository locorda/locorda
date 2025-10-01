/// Test implementation of PhysicalTimestampFactory with controlled, deterministic timestamps.
///
/// Supports two modes:
/// 1. Auto-increment mode: Auto-increments milliseconds from a base timestamp (legacy)
/// 2. Explicit mode: Returns explicitly set timestamps via setTimestamp()
class TestPhysicalTimestampFactory {
  int _counter = 0;
  final DateTime baseTimestamp;
  DateTime? _explicitTimestamp;

  TestPhysicalTimestampFactory({required this.baseTimestamp});

  /// Set an explicit timestamp for the next call().
  /// This overrides the auto-increment behavior for one call.
  void setTimestamp(DateTime timestamp) {
    _explicitTimestamp = timestamp;
  }

  DateTime call() {
    if (_explicitTimestamp != null) {
      final result = _explicitTimestamp!;
      _explicitTimestamp = null;
      return result;
    }
    return baseTimestamp.add(Duration(milliseconds: _counter++));
  }
}
