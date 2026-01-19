import 'package:test/test.dart';
import 'package:locorda_rdf_core/core.dart';
import '../05_jsonld.dart' as app;

void main() {
  test('JSON-LD example runs without errors', () {
    expect(() => app.main(), returnsNormally);
  });
}
