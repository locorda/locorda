import 'package:locorda_rdf_core/core.dart';

void main() {
  final turtleData = '''
    @prefix ex: <http://example.org/> .
    @prefix foaf: <http://xmlns.com/foaf/0.1/> .
    
    ex:Alice foaf:knows ex:Bob .
    ex:Bob foaf:knows ex:Charlie .
  ''';

  final graph = turtle.decode(turtleData);

  // Find all triples where the predicate is foaf:knows
  final knowsTriples =
      graph.findTriples(predicate: IriTerm('http://xmlns.com/foaf/0.1/knows'));

  print('People who know someone:');
  for (final triple in knowsTriples) {
    print('  ${triple.subject}');
  }

  // Add new triple (creates new immutable graph)
  final updatedGraph = graph.withTriple(Triple(
    IriTerm('http://example.org/Bob'),
    IriTerm('http://xmlns.com/foaf/0.1/knows'),
    IriTerm('http://example.org/David'),
  ));

  print('\nTotal triples: ${updatedGraph.triples.length}');
}
