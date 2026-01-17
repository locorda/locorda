---
title: RDF Core
description: Core RDF library for Dart
---

Core library for working with RDF (Resource Description Framework) data in Dart.

## Features

- RDF data structures: Quad, Triple, IRI, Literal, BlankNode
- Graph operations: Add, remove, query RDF statements
- Serialization support for various RDF formats
- W3C RDF specification compliant

## Installation

```yaml
dependencies:
  locorda_rdf_core: ^0.1.0
```

## Quick Example

```dart
import 'package:locorda_rdf_core/locorda_rdf_core.dart';

void main() {
  final graph = Graph();
  
  graph.add(Triple(
    IRI('http://example.org/person/john'),
    IRI('http://xmlns.com/foaf/0.1/name'),
    Literal('John Doe'),
  ));
}
```

## Resources

- [GitHub Repository](https://github.com/locorda/rdf)
- Package on pub.dev (coming soon)
