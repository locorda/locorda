// Quick start: decode and encode JSON-LD
import 'package:locorda_rdf_jsonld/jsonld.dart';

void main() {
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
    "knows": "http://example.org/bob"
  }
  ''';

  // Decode JSON-LD to an RDF graph
  final graph = jsonldGraph.decode(jsonLdData);

  print('Parsed ${graph.size} triples:');
  for (final triple in graph.triples) {
    print('  $triple');
  }

  // Encode the graph back to JSON-LD
  final encoded = jsonldGraph.encode(graph);
  print('\nEncoded JSON-LD:\n$encoded');
}
