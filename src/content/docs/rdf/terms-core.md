---
title: RDF Terms Core
description: Core RDF term representations
---

Core library providing fundamental RDF term representations.

## Features

- Term types: IRI, Literal, BlankNode
- Term operations: Comparison, hashing, equality
- Namespace management
- XSD datatypes support
- RFC 5646 language tags

## Installation

```yaml
dependencies:
  locorda_rdf_terms_core: ^0.1.0
```

## Quick Example

```dart
import 'package:locorda_rdf_terms_core/locorda_rdf_terms_core.dart';

void main() {
  // IRIs
  final iri = IRI('http://example.org/resource');
  
  // Literals with datatypes
  final intLiteral = Literal('42', datatype: XSD.integer);
  
  // Literals with language tags
  final enLiteral = Literal('Hello', language: 'en');
  
  // Blank nodes
  final blank = BlankNode('b1');
}
```

## Resources

- [GitHub Repository](https://github.com/locorda/rdf)
