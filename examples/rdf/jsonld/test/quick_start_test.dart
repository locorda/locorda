import 'package:test/test.dart';
import '../lib/quick_start.dart' as example;

void main() {
  test('quick_start runs without errors', () {
    expect(() => example.main(), returnsNormally);
  });
}
