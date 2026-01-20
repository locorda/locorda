// Base URI handling for relative URIs in RDF/XML
import 'package:locorda_rdf_core/core.dart';
import 'package:locorda_rdf_xml/xml.dart';

void main() {
  final graph = RdfGraph.fromTriples([
    Triple(
      const IriTerm('http://example.org/docs/document'),
      const IriTerm('http://purl.org/dc/elements/1.1/title'),
      LiteralTerm.string('My Document'),
    ),
    Triple(
      const IriTerm('http://example.org/docs/images/photo.jpg'),
      const IriTerm('http://purl.org/dc/elements/1.1/title'),
      LiteralTerm.string('Photo'),
    ),
  ]);

  final baseUri = 'http://example.org/docs/';

  // Scenario 1: With base URI - URIs are relativized AND xml:base is included
  // Output: xml:base="http://example.org/docs/" rdf:about="document"
  print('=== SCENARIO 1: With baseUri + xml:base declaration (default) ===');
  final withBase = rdfxml.encode(graph, baseUri: baseUri);
  print(withBase);

  // Scenario 2: With base URI but no declaration - URIs are relativized but xml:base is omitted
  // Output: (no xml:base) rdf:about="document"
  // ⚠️ WARNING: Parsing such documents requires providing documentUrl to resolve relative URIs!
  print('\n=== SCENARIO 2: With baseUri but WITHOUT xml:base declaration ===');
  final withoutBase = RdfXmlCodec(
    encoderOptions: RdfXmlEncoderOptions(
      includeBaseDeclaration: false,
    ),
  ).encode(graph, baseUri: baseUri);
  print(withoutBase);

  // Scenario 3: Without base URI - all URIs remain absolute
  // Output: (no xml:base) rdf:about="http://example.org/docs/document"
  print('\n=== SCENARIO 3: WITHOUT baseUri (absolute URIs) ===');
  final withoutBaseUri = rdfxml.encode(graph); // No baseUri parameter
  print(withoutBaseUri);

  // Parsing with base URI
  print('\n=== PARSING: Relative URIs with xml:base ===');
  final xmlWithRelative = '''
    <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
             xmlns:dc="http://purl.org/dc/elements/1.1/"
             xml:base="http://example.org/docs/">
      <rdf:Description rdf:about="document">
        <dc:title>Relative URI Example</dc:title>
      </rdf:Description>
    </rdf:RDF>
  ''';

  final parsed = rdfxml.decode(xmlWithRelative);
  print('Parsed ${parsed.size} triple(s):');
  for (final triple in parsed.triples) {
    print('  $triple');
  }
}
