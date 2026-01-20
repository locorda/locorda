import 'package:test/test.dart';
import '../lib/map_entries.dart';

void main() {
  test('Map entry annotations compile', () {
    final book = Book(
      isbn: '978-0-544-00341-5',
      title: 'The Hobbit',
      translations: {'de': 'Der Hobbit', 'fr': 'Le Hobbit'},
    );
    expect(book.translations['de'], 'Der Hobbit');
  });
}
