import 'package:test/test.dart';
import '../lib/property_annotations.dart';

void main() {
  test('Property annotations compile', () {
    final book = Book(
      isbn: '978-0-544-00341-5',
      title: 'The Hobbit',
      author: 'J.R.R. Tolkien',
      tags: ['fantasy', 'adventure'],
    );
    expect(book.tags.length, 2);
  });
}
