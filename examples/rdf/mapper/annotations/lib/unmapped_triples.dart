import 'package:locorda_rdf_core/core.dart';
import 'package:locorda_rdf_mapper_annotations/annotations.dart';
import 'package:locorda_rdf_terms_schema/schema.dart';

/// @RdfUnmappedTriples preserves triples not mapped to fields.
/// Enables lossless round-trip conversion.
@RdfGlobalResource(
  SchemaBook.classIri,
  IriStrategy('https://example.org/books/{isbn}'),
)
class Book {
  @RdfIriPart()
  final String isbn;

  @RdfProperty(SchemaBook.name)
  final String title;

  /// All unmapped triples are stored here
  @RdfUnmappedTriples()
  final RdfGraph unmappedProperties;

  Book({
    required this.isbn,
    required this.title,
    RdfGraph? unmappedProperties,
  }) : unmappedProperties = unmappedProperties ?? RdfGraph();
}
