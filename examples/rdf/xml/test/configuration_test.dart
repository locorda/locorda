import 'package:test/test.dart';
import 'package:rdf_xml_examples/configuration.dart' as configuration;

void main() {
  test('configuration example runs without errors', () {
    expect(() => configuration.main(), returnsNormally);
  });
}
