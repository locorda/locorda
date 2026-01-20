import 'package:locorda_rdf_core/core.dart';

void main() {
  // Create individual triples
  final alice = const IriTerm('http://example.org/alice');
  final foafName = const IriTerm('http://xmlns.com/foaf/0.1/name');
  final foafAge = const IriTerm('http://xmlns.com/foaf/0.1/age');

  final triple = Triple(alice, foafName, LiteralTerm.string('Alice'));

  // Create graph from triples
  final graph = RdfGraph(triples: [triple]);
  print('Created graph with ${graph.triples.length} triple(s)');

  // Add more triples (immutable - returns new graph)
  final updatedGraph = graph.withTriple(
    Triple(alice, foafAge, LiteralTerm.integer(30)),
  );
  print('Updated graph has ${updatedGraph.triples.length} triples');

  // Note: For parsing, use turtle.decode(data) instead
  print('\nTurtle output:');
  print(turtle.encode(updatedGraph));
}
