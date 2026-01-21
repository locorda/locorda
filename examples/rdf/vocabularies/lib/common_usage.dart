import 'package:locorda_rdf_core/core.dart';
import 'package:locorda_rdf_terms_common/foaf.dart';
import 'package:locorda_rdf_terms_common/dc.dart';

void main() {
  final personIri = IriTerm('http://example.org/person/jane');

  // Use FOAF for person data
  final graph = RdfGraph.fromTriples([
    Triple(personIri, Foaf.name, LiteralTerm('Jane Doe')),
    Triple(personIri, Foaf.mbox, IriTerm('mailto:jane@example.com')),
    Triple(personIri, Dc.creator, LiteralTerm('System')),
  ]);

  print(turtle.encode(graph));
}
