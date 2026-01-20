import 'package:locorda_rdf_mapper_annotations/annotations.dart';
import 'package:locorda_rdf_terms_schema/schema.dart';

/// Enum mapped to IRIs using @RdfIri annotation with template.
/// Use @RdfEnumValue to customize individual enum values.
@RdfIri('https://schema.org/{value}')
enum BookFormat {
  @RdfEnumValue('Hardcover')
  hardcover,

  @RdfEnumValue('Paperback')
  paperback,

  @RdfEnumValue('EBook')
  ebook,
}

@RdfGlobalResource(
  SchemaBook.classIri,
  IriStrategy('https://example.org/books/{isbn}'),
)
class Book {
  @RdfIriPart()
  final String isbn;

  @RdfProperty(SchemaBook.name)
  final String title;

  @RdfProperty(SchemaBook.bookFormat)
  final BookFormat format;

  Book({
    required this.isbn,
    required this.title,
    required this.format,
  });
}
