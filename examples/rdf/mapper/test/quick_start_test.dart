import 'package:test/test.dart';
import '../lib/quick_start.dart';

void main() {
  group('Quick Start Example', () {
    test('creates book with basic properties', () {
      final book = Book(
        isbn: '978-0-544-00341-5',
        title: 'The Hobbit',
        author: 'J.R.R. Tolkien',
        published: DateTime(1937, 9, 21),
      );

      expect(book.isbn, '978-0-544-00341-5');
      expect(book.title, 'The Hobbit');
      expect(book.author, 'J.R.R. Tolkien');
      expect(book.published.year, 1937);
    });

    // After code generation, add tests with generated mapper:
    // test('serializes book to RDF', () {
    //   final mapper = initRdfMapper();
    //   final book = Book(...);
    //   final turtle = mapper.encodeObject(book);
    //   expect(turtle, contains('schema:Book'));
    // });
  });
}
