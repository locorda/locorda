// Integration with RdfCore for content-type-based dispatch
import 'package:locorda_rdf_core/core.dart';
import 'package:locorda_rdf_jelly/jelly.dart';

void main() {
  // Register Jelly alongside the built-in text codecs
  final rdfCore = RdfCore.withStandardCodecs(
    additionalBinaryGraphCodecs: [jellyGraph],
    additionalBinaryDatasetCodecs: [jelly],
  );

  // Suppose we already have a graph (e.g. parsed from Turtle)
  final graph = RdfGraph(triples: [
    Triple(
      IriTerm('http://example.org/s'),
      IriTerm('http://example.org/p'),
      LiteralTerm.string('hello'),
    ),
  ]);

  // Encode to Jelly via content-type dispatch
  final bytes = rdfCore.encodeBinary(graph, contentType: jellyMimeType);
  print('Jelly bytes: ${bytes.length}');

  // Decode back — codec selection is automatic
  final decoded = rdfCore.decodeBinary(bytes, contentType: jellyMimeType);
  print('Decoded ${decoded.size} triples');
}
