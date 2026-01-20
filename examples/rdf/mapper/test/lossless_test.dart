import 'package:rdf_mapper_examples/lossless.dart';
import 'package:test/test.dart';

import 'package:rdf_mapper_examples/init_rdf_mapper.g.dart';

void main() {
  group('Lossless Mapping Example', () {
    test('decodeObjectLossless preserves all unmapped triples', () {
      const rdfData = '''
@prefix schema: <https://schema.org/> .
@prefix ex: <https://example.org/vocab/> .

<https://example.org/lossless-books/978-0-544-00341-5> a ex:LosslessBook ;
  schema:name "The Hobbit" ;
  schema:author "J.R.R. Tolkien" ;
  schema:publisher "George Allen & Unwin" ;
  schema:isbn "978-0-544-00341-5" ;
  schema:numberOfPages "310" .

<https://example.org/publishers/allen-unwin> a schema:Organization ;
  schema:name "George Allen & Unwin" ;
  schema:location "London" .
''';

      final mapper = initRdfMapper(
        baseUriProvider: () => 'https://example.org',
      );
      final deser = mapper.registry.findDeserializerByType<BookLossless>();
      print('Using deserializer: $deser');
      print('RDF Data to decode:');
      print(rdfData);

      try {
        final (books, unmappedTriples) =
            mapper.decodeObjectsLossless<BookLossless>(rdfData);
        print('Unmapped triples: ${unmappedTriples.triples.length}');
        print('Unmapped triples: ${unmappedTriples.triples}');
        final book = books.first;
        print('Success! Book: ${book.title}');

        expect(book.isbn, '978-0-544-00341-5');
        expect(book.title, 'The Hobbit');
        expect(book.author, 'J.R.R. Tolkien');

        // Should include unmapped book properties + unrelated triples
        expect(unmappedTriples.triples.length, greaterThan(3));

        // Round-trip should preserve everything
        final restoredRdf =
            mapper.encodeObjectLossless((book, unmappedTriples));
        expect(restoredRdf, contains('publisher'));
        expect(restoredRdf, contains('George Allen & Unwin'));
        expect(restoredRdf, contains('numberOfPages'));
        expect(restoredRdf, contains('location'));
      } catch (e, st) {
        print('Error: $e');
        print('Stack: $st');
        rethrow;
      }
    });
  });
}
