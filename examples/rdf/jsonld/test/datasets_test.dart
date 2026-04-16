import 'package:test/test.dart';
import '../lib/datasets.dart' as example;

void main() {
  test('datasets runs without errors', () {
    expect(() => example.main(), returnsNormally);
  });
}
