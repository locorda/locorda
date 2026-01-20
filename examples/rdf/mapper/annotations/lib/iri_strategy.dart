import 'package:locorda_rdf_mapper_annotations/annotations.dart';
import 'package:locorda_rdf_terms_schema/schema.dart';

/// IriStrategy with template placeholders.
/// Use @RdfIriPart() to mark fields that fill the template.
@RdfGlobalResource(
  SchemaPerson.classIri,
  IriStrategy('https://example.org/users/{username}'),
)
class User {
  @RdfIriPart()
  final String username;

  @RdfProperty(SchemaPerson.name)
  final String fullName;

  User({required this.username, required this.fullName});
}

/// IriStrategy with baseUri parameter.
/// Useful for dynamic base URIs.
@RdfGlobalResource(
  SchemaProduct.classIri,
  IriStrategy('{+baseUri}/products/{id}'),
)
class Product {
  @RdfIriPart()
  final String id;

  @RdfProperty(SchemaProduct.name)
  final String name;

  Product({required this.id, required this.name});
}
