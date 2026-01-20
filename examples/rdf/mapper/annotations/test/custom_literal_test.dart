import 'package:test/test.dart';
import 'package:locorda_rdf_mapper_annotations/annotations.dart';
import '../lib/custom_literal.dart';

void main() {
  group('ISBN', () {
    test('accepts valid ISBN-10', () {
      expect(() => ISBN('1234567890'), returnsNormally);
      expect(() => ISBN('043942089X'), returnsNormally);
    });

    test('accepts valid ISBN-13', () {
      expect(() => ISBN('9780596520687'), returnsNormally);
    });

    test('rejects invalid ISBN', () {
      expect(() => ISBN('invalid'), throwsArgumentError);
      expect(() => ISBN('978-0-596-52068-7'),
          throwsArgumentError); // hyphens not allowed
      expect(() => ISBN('12345'), throwsArgumentError); // too short
    });

    test('value is accessible', () {
      final isbn = ISBN('9780596520687');
      expect(isbn.value, equals('9780596520687'));
    });
  });

  group('Temperature', () {
    test('stores celsius value', () {
      final temp = Temperature(25.5);
      expect(temp.celsius, equals(25.5));
    });

    test('formats to string with °C', () {
      final temp = Temperature(100.0);
      final formatted = temp.formatCelsius();
      expect(formatted.value, equals('100.0°C'));
    });

    test('parses from formatted string', () {
      final content = LiteralContent('37.5°C');
      final temp = Temperature.parse(content);
      expect(temp.celsius, equals(37.5));
    });

    test('round-trip conversion', () {
      final original = Temperature(21.3);
      final content = original.formatCelsius();
      final parsed = Temperature.parse(content);
      expect(parsed.celsius, equals(original.celsius));
    });
  });
}
