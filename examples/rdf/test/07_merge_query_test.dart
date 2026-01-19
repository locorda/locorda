import 'package:test/test.dart';

import '../07_merge_query.dart' as app;

void main() {
  test('merge and query example runs without errors', () {
    expect(() => app.main(), returnsNormally);
  });
}
