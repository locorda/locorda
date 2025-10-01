/// Test implementation of PhysicalTimestampFactory with controlled, deterministic timestamps.
///
/// Auto-increments milliseconds from a base timestamp for predictable test results.
class TestPhysicalTimestampFactory {
  int _counter = 0;
  final DateTime baseTimestamp;

  TestPhysicalTimestampFactory({required this.baseTimestamp});

  DateTime call() {
    return baseTimestamp.add(Duration(milliseconds: _counter++));
  }
}
