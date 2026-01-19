import 'package:locorda_rdf_core/core.dart';

void main() {
  // Sample data in Turtle format
  final turtleData = '''
    @prefix foaf: <http://xmlns.com/foaf/0.1/> .
    <http://example.org/alice> foaf:name "Alice" ;
                                foaf:age 30 .
  ''';

  // Using the preconfigured RdfCore instance
  // Decode with explicit content type
  print('1. Decoding Turtle with RdfCore:');
  final graph = rdf.decode(turtleData, contentType: 'text/turtle');
  print('   Decoded ${graph.triples.length} triples');

  // Encode to different format
  print('\n2. Encoding to JSON-LD:');
  final jsonld = rdf.encode(graph, contentType: 'application/ld+json');
  print(jsonld);

  // Encode to N-Triples
  print('\n3. Encoding to N-Triples:');
  final ntriples = rdf.encode(graph, contentType: 'application/n-triples');
  print(ntriples);

  // Working with datasets and N-Quads
  print('\n4. Working with Datasets:');
  final quadsData = '''
    <http://example.org/alice> <http://xmlns.com/foaf/0.1/name> "Alice" .
    <http://example.org/bob> <http://xmlns.com/foaf/0.1/name> "Bob" <http://example.org/graph1> .
  ''';

  final dataset =
      rdf.decodeDataset(quadsData, contentType: 'application/n-quads');
  print('   Default graph: ${dataset.defaultGraph.triples.length} triples');
  print('   Named graphs: ${dataset.namedGraphs.length}');

  // Encode dataset back to N-Quads
  final encodedDataset =
      rdf.encodeDataset(dataset, contentType: 'application/n-quads');
  print('\n5. Encoded Dataset:');
  print(encodedDataset);

  // Format auto-detection (when contentType is omitted)
  print('\n6. Auto-detection:');
  final autoDetected = rdf.decode(turtleData); // Automatically detects Turtle
  print('   Auto-detected and decoded ${autoDetected.triples.length} triples');
}
