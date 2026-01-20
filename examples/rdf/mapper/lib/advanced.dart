import 'package:locorda_rdf_core/core.dart';
import 'package:locorda_rdf_mapper_annotations/annotations.dart';
import 'package:locorda_rdf_terms_schema/schema.dart';

// Import the generated init file (created by build_runner) - needed by main() below
import 'init_rdf_mapper.g.dart';

// Complex IRI strategies with context variables
@RdfGlobalResource(
  SchemaBook.classIri,
  IriStrategy('{+baseUri}/books/{isbn}'),
)
class Book {
  @RdfIriPart()
  final String isbn;

  @RdfProperty(SchemaBook.name)
  final String title;

  // Enum as IRI
  @RdfProperty(SchemaBook.bookFormat)
  final BookFormat format;

  // Custom literal type with language tag
  @RdfProperty(
    SchemaBook.description,
    literal: LiteralMapping.withLanguage('en'),
  )
  final String description;

  Book({
    required this.isbn,
    required this.title,
    required this.format,
    required this.description,
  });
}

// Enum mapping to IRIs
@RdfIri('https://schema.org/BookFormatType/{value}')
enum BookFormat {
  @RdfEnumValue('Hardcover')
  hardcover,

  @RdfEnumValue('Paperback')
  paperback,

  @RdfEnumValue('EBook')
  ebook,
}

// Custom literal type
@RdfLiteral()
class ISBN {
  @RdfValue()
  final String value;

  ISBN(this.value);

  // Custom serialization
  LiteralTerm toRdfTerm() {
    return LiteralTerm(value);
  }

  // Custom deserialization
  static ISBN fromRdfTerm(LiteralTerm term) {
    return ISBN(term.value);
  }
}

void main() {
  // After generation, initialize with context providers:
  final mapper = initRdfMapper(
    baseUriProvider: () => 'https://library.example.org',
  );

  final book = Book(
    isbn: '978-0-544-00341-5',
    title: 'The Hobbit',
    format: BookFormat.hardcover,
    description: 'A fantasy adventure novel',
  );

  final turtle = mapper.encodeObject(book);
  print(turtle);
  // IRI will be: https://library.example.org/books/978-0-544-00341-5
  // format will be: <https://schema.org/BookFormatType/Hardcover>
  // description will have @en language tag
}
