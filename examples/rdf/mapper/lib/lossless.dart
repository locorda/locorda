import 'package:locorda_rdf_core/core.dart';
import 'package:locorda_rdf_mapper_annotations/annotations.dart';
import 'package:locorda_rdf_terms_schema/schema.dart';

// Import the generated init file (created by build_runner) - needed by main() below
import 'init_rdf_mapper.g.dart';

// Lossless mapping with DECOUPLED unmapped triples
// Keeps domain model clean - unmapped triples stored separately
@RdfGlobalResource(
  IriTerm('https://example.org/vocab/LosslessBook'),
  IriStrategy('{+baseUri}/lossless-books/{isbn}'),
)
class BookLossless {
  @RdfIriPart()
  final String isbn;

  @RdfProperty(SchemaBook.name)
  final String title;

  @RdfProperty(SchemaBook.author)
  final String author;

  BookLossless({
    required this.isbn,
    required this.title,
    required this.author,
  });
}

// Alternative: Use @RdfUnmappedTriples to store unmapped triples
// INSIDE domain objects (by default only captures triples about that specific object)

void main() {
  // RDF data with unmapped properties + unrelated triples
  const rdfData = '''
@prefix schema: <https://schema.org/> .
@prefix ex: <https://example.org/vocab/> .

<https://example.org/lossless-books/978-0-544-00341-5> a ex:LosslessBook ;
  schema:name "The Hobbit" ;
  schema:author "J.R.R. Tolkien" ;
  schema:publisher "George Allen & Unwin" ;
  schema:isbn "978-0-544-00341-5" ;
  schema:numberOfPages "310" .

# Unrelated triples in the document
<https://example.org/publishers/allen-unwin> a schema:Organization ;
  schema:name "George Allen & Unwin" ;
  schema:location "London" .
''';

  final mapper = initRdfMapper(
    baseUriProvider: () => 'https://example.org',
  );

  // Decode with separate unmapped triples storage
  final (book, unmappedTriples) =
      mapper.decodeObjectLossless<BookLossless>(rdfData);

  print('Book domain object is clean (no unmapped field)');
  print(
      'Unmapped triples stored separately: ${unmappedTriples.triples.length}');
  // Includes: publisher, numberOfPages (book's) + ALL unrelated publisher triples

  // Perfect round-trip - ALL triples preserved
  final restoredRdf = mapper.encodeObjectLossless((book, unmappedTriples));
  print('\nRestored RDF (everything preserved):\n$restoredRdf');
  // Contains: book properties + unmapped book properties + unrelated triples!
}
