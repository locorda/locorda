// Quick start example for RDF/XML parsing and serialization
import 'package:locorda_rdf_xml/xml.dart';

void main() {
  // Example RDF/XML document
  final xmlContent = '''
    <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
             xmlns:dc="http://purl.org/dc/elements/1.1/">
      <rdf:Description rdf:about="http://example.org/book">
        <dc:title>The Semantic Web</dc:title>
        <dc:creator>Tim Berners-Lee</dc:creator>
      </rdf:Description>
    </rdf:RDF>
  ''';

  // Decode RDF/XML to a graph
  final graph = rdfxml.decode(xmlContent);

  print('Parsed ${graph.size} triples:');
  for (final triple in graph.triples) {
    print('  $triple');
  }

  // Encode the graph back to RDF/XML
  final encoded = rdfxml.encode(graph);
  print('\nEncoded RDF/XML:\n$encoded');
}
