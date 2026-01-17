---
title: RDF Terms
description: Common RDF vocabularies as Dart packages
---

Collection of pre-generated Dart packages for common RDF vocabularies.

## Features

- Common vocabularies: FOAF, Dublin Core, Schema.org, and more
- Type-safe IRI constants
- Includes documentation from vocabularies
- Zero dependencies
- Tree-shakeable

## Installation

```yaml
dependencies:
  locorda_rdf_terms: ^0.1.0
```

## Available Vocabularies

- **FOAF** - Friend of a Friend
- **Dublin Core** - Metadata terms (DC, DCTERMS)
- **Schema.org** - Schema.org vocabulary
- **RDF** - RDF core vocabulary
- **RDFS** - RDF Schema
- **OWL** - Web Ontology Language
- **SKOS** - Simple Knowledge Organization System

## Quick Example

```dart
import 'package:locorda_rdf_terms/foaf.dart';
import 'package:locorda_rdf_terms/schema.dart';

void main() {
  // FOAF vocabulary
  print(FOAF.Person);  // http://xmlns.com/foaf/0.1/Person
  print(FOAF.name);    // http://xmlns.com/foaf/0.1/name
  
  // Schema.org vocabulary
  print(SCHEMA.Person);     // https://schema.org/Person
  print(SCHEMA.givenName);  // https://schema.org/givenName
}
```

## Resources

- [GitHub Repository](https://github.com/locorda/rdf-vocabularies)
