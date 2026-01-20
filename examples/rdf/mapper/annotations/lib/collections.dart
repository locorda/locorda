import 'package:locorda_rdf_mapper_annotations/annotations.dart';
import 'package:locorda_rdf_terms_schema/schema.dart';

/// Collections (List, Set) are automatically supported.
@RdfGlobalResource(
  SchemaBook.classIri,
  IriStrategy('https://example.org/books/{isbn}'),
)
class Book {
  @RdfIriPart()
  final String isbn;

  @RdfProperty(SchemaBook.name)
  final String title;

  /// List of strings
  @RdfProperty(SchemaBook.keywords)
  final List<String> tags;

  /// Set of strings (no duplicates)
  @RdfProperty(SchemaBook.author)
  final Set<String> authors;

  /// RDF List (ordered collection)
  @RdfProperty(SchemaBook.hasPart, collection: rdfList)
  final List<Chapter> chapters;

  Book({
    required this.isbn,
    required this.title,
    this.tags = const [],
    this.authors = const {},
    this.chapters = const [],
  });
}

@RdfLocalResource(SchemaChapter.classIri)
class Chapter {
  @RdfProperty(SchemaChapter.name)
  final String title;

  Chapter({required this.title});
}
