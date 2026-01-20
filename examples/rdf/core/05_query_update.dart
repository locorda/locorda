import 'package:locorda_rdf_core/core.dart';

void main() {
  // Start with a graph
  final alice = const IriTerm('http://example.org/alice');
  final bob = const IriTerm('http://example.org/bob');
  final charlie = const IriTerm('http://example.org/charlie');
  final foafKnows = const IriTerm('http://xmlns.com/foaf/0.1/knows');

  final graph = RdfGraph(triples: [
    Triple(alice, foafKnows, bob),
    Triple(bob, foafKnows, charlie),
  ]);

  // Query: Find all "knows" relationships
  final knowsTriples = graph.findTriples(predicate: foafKnows);

  print('People who know someone:');
  for (final triple in knowsTriples) {
    print('  ${triple.subject} knows ${triple.object}');
  }

  // Update: Add new triple (returns new immutable graph)
  final updatedGraph = graph.withTriple(Triple(alice, foafKnows, charlie));

  print('\nTotal triples: ${updatedGraph.triples.length}');

  // Check existence
  if (updatedGraph.hasTriples(subject: alice, object: charlie)) {
    print('Alice knows Charlie!');
  }
}
