// Quick start: batch encode/decode with the pre-configured global codecs
import 'dart:typed_data';
import 'package:locorda_rdf_core/core.dart';
import 'package:locorda_rdf_jelly/jelly.dart';

void main() {
  // Build a small graph
  final graph = RdfGraph(triples: [
    Triple(
      IriTerm('http://example.org/alice'),
      IriTerm('http://xmlns.com/foaf/0.1/name'),
      LiteralTerm.string('Alice'),
    ),
    Triple(
      IriTerm('http://example.org/alice'),
      IriTerm('http://xmlns.com/foaf/0.1/knows'),
      IriTerm('http://example.org/bob'),
    ),
  ]);

  // Encode to compact binary Jelly format
  final Uint8List bytes = jellyGraph.encode(graph);
  print('Encoded ${bytes.length} bytes (vs ~200 bytes as Turtle)');

  // Decode back
  final decoded = jellyGraph.decode(bytes);
  print('Decoded ${decoded.size} triples');
}
