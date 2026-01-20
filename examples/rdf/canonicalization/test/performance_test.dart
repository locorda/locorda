import 'package:test/test.dart';
import 'package:rdf_canonicalization_examples/performance.dart' as example;

void main() {
  test('performance runs without errors', () {
    expect(() => example.main(), returnsNormally);
  });
}
