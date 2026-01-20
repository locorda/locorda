import 'package:locorda_rdf_core/core.dart';
import 'package:test/test.dart';
import '../lib/unmapped_triples.dart';

void main() {
  test('Unmapped triples annotation compiles', () {
    final book = Book(
      isbn: '978-0-544-00341-5',
      title: 'The Hobbit',
      unmappedProperties: RdfGraph(triples: [
        Triple(
          IriTerm('https://example.org/books/978-0-544-00341-5'),
          IriTerm('https://schema.org/publisher'),
          LiteralTerm('George Allen & Unwin'),
        ),
      ]),
    );
    expect(book.unmappedProperties.triples.length, 1);
  });
}
