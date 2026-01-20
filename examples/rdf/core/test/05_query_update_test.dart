import 'package:test/test.dart';
import 'package:locorda_rdf_core/core.dart';

void main() {
  test('05_query_update example runs without errors', () {
    final alice = const IriTerm('http://example.org/alice');
    final bob = const IriTerm('http://example.org/bob');
    final charlie = const IriTerm('http://example.org/charlie');
    final foafKnows = const IriTerm('http://xmlns.com/foaf/0.1/knows');

    final graph = RdfGraph(triples: [
      Triple(alice, foafKnows, bob),
      Triple(bob, foafKnows, charlie),
    ]);

    final knowsTriples = graph.findTriples(predicate: foafKnows);
    expect(knowsTriples.length, 2);

    final updatedGraph = graph.withTriple(Triple(alice, foafKnows, charlie));
    expect(updatedGraph.triples.length, 3);
    expect(updatedGraph.hasTriples(subject: alice, object: charlie), true);
  });
}
