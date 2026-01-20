import 'package:test/test.dart';
import 'package:rdf_canonicalization_examples/quick_start_graph.dart'
    as example;

void main() {
  test('quick_start_graph runs without errors', () {
    expect(() => example.main(), returnsNormally);
  });
}
