/// Test implementation of PhysicalTimestampFactory with controlled, deterministic timestamps.
///
/// Provides auto-incrementing timestamps starting from a base timestamp.
/// Each call to call() returns baseTimestamp + counter milliseconds, where counter
/// increments with each call.
///
/// The base timestamp can be updated at any time via setTimestamp(), allowing tests
/// to control the timeline for different phases (e.g., preparation vs. actual test execution).
class TestPhysicalTimestampFactory {
  int _counter = 0;
  DateTime get baseTimestamp => _explicitTimestamp;
  DateTime _explicitTimestamp;

  TestPhysicalTimestampFactory({required DateTime baseTimestamp})
      : _explicitTimestamp = baseTimestamp;

  /// Set a new base timestamp and reset the counter to 0.
  /// Subsequent calls to call() will start incrementing from this new base at 0ms.
  void setTimestamp(DateTime timestamp) {
    _explicitTimestamp = timestamp;
    _counter = 0;
  }

  DateTime call() {
    return baseTimestamp.add(Duration(milliseconds: _counter++));
  }
}
