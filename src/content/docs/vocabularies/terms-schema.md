---
title: RDF Terms Schema
description: Schema.org vocabulary for Dart
---

Pre-generated Dart package providing the complete Schema.org vocabulary.

## Features

- Complete Schema.org types and properties
- Type-safe compile-time constants
- Documentation from Schema.org
- Regular updates with latest Schema.org releases
- HTTPS namespace (https://schema.org)

## Installation

```yaml
dependencies:
  locorda_rdf_terms_schema: ^0.1.0
```

## Quick Example

```dart
import 'package:locorda_rdf_terms_schema/locorda_rdf_terms_schema.dart';

void main() {
  // Schema.org types
  print(SCHEMA.Person);
  print(SCHEMA.Organization);
  print(SCHEMA.Product);
  
  // Schema.org properties
  print(SCHEMA.name);
  print(SCHEMA.description);
  print(SCHEMA.email);
}
```

## Common Types

- `Person` - A person
- `Organization` - An organization
- `Product` - A product
- `Event` - An event
- `Place` - A place or location
- `CreativeWork` - Creative works

## Resources

- [GitHub Repository](https://github.com/locorda/rdf-vocabularies)
- [Schema.org Website](https://schema.org/)
