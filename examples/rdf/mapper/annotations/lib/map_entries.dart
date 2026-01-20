import 'package:locorda_rdf_mapper_annotations/annotations.dart';
import 'package:locorda_rdf_terms_schema/schema.dart';

/// Maps require custom entry classes with @RdfMapEntry.
@RdfGlobalResource(
  SchemaBook.classIri,
  IriStrategy('https://example.org/books/{isbn}'),
)
class Book {
  @RdfIriPart()
  final String isbn;

  @RdfProperty(SchemaBook.name)
  final String title;

  /// Map of language codes to translated titles
  @RdfProperty(SchemaBook.review)
  @RdfMapEntry(TranslationEntry)
  final Map<String, String> translations;

  Book({
    required this.isbn,
    required this.title,
    this.translations = const {},
  });
}

/// Entry class for Map<String, String>
@RdfLocalResource(SchemaReview.classIri)
class TranslationEntry {
  @RdfMapKey()
  @RdfProperty(SchemaReview.inLanguage)
  final String language;

  @RdfMapValue()
  @RdfProperty(SchemaReview.reviewBody)
  final String text;

  TranslationEntry({required this.language, required this.text});
}
