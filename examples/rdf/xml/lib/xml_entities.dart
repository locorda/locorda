// XML Entities support in RDF/XML
import 'package:locorda_rdf_xml/xml.dart';

void main() {
  // RDF/XML with DOCTYPE entity declarations
  final xmlWithEntities = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE rdf:RDF [
    <!ENTITY xsd "http://www.w3.org/2001/XMLSchema#" >
    <!ENTITY lcc-cr "https://www.omg.org/spec/LCC/Countries/CountryRepresentation/" >
    <!ENTITY owl "http://www.w3.org/2002/07/owl#" >
    <!ENTITY rdfs "http://www.w3.org/2000/01/rdf-schema#" >
    <!ENTITY skos "http://www.w3.org/2004/02/skos/core#" >
]>
<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
         xmlns:owl="&owl;"
         xmlns:rdfs="&rdfs;"
         xmlns:skos="&skos;">
  <owl:ObjectProperty rdf:about="&lcc-cr;classifies">
    <rdfs:label>classifies</rdfs:label>
    <skos:definition rdf:datatype="&xsd;string">arranges in categories according to shared characteristics</skos:definition>
    <rdfs:isDefinedBy rdf:resource="&lcc-cr;" />
  </owl:ObjectProperty>
</rdf:RDF>
  ''';

  print('=== PARSING RDF/XML WITH XML ENTITIES ===\n');

  // Parse the RDF/XML with entities
  final graph = rdfxml.decode(xmlWithEntities);

  print('Parsed ${graph.size} triples:\n');
  for (final triple in graph.triples) {
    print('  $triple');
  }

  print('\n=== ENTITY EXPANSION ===');
  print('Entities like &xsd; and &lcc-cr; are automatically expanded');
  print('to their full URIs during parsing.');
  print('\nExample:');
  print('  &xsd;string → http://www.w3.org/2001/XMLSchema#string');
  print(
      '  &lcc-cr;classifies → https://www.omg.org/spec/LCC/Countries/CountryRepresentation/classifies');

  print('\n⚠️ Note: XML entities are supported for PARSING only.');
  print('When encoding RDF to XML, full URIs are used (no entity references).');
}
