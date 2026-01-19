import 'package:test/test.dart';

import '../08_rdfcore_contenttypes.dart' as app;

void main() {
  test('RdfCore content types example runs without errors', () {
    expect(() => app.main(), returnsNormally);
  });
}
