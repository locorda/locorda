import 'package:locorda_rdf_core/core.dart';

void main() {
  final turtleData = '''
    @prefix foaf: <http://xmlns.com/foaf/0.1/> .
    <http://example.org/alice> foaf:name "Alice" ;
                                foaf:age 30 .
  ''';

  // Parse Turtle
  final graph = rdf.decode(turtleData, contentType: 'text/turtle');
  print('Parsed ${graph.triples.length} triples');

  // Convert to JSON-LD
  final jsonld = rdf.encode(graph, contentType: 'application/ld+json');
  print('\nJSON-LD:\n$jsonld');

  // Convert to N-Triples
  final ntriples = rdf.encode(graph, contentType: 'application/n-triples');
  print('\nN-Triples:\n$ntriples');
}
