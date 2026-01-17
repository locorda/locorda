---
title: RDF Terms Generator
description: Code generator for RDF vocabularies
---

Build tool for generating Dart code from RDF vocabularies.

## Features

- Automatic code generation from RDF ontologies
- Type-safe vocabulary terms
- Extract documentation from rdfs:comment
- build_runner integration
- Support for multiple vocabularies

## Installation

```yaml
dev_dependencies:
  locorda_rdf_terms_generator: ^0.1.0
  build_runner: ^2.4.0
```

## Configuration

Create a `build.yaml` file:

```yaml
targets:
  $default:
    builders:
      locorda_rdf_terms_generator:
        options:
          vocabularies:
            - source: https://xmlns.com/foaf/spec/index.rdf
              prefix: foaf
              output: lib/foaf.dart
```

## Usage

Run the generator:

```bash
dart run build_runner build
```

Use the generated vocabulary:

```dart
import 'package:your_package/foaf.dart';

void main() {
  print(FOAF.Person); // http://xmlns.com/foaf/0.1/Person
  print(FOAF.name);   // http://xmlns.com/foaf/0.1/name
}
```

## Resources

- [GitHub Repository](https://github.com/locorda/rdf)
