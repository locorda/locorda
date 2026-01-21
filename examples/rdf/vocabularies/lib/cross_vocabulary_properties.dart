/// Example demonstrating cross-vocabulary properties in class-specific constants.
///
/// Shows how SchemaPerson includes properties from related vocabularies like FOAF,
/// enabling seamless vocabulary mixing through IDE autocompletion.
library;

import 'package:locorda_rdf_core/core.dart';
import 'package:locorda_rdf_terms_schema/schema.dart';

void main() {
  final personIri = IriTerm('http://example.org/person/jane_doe');
  final friendIri = IriTerm('http://example.org/person/john_smith');

  // SchemaPerson includes common FOAF properties
  // Discover them via IDE autocompletion!
  final graph = RdfGraph.fromTriples([
    // Related RDF properties like rdf:type are accessible through SchemaPerson context
    Triple(personIri, SchemaPerson.rdfType, SchemaPerson.classIri),

    // Pure schema.org properties for schema:Person
    Triple(personIri, SchemaPerson.name, LiteralTerm.string('Jane Doe')),
    Triple(
        personIri, SchemaPerson.email, LiteralTerm.string('jane@example.com')),

    // Related FOAF properties are accessible through SchemaPerson context
    Triple(personIri, SchemaPerson.foafAge,
        LiteralTerm.integer(42)), // FOAF property!
    Triple(personIri, SchemaPerson.foafKnows, friendIri), // FOAF relationship!
  ]);

  print('Cross-Vocabulary Properties Example:');
  print(RdfCore.withStandardCodecs().encode(graph));
}
