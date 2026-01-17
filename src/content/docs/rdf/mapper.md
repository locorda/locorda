---
title: RDF Mapper
description: Object-RDF mapping framework for Dart
---

Object-RDF mapping framework with code generation support.

## Features

- Declarative mapping using annotations
- Automatic code generation via build_runner
- Bidirectional conversion (objects ↔ RDF)
- Type-safe with Dart's type system
- Extensible with custom converters

## Installation

```yaml
dependencies:
  locorda_rdf_mapper: ^0.1.0
  locorda_rdf_mapper_annotations: ^0.1.0

dev_dependencies:
  locorda_rdf_mapper_generator: ^0.1.0
  build_runner: ^2.4.0
```

## Quick Example

```dart
import 'package:locorda_rdf_mapper_annotations/locorda_rdf_mapper_annotations.dart';

@RdfClass(iri: 'http://xmlns.com/foaf/0.1/Person')
class Person {
  @RdfProperty(iri: 'http://xmlns.com/foaf/0.1/name')
  final String name;
  
  Person(this.name);
}
```

Run code generation:
```bash
dart run build_runner build
```

## Resources

- [GitHub Repository](https://github.com/locorda/rdf)
