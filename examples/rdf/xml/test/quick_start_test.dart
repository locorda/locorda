import 'package:test/test.dart';
import 'package:rdf_xml_examples/quick_start.dart' as quick_start;

void main() {
  test('quick_start example runs without errors', () {
    expect(() => quick_start.main(), returnsNormally);
  });
}
