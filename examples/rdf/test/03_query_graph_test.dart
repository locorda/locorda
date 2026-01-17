import 'package:test/test.dart';
import '../03_query_graph.dart' as example;

void main() {
  test('03_query_graph runs without errors', () {
    expect(() => example.main(), returnsNormally);
  });
}
