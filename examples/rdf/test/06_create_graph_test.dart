import 'package:test/test.dart';

import '../06_create_graph.dart' as app;

void main() {
  test('create graph example runs without errors', () {
    expect(() => app.main(), returnsNormally);
  });
}
