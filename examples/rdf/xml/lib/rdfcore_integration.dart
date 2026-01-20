// Integration with RdfCore for multi-format support
import 'package:locorda_rdf_core/core.dart';
import 'package:locorda_rdf_xml/xml.dart';

void main() {
  // Register RDF/XML codec with RdfCore
  final rdfCore = RdfCore.withStandardCodecs(
    additionalCodecs: [RdfXmlCodec()],
  );

  final xmlContent = '''
    <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
             xmlns:foaf="http://xmlns.com/foaf/0.1/">
      <foaf:Person rdf:about="http://example.org/alice">
        <foaf:name>Alice</foaf:name>
        <foaf:knows>
          <foaf:Person>
            <foaf:name>Bob</foaf:name>
          </foaf:Person>
        </foaf:knows>
      </foaf:Person>
    </rdf:RDF>
  ''';

  // Decode from RDF/XML
  final graph = rdfCore.decode(
    xmlContent,
    contentType: 'application/rdf+xml',
  );

  print('Decoded ${graph.size} triples');

  // Convert to Turtle format
  final turtle = rdfCore.encode(graph, contentType: 'text/turtle');
  print('\nAs Turtle:\n$turtle');

  // Convert to N-Triples format
  final ntriples = rdfCore.encode(graph, contentType: 'application/n-triples');
  print('\nAs N-Triples:\n$ntriples');
}
