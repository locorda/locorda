import 'package:locorda_rdf_core/core.dart';

void main() {
  // Create two separate graphs
  final graph1 = RdfGraph(triples: [
    Triple(
      const IriTerm('http://example.org/alice'),
      const IriTerm('http://xmlns.com/foaf/0.1/name'),
      LiteralTerm.string('Alice'),
    ),
    Triple(
      const IriTerm('http://example.org/alice'),
      const IriTerm('http://xmlns.com/foaf/0.1/age'),
      LiteralTerm.integer(30),
    ),
  ]);

  final graph2 = RdfGraph(triples: [
    Triple(
      const IriTerm('http://example.org/bob'),
      const IriTerm('http://xmlns.com/foaf/0.1/name'),
      LiteralTerm.string('Bob'),
    ),
    Triple(
      const IriTerm('http://example.org/alice'),
      const IriTerm('http://xmlns.com/foaf/0.1/knows'),
      const IriTerm('http://example.org/bob'),
    ),
  ]);

  print('Graph 1 has ${graph1.triples.length} triples');
  print('Graph 2 has ${graph2.triples.length} triples');

  // Merge graphs
  final merged = graph1.merge(graph2);
  print('\nMerged graph has ${merged.triples.length} triples');

  // Query for specific patterns
  final alice = const IriTerm('http://example.org/alice');
  final aliceTriples = merged.findTriples(subject: alice);

  print('\nAll triples about Alice:');
  for (final triple in aliceTriples) {
    print('  ${triple.predicate} -> ${triple.object}');
  }

  // Check if triple exists
  final foafKnows = const IriTerm('http://xmlns.com/foaf/0.1/knows');
  if (merged.hasTriples(subject: alice, predicate: foafKnows)) {
    print('\nAlice knows someone!');
  }

  // Create filtered graph
  final aliceGraph = merged.matching(subject: alice);
  print(
      '\nFiltered graph with only Alice has ${aliceGraph.triples.length} triples');
}
