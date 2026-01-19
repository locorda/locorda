import 'package:locorda_rdf_core/core.dart';

void main() {
  // Create individual triples
  final subject = const IriTerm('http://example.org/alice');
  final predicate = const IriTerm('http://xmlns.com/foaf/0.1/name');
  final object = LiteralTerm.string('Alice');
  final triple = Triple(subject, predicate, object);

  // Create graph with triples
  final graph = RdfGraph(triples: [triple]);

  print('Created graph with ${graph.triples.length} triple(s)');
  print('\nTriples:');
  for (final t in graph.triples) {
    print('  ${t.subject} ${t.predicate} ${t.object}');
  }

  // Add more triples using withTriple
  final age = const IriTerm('http://xmlns.com/foaf/0.1/age');
  final updatedGraph = graph.withTriple(
    Triple(subject, age, LiteralTerm.integer(30)),
  );

  print('\nUpdated graph has ${updatedGraph.triples.length} triples');

  // Encode to Turtle
  print('\nTurtle format:');
  print(turtle.encode(updatedGraph));
}
