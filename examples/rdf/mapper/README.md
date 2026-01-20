# RDF Mapper Examples

Examples demonstrating the locorda_rdf_mapper package.

## Running Examples

```bash
# Install dependencies
dart pub get

# Generate mappers
dart run build_runner build --delete-conflicting-outputs

# Run individual examples
dart run 02_quick_start.dart
dart run 03_collections.dart
dart run 04_lossless.dart
dart run 05_advanced.dart
dart run 06_manual.dart

# Run tests
dart test
```

## Examples

- `02_quick_start.dart` - Basic annotation-driven mapping
- `03_collections.dart` - Lists, Sets, and Maps
- `04_lossless.dart` - Lossless round-trip with @RdfUnmappedTriples
- `05_advanced.dart` - IRI strategies, enums, custom types
- `06_manual.dart` - Manual mapper implementation
