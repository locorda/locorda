import 'package:locorda_rdf_core/core.dart';

void main() {
  // Example: Decode a JSON-LD document
  final jsonLdData = '''
  {
    "@context": {
      "name": "http://xmlns.com/foaf/0.1/name",
      "knows": {
        "@id": "http://xmlns.com/foaf/0.1/knows",
        "@type": "@id"
      },
      "Person": "http://xmlns.com/foaf/0.1/Person"
    },
    "@id": "http://example.org/alice",
    "@type": "Person",
    "name": "Alice",
    "knows": [
      {
        "@id": "http://example.org/bob",
        "@type": "Person",
        "name": "Bob"
      }
    ]
  }
  ''';

  // Using the convenience global variable
  final graph = jsonldGraph.decode(jsonLdData);

  // Print decoded triples
  print('Decoded ${graph.triples.length} triples:');
  for (final triple in graph.triples) {
    print('${triple.subject} ${triple.predicate} ${triple.object}');
  }

  // Encode the graph back to JSON-LD
  final serialized = jsonldGraph.encode(graph);
  print('\nEncoded JSON-LD:');
  print(serialized);
}
