// ignore_for_file: unused_local_variable

import 'package:locorda_rdf_core/core.dart';
// import 'package:locorda_rdf_xml/xml.dart';

void main() {
  // Example 1: Customize Turtle parsing for SPARQL-style syntax
  print('1. Custom Turtle codec for SPARQL-style files:');
  final sparqlStyleTurtle = TurtleCodec(
    decoderOptions: TurtleDecoderOptions(
      parsingFlags: {
        TurtleParsingFlag.allowMissingDotAfterPrefix,
        TurtleParsingFlag.allowPrefixWithoutAtSign,
      },
    ),
  );

  final customRdf = RdfCore.withCodecs(codecs: [
    sparqlStyleTurtle,
    NTriplesCodec(),
  ]);

  // Parse SPARQL-style Turtle (no @ before PREFIX, no . after prefix)
  final sparqlData = '''
    PREFIX foaf: <http://xmlns.com/foaf/0.1/>
    <http://example.org/alice> foaf:name "Alice" .
  ''';

  final graph = customRdf.decode(sparqlData, contentType: 'text/turtle');
  print('   Parsed ${graph.triples.length} triples from SPARQL-style syntax\n');

  // Example 2: Add RDF/XML support via extension package
  print('2. Extending with RDF/XML support:');
  final xmlRdf = RdfCore.withCodecs(codecs: [
    TurtleCodec(),
    NTriplesCodec(),
    // RdfXmlCodec(), // from locorda_rdf_xml package
  ]);

  final xmlData = '''
    <?xml version="1.0"?>
    <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
             xmlns:foaf="http://xmlns.com/foaf/0.1/">
      <rdf:Description rdf:about="http://example.org/alice">
        <foaf:name>Alice</foaf:name>
      </rdf:Description>
    </rdf:RDF>
  ''';

  // final xmlGraph = xmlRdf.decode(xmlData, contentType: 'application/rdf+xml');
  // print('   Parsed ${xmlGraph.triples.length} triples from RDF/XML');

  print('   Add locorda_rdf_xml to pubspec.yaml for RDF/XML support');
  print('   Extensible architecture: any codec can be added!');
}
