import 'package:test/test.dart';
import '../lib/streaming.dart' as example;

void main() {
  test('streaming runs without errors', () async {
    await expectLater(() => example.main(), returnsNormally);
  });
}
