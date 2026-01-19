import 'package:test/test.dart';

import '../05_jsonld.dart' as app;

void main() {
  test('JSON-LD example runs without errors', () {
    expect(() => app.main(), returnsNormally);
  });
}
