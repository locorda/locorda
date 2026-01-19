import 'package:test/test.dart';
import 'package:locorda_rdf_core/core.dart';
import '../04_dataset_quads.dart' as app;

void main() {
  test('dataset example runs without errors', () {
    expect(() => app.main(), returnsNormally);
  });
}
