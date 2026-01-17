# RDF Code Examples

This directory contains verified code examples that are embedded in the website.

## Structure

- `01_install.txt` - Installation command
- `02_parse_turtle.dart` - Basic Turtle parsing example
- `03_query_graph.dart` - Querying and manipulating RDF graphs
- `test/` - Automated tests for each example

## Testing Locally

```bash
# From the examples/rdf directory
dart pub get
dart test

# Or from the website root
npm run verify-examples
```

## CI/CD Integration

Examples are automatically tested in GitHub Actions:
1. `verify-examples.sh` runs all Dart tests
2. Website build only proceeds if examples pass
3. This ensures website always shows working code

## Development Workflow

```bash
# 1. Edit example code
vim 02_parse_turtle.dart

# 2. Test it
dart run 02_parse_turtle.dart

# 3. Verify with automated tests
dart test

# 4. Build website (includes verification)
cd ../..
npm run build
```

## Guidelines

- All Dart files must be valid, compilable code
- Use actual locorda_rdf_core APIs (not invented syntax)
- Keep examples concise and focused (< 20 lines)
- Add comments to explain non-obvious parts
- Every example must have a corresponding test
- Update website if example changes

## Embedding in Website

The website reads these files at build time in `src/pages/rdf.astro`:

```typescript
const parseCode = await readFile(join(examplesDir, '02_parse_turtle.dart'), 'utf-8');
```

This ensures the website always shows verified, up-to-date code that actually works.
