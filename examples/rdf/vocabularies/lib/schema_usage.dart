import 'package:locorda_rdf_core/core.dart';
import 'package:locorda_rdf_terms_schema/schema.dart';

void main() {
  final personIri = IriTerm('http://example.org/person/jane');

  final graph = RdfGraph.fromTriples([
    Triple(personIri, SchemaPerson.rdfType, SchemaPerson.classIri),
    Triple(personIri, SchemaPerson.name, LiteralTerm.string('Jane Doe')),
    Triple(
        personIri, SchemaPerson.email, LiteralTerm.string('jane@example.com')),
    Triple(
        personIri, SchemaPerson.jobTitle, LiteralTerm.string('Data Engineer')),
    Triple(
      personIri,
      SchemaPerson.worksFor,
      IriTerm('http://example.org/org/locorda'),
    ),
  ]);

  print(turtle.encode(graph));
}
