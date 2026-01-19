import 'package:test/test.dart';

import '../09_custom_codecs.dart' as app;

void main() {
  test('custom codecs example runs without errors', () {
    expect(() => app.main(), returnsNormally);
  });
}
