import 'package:test/test.dart';

import '../04_dataset_quads.dart' as app;

void main() {
  test('dataset example runs without errors', () {
    expect(() => app.main(), returnsNormally);
  });
}
