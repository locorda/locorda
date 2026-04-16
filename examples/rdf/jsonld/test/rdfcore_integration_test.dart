import 'package:test/test.dart';
import '../lib/rdfcore_integration.dart' as example;

void main() {
  test('rdfcore_integration runs without errors', () {
    expect(() => example.main(), returnsNormally);
  });
}
