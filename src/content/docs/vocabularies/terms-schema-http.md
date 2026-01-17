---
title: RDF Terms Schema HTTP
description: Schema.org vocabulary with HTTP namespace
---

Schema.org vocabulary using the HTTP namespace variant.

## Features

- HTTP namespace (http://schema.org)
- Complete Schema.org vocabulary
- Type-safe constants
- Legacy support

## Installation

```yaml
dependencies:
  locorda_rdf_terms_schema_http: ^0.1.0
```

## When to Use

Use this package when working with:
- Legacy RDF data using HTTP Schema.org IRIs
- Systems that normalize HTTPS to HTTP
- Data predating Schema.org's HTTPS migration

For new projects, prefer [RDF Terms Schema](./terms-schema.md) with HTTPS.

## Quick Example

```dart
import 'package:locorda_rdf_terms_schema_http/locorda_rdf_terms_schema_http.dart';

void main() {
  // HTTP namespace version
  print(SCHEMA.Person);  // http://schema.org/Person
  print(SCHEMA.name);    // http://schema.org/name
}
```

## Resources

- [GitHub Repository](https://github.com/locorda/rdf-vocabularies)
- [Schema.org Website](https://schema.org/)
