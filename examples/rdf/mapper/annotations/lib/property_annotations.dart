import 'package:locorda_rdf_mapper_annotations/annotations.dart';
import 'package:locorda_rdf_terms_schema/schema.dart';

/// @RdfProperty maps fields to RDF predicates.
@RdfGlobalResource(
  SchemaBook.classIri,
  IriStrategy('https://example.org/books/{isbn}'),
)
class Book {
  @RdfIriPart()
  final String isbn;

  /// Simple property mapping
  @RdfProperty(SchemaBook.name)
  final String title;

  /// Optional properties (nullable fields)
  @RdfProperty(SchemaBook.author)
  final String? author;

  /// Collections are automatically handled
  @RdfProperty(SchemaBook.keywords)
  final List<String> tags;

  Book({
    required this.isbn,
    required this.title,
    this.author,
    this.tags = const [],
  });
}
