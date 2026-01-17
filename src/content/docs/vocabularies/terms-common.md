---
title: RDF Terms Common
description: Shared utilities for RDF vocabulary packages
---

Shared infrastructure for the RDF Terms vocabulary ecosystem.

## Features

- Namespace management utilities
- Shared base types for vocabulary terms
- URI manipulation helpers
- Common RDF constants

## Installation

This package is typically a transitive dependency.

```yaml
dependencies:
  locorda_rdf_terms_common: ^0.1.0
```

## Usage

Most users won't need this directly. For package authors creating custom vocabularies:

```dart
import 'package:locorda_rdf_terms_common/locorda_rdf_terms_common.dart';

class MyVocabulary extends VocabularyBase {
  static const namespace = 'http://example.org/vocab#';
  static final term = IRI('${namespace}term');
}
```

## Resources

- [GitHub Repository](https://github.com/locorda/rdf-vocabularies)
