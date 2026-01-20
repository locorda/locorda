import 'package:test/test.dart';
import 'package:rdf_xml_examples/rdfcore_integration.dart'
    as rdfcore_integration;

void main() {
  test('rdfcore_integration example runs without errors', () {
    expect(() => rdfcore_integration.main(), returnsNormally);
  });
}
