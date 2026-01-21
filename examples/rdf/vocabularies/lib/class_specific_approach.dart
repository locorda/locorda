/// Example demonstrating the class-specific approach to using RDF vocabularies.
///
/// This approach is beginner-friendly and provides IDE autocompletion for
/// properties that are valid for a specific RDF class.
library;

import 'package:locorda_rdf_core/core.dart';
import 'package:locorda_rdf_terms_common/foaf.dart';

void main() {
  final personIri = IriTerm('http://example.org/person/jane_doe');

  // Create a graph using class-specific constants
  // FoafPerson provides all properties relevant to a FOAF Person
  final graph = RdfGraph.fromTriples([
    // Use FoafPerson class for type-safe property access
    Triple(personIri, FoafPerson.rdfType, FoafPerson.classIri),
    Triple(personIri, FoafPerson.name, LiteralTerm.string('Jane Doe')),
    Triple(personIri, FoafPerson.givenName, LiteralTerm.string('Jane')),
    Triple(personIri, FoafPerson.familyName, LiteralTerm.string('Doe')),
    Triple(personIri, FoafPerson.age, LiteralTerm.integer(42)),
    Triple(personIri, FoafPerson.mbox, IriTerm('mailto:jane.doe@example.com')),
  ]);

  print('Class-Specific Approach Example:');
  print(RdfCore.withStandardCodecs().encode(graph));
}
