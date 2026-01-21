/// Example demonstrating the direct vocabulary approach to using RDF vocabularies.
///
/// This approach is for RDF experts who want maximum flexibility and concise syntax.
library;

import 'package:locorda_rdf_core/core.dart';
import 'package:locorda_rdf_terms_common/foaf.dart';
import 'package:locorda_rdf_terms_core/rdf.dart';
import 'package:locorda_rdf_terms_common/dc.dart';

void main() {
  final personIri = IriTerm('http://example.org/person/jane_doe');

  // Create a graph with direct vocabulary access
  // Mix vocabularies freely for maximum flexibility
  final graph = RdfGraph.fromTriples([
    Triple(personIri, Rdf.type, Foaf.Person),
    Triple(personIri, Foaf.name, LiteralTerm.string('Jane Doe')),
    Triple(personIri, Foaf.age, LiteralTerm.integer(42)),
    Triple(personIri, Dc.creator, LiteralTerm.string('System')),
  ]);

  print('Direct Vocabulary Approach Example:');
  print(RdfCore.withStandardCodecs().encode(graph));
}
