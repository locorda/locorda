import 'package:test/test.dart';
import '../lib/collections.dart';

void main() {
  test('Collection annotations compile', () {
    final book = Book(
      isbn: '978-0-544-00341-5',
      title: 'The Hobbit',
      tags: ['fantasy', 'adventure'],
      authors: {'J.R.R. Tolkien'},
      chapters: [Chapter(title: 'An Unexpected Party')],
    );
    expect(book.chapters.length, 1);
  });
}
