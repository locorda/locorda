// Configuration options for RDF/XML encoding and decoding
import 'package:locorda_rdf_core/core.dart';
import 'package:locorda_rdf_xml/xml.dart';

void main() {
  final graph = RdfGraph.fromTriples([
    Triple(
      const IriTerm('http://example.org/resource'),
      const IriTerm('http://purl.org/dc/elements/1.1/title'),
      LiteralTerm.string('Example Resource'),
    ),
  ]);

  // Readable output with pretty printing
  print('=== READABLE (pretty-printed) ===');
  final readable = RdfXmlCodec.readable().encode(graph);
  print(readable);

  // Compact output for minimal size
  print('\n=== COMPACT (minimal whitespace) ===');
  final compact = RdfXmlCodec.compact().encode(graph);
  print(compact);

  // Custom configuration
  print('\n=== CUSTOM CONFIGURATION ===');
  final custom = RdfXmlCodec(
    encoderOptions: RdfXmlEncoderOptions(
      prettyPrint: true,
      indentSpaces: 2,
      useTypedNodes: true,
      customPrefixes: {
        'dcelems': 'http://purl.org/dc/elements/1.1/',
        'ex': 'http://example.org/',
      },
    ),
  ).encode(graph);
  print(custom);

  // Strict vs lenient parsing
  print('\n=== PARSING MODES ===');
  print('Strict mode: validates strictly against W3C spec');
  print('Lenient mode: tolerates common RDF/XML variations');
  print('Use RdfXmlCodec.strict() or RdfXmlCodec.lenient() to create codecs');
}
