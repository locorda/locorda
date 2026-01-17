---
title: RDF XML
description: RDF/XML parser and serializer for Dart
---

Parser and serializer for the RDF/XML format.

## Features

- RDF/XML parsing
- RDF/XML serialization
- W3C RDF/XML specification compliant
- Robust error handling
- Streaming support for large documents

## Installation

```yaml
dependencies:
  locorda_rdf_xml: ^0.1.0
```

## Quick Example

```dart
import 'package:locorda_rdf_xml/locorda_rdf_xml.dart';

void main() {
  const rdfXml = '''
    <?xml version="1.0"?>
    <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
             xmlns:foaf="http://xmlns.com/foaf/0.1/">
      <foaf:Person>
        <foaf:name>John Doe</foaf:name>
      </foaf:Person>
    </rdf:RDF>
  ''';
  
  final dataset = parseRdfXml(rdfXml);
}
```

## Resources

- [GitHub Repository](https://github.com/locorda/rdf)
- [W3C RDF/XML Specification](https://www.w3.org/TR/rdf-syntax-grammar/)
