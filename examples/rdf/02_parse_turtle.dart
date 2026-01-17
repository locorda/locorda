import 'package:locorda_rdf_core/core.dart';

void main() {
  final turtleData = '''
    @prefix foaf: <http://xmlns.com/foaf/0.1/> .
    <http://example.org/alice> foaf:name "Alice"@en .
  ''';

  final graph = turtle.decode(turtleData);

  print('Triples: ${graph.triples.length}'); // Triples: 1
}
