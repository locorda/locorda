import 'package:locorda_rdf_core/core.dart';
import 'package:locorda_rdf_terms_core/rdf.dart';
import 'package:locorda_rdf_terms_core/rdfs.dart';
import 'package:locorda_rdf_terms_core/owl.dart';

void main() {
  final conceptIri = IriTerm('http://example.org/concept/Mammal');

  // Create a graph using core vocabularies
  final graph = RdfGraph.fromTriples([
    Triple(conceptIri, Rdf.type, Owl.Class),
    Triple(conceptIri, Rdfs.label, LiteralTerm.string('Mammal')),
    Triple(conceptIri, Rdfs.comment,
        LiteralTerm.string('A warm-blooded vertebrate animal')),
    Triple(conceptIri, Rdfs.subClassOf,
        IriTerm('http://example.org/concept/Animal')),
  ]);

  print(turtle.encode(graph));
}
