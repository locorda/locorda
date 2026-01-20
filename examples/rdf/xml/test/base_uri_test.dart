import 'package:test/test.dart';
import 'package:rdf_xml_examples/base_uri.dart' as base_uri;

void main() {
  test('base_uri example runs without errors', () {
    expect(() => base_uri.main(), returnsNormally);
  });
}
