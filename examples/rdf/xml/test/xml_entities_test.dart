import 'package:test/test.dart';
import 'package:rdf_xml_examples/xml_entities.dart' as xml_entities;

void main() {
  test('xml_entities example runs without errors', () {
    expect(() => xml_entities.main(), returnsNormally);
  });
}
