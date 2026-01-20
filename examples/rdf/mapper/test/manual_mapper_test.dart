import 'package:locorda_rdf_mapper/mapper.dart';
import 'package:test/test.dart';
import '../lib/manual_mapper.dart';

void main() {
  group('Manual Mappers Example', () {
    test('manual mapper serializes and deserializes book', () {
      final mapper = RdfMapper.withDefaultRegistry()
        ..registerMapper<Book>(BookMapper());

      final book = Book(
        isbn: '978-0-544-00341-5',
        title: 'The Hobbit',
        author: 'J.R.R. Tolkien',
      );

      // Serialize
      final turtle = mapper.encodeObject(book);
      expect(turtle, contains('The Hobbit'));
      expect(turtle, contains('J.R.R. Tolkien'));

      // Deserialize
      final deserializedBook = mapper.decodeObject<Book>(turtle);
      expect(deserializedBook.title, 'The Hobbit');
      expect(deserializedBook.author, 'J.R.R. Tolkien');
    });
  });
}
