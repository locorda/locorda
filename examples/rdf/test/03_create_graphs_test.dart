import 'package:test/test.dart';
import 'package:locorda_rdf_core/core.dart';

void main() {
  test('03_create_graphs example runs without errors', () {
    final alice = const IriTerm('http://example.org/alice');
    final foafName = const IriTerm('http://xmlns.com/foaf/0.1/name');
    final foafAge = const IriTerm('http://xmlns.com/foaf/0.1/age');

    final triple = Triple(alice, foafName, LiteralTerm.string('Alice'));
    final graph = RdfGraph(triples: [triple]);
    expect(graph.triples.length, 1);

    final updatedGraph = graph.withTriple(
      Triple(alice, foafAge, LiteralTerm.integer(30)),
    );
    expect(updatedGraph.triples.length, 2);
  });
}
