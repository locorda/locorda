import 'package:test/test.dart';
import '../lib/enum_mapping.dart';

void main() {
  test('Enum mapping annotations compile', () {
    final book = Book(
      isbn: '978-0-544-00341-5',
      title: 'The Hobbit',
      format: BookFormat.hardcover,
    );
    expect(book.format, BookFormat.hardcover);
  });
}
