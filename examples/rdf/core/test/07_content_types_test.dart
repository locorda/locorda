import 'package:test/test.dart';
import 'package:locorda_rdf_core/core.dart';

void main() {
  test('06_content_types example runs without errors', () {
    final turtleData = '''
      @prefix foaf: <http://xmlns.com/foaf/0.1/> .
      <http://example.org/alice> foaf:name "Alice" ;
                                  foaf:age 30 .
    ''';

    // Parse Turtle
    final graph = rdf.decode(turtleData, contentType: 'text/turtle');
    expect(graph.triples.length, 2);

    // Convert to JSON-LD
    final jsonld = rdf.encode(graph, contentType: 'application/ld+json');
    expect(jsonld, isNotEmpty);

    // Convert to N-Triples
    final ntriples = rdf.encode(graph, contentType: 'application/n-triples');
    expect(ntriples, isNotEmpty);
  });
}
