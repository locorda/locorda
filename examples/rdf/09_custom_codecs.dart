import 'package:locorda_rdf_core/core.dart';

void main() {
  // Example 1: Using individual codec instances directly
  print('1. Using codec instances directly:');
  final turtleData = '''
    @prefix foaf: <http://xmlns.com/foaf/0.1/> .
    <http://example.org/alice> foaf:name "Alice" .
  ''';

  // Each format has a global codec instance
  final graph1 = turtle.decode(turtleData);
  final asJsonLd = jsonldGraph.encode(graph1);
  print('   Encoded as JSON-LD:\n$asJsonLd');

  // Example 2: Creating a custom RdfCore instance
  print('\n2. Creating custom RdfCore with specific codecs:');

  // Create RdfCore with only Turtle and N-Triples support
  final customRdf = RdfCore.withCodecs(codecs: [
    TurtleCodec(),
    NTriplesCodec(),
  ]);

  final graph2 = customRdf.decode(turtleData, contentType: 'text/turtle');
  final asNTriples =
      customRdf.encode(graph2, contentType: 'application/n-triples');
  print('   Encoded as N-Triples:\n$asNTriples');

  // Example 3: Customizing codec options
  print('\n3. Using codecs with custom options:');

  // Create a Turtle codec with custom parsing options
  final strictTurtle = TurtleCodec(
    decoderOptions: TurtleDecoderOptions(
      parsingFlags: {
        TurtleParsingFlag.allowDigitInLocalName,
      },
    ),
  );

  final customRdfCore = RdfCore.withCodecs(codecs: [strictTurtle]);

  // Use the custom codec
  final strictData =
      '@prefix ex: <http://example.org/> . ex:resource123 a ex:Type .';
  final graph3 = customRdfCore.decode(strictData, contentType: 'text/turtle');
  print('   Parsed ${graph3.triples.length} triples with custom options');

  // Example 4: Standard codecs (recommended for most use cases)
  print('\n4. Using standard codecs (includes all formats):');
  final standardRdf = RdfCore.withStandardCodecs();

  // Supports Turtle, N-Triples, N-Quads, and JSON-LD out of the box
  final graph4 = standardRdf.decode(turtleData, contentType: 'text/turtle');
  print('   Standard RdfCore decoded ${graph4.triples.length} triples');

  // Can encode to any standard format
  final formats = [
    'text/turtle',
    'application/n-triples',
    'application/ld+json'
  ];
  print('\n   Available standard formats:');
  for (final format in formats) {
    final encoded = standardRdf.encode(graph4, contentType: format);
    print('   - $format: ${encoded.split('\n').length} lines');
  }
}
