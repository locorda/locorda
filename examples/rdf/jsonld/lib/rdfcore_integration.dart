// Integration with RdfCore for unified multi-format support
import 'package:locorda_rdf_core/core.dart';
import 'package:locorda_rdf_jsonld/jsonld.dart';

void main() {
  // Register JSON-LD alongside the built-in codecs (Turtle, N-Triples, …)
  final rdfCore = RdfCore.withStandardCodecs(
    additionalCodecs: [jsonldGraph],
    additionalDatasetCodecs: [jsonld],
  );

  const input = '''
  {
    "@context": { "ex": "http://example.org/" },
    "@id": "ex:alice",
    "ex:name": "Alice"
  }
  ''';

  // Decode by explicit content type
  final graph = rdfCore.decode(input, contentType: 'application/ld+json');
  print('Decoded ${graph.size} triples');

  // Re-encode as Turtle — no format-specific code needed
  final turtle = rdfCore.encode(graph, contentType: 'text/turtle');
  print('\nAs Turtle:\n$turtle');

  // Auto-detection also works when content type is unknown
  final autoDetected = rdfCore.decode(input);
  print('\nAuto-detected ${autoDetected.size} triples');
}
