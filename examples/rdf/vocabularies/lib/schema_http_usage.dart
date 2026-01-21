import 'package:locorda_rdf_core/core.dart';
import 'package:locorda_rdf_terms_schema_http/schema_http.dart';

void main() {
  final personIri = IriTerm('http://example.org/person/jane');

  final graph = RdfGraph.fromTriples([
    Triple(personIri, SchemaHttpPerson.rdfType, SchemaHttpPerson.classIri),
    Triple(personIri, SchemaHttpPerson.name, LiteralTerm.string('Jane Doe')),
    Triple(
      personIri,
      SchemaHttpPerson.email,
      LiteralTerm.string('jane@example.com'),
    ),
    Triple(
      personIri,
      SchemaHttpPerson.jobTitle,
      LiteralTerm.string('Data Engineer'),
    ),
    Triple(
      personIri,
      SchemaHttpPerson.worksFor,
      IriTerm('http://example.org/org/locorda'),
    ),
  ]);

  print(turtle.encode(graph));
}
