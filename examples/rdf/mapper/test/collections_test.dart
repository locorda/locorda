import 'package:test/test.dart';
import '../lib/collections.dart';

void main() {
  group('Collections Example', () {
    test('creates book with collections', () {
      final book = Book(
        isbn: '978-0-544-00341-5',
        title: 'The Hobbit',
        chapters: [
          Chapter(title: 'An Unexpected Party', number: 1),
          Chapter(title: 'Roast Mutton', number: 2),
        ],
        keywords: {'fantasy', 'adventure', 'dragons'},
        reviews: {
          'Alice': Review(stars: 5),
          'Bob': Review(stars: 4),
        },
      );

      expect(book.chapters.length, 2);
      expect(book.keywords, {'fantasy', 'adventure', 'dragons'});
      expect(book.reviews['Alice']?.stars, 5);
    });
  });
}
