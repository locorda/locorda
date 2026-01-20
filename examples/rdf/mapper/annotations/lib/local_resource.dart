import 'package:locorda_rdf_mapper_annotations/annotations.dart';
import 'package:locorda_rdf_terms_schema/schema.dart';

/// Local resources exist only in relation to a parent.
/// They're represented as blank nodes in RDF.
@RdfLocalResource(SchemaChapter.classIri)
class Chapter {
  @RdfProperty(SchemaChapter.name)
  final String title;

  @RdfProperty(SchemaChapter.position)
  final int number;

  Chapter({required this.title, required this.number});
}
