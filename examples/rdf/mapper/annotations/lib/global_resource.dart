import 'package:locorda_rdf_mapper_annotations/annotations.dart';
import 'package:locorda_rdf_terms_schema/schema.dart';

/// Global resources have globally unique IRIs.
/// They become subjects in RDF triples.
@RdfGlobalResource(
  SchemaBook.classIri,
  IriStrategy('https://example.org/books/{isbn}'),
)
class Book {
  @RdfIriPart()
  final String isbn;

  @RdfProperty(SchemaBook.name)
  final String title;

  Book({required this.isbn, required this.title});
}
