import 'package:test/test.dart';
import '../02_parse_turtle.dart' as example;

void main() {
  test('02_parse_turtle runs without errors', () {
    expect(() => example.main(), returnsNormally);
  });
}
