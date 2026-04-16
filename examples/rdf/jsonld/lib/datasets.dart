// Working with RDF datasets and named graphs via JSON-LD
import 'package:locorda_rdf_jsonld/jsonld.dart';

void main() {
  final jsonLdData = '''
  {
    "@context": { "ex": "http://example.org/" },
    "@graph": [
      {
        "@id": "ex:alice",
        "ex:name": "Alice",
        "ex:knows": { "@id": "ex:bob" }
      },
      {
        "@id": "ex:bob",
        "ex:name": "Bob"
      }
    ]
  }
  ''';

  // Decode to a full RDF dataset (preserves named graphs)
  final dataset = jsonld.decode(jsonLdData);

  print('Default graph: ${dataset.defaultGraph.size} triples');
  print('Named graphs: ${dataset.namedGraphs.length}');

  // Encode the dataset back to JSON-LD
  final encoded = jsonld.encode(dataset);
  print('\nEncoded JSON-LD:\n$encoded');
}
