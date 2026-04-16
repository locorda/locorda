// Frame-level streaming — encode and decode a stream of triple batches
import 'dart:async';
import 'package:locorda_rdf_core/core.dart';
import 'package:locorda_rdf_jelly/jelly.dart';

Future<void> main() async {
  // A stream of triple batches (e.g. from a database or file in pages)
  final Stream<Iterable<Triple>> triplePages = Stream.fromIterable([
    [
      Triple(
        IriTerm('http://example.org/s1'),
        IriTerm('http://example.org/p'),
        LiteralTerm.string('first batch'),
      ),
    ],
    [
      Triple(
        IriTerm('http://example.org/s2'),
        IriTerm('http://example.org/p'),
        LiteralTerm.string('second batch'),
      ),
    ],
  ]);

  // Encode — lookup tables are shared across frames for better compression
  final encodedStream = JellyTripleFrameEncoder().bind(triplePages);

  // Collect the encoded frames
  final frames = await encodedStream.toList();
  print('Encoded ${frames.length} Jelly frames');

  // Decode — each frame emits a List<Triple>
  final byteStream = Stream.fromIterable(frames);
  final decoded =
      JellyTripleFrameDecoder().bind(byteStream).expand((frame) => frame);

  final triples = await decoded.toList();
  print('Decoded ${triples.length} triples across all frames');
}
