import 'package:locorda_rdf_mapper_annotations/annotations.dart';
import 'package:locorda_rdf_terms_schema/schema.dart';

// Import the generated init file (created by build_runner) - needed by main() below
import 'init_rdf_mapper.g.dart';

// Annotate your domain model
@RdfGlobalResource(
  SchemaBook.classIri,
  IriStrategy('{+baseUri}/books/{isbn}'),
)
class Book {
  @RdfIriPart()
  final String isbn;

  @RdfProperty(SchemaBook.name)
  final String title;

  @RdfProperty(SchemaBook.author)
  final String author;

  @RdfProperty(SchemaBook.datePublished)
  final DateTime published;

  Book({
    required this.isbn,
    required this.title,
    required this.author,
    required this.published,
  });
}

void main() {
  // After running 'dart run build_runner build', use the generated mapper:
  // Initialize generated mapper
  final mapper = initRdfMapper(
    baseUriProvider: () => 'https://example.org',
  );

  // Serialize to RDF
  final book = Book(
    isbn: '978-0-544-00341-5',
    title: 'The Hobbit',
    author: 'J.R.R. Tolkien',
    published: DateTime(1937, 9, 21),
  );

  final turtle = mapper.encodeObject(book);
  print(turtle);

  // Deserialize from RDF
  final deserializedBook = mapper.decodeObject<Book>(turtle);
  print('Title: ${deserializedBook.title}');
}
