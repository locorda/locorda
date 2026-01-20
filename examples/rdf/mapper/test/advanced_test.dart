import 'package:test/test.dart';
import '../lib/advanced.dart';

void main() {
  group('Advanced Features Example', () {
    test('creates book with enum and custom types', () {
      final book = Book(
        isbn: '978-0-544-00341-5',
        title: 'The Hobbit',
        format: BookFormat.hardcover,
        description: 'A fantasy adventure novel',
      );

      expect(book.format, BookFormat.hardcover);
      expect(book.description, 'A fantasy adventure novel');
    });

    test('creates ISBN literal', () {
      final isbn = ISBN('978-0-544-00341-5');
      expect(isbn.value, '978-0-544-00341-5');
    });
  });
}
