# Locorda Website

Official website for the Locorda project - RDF libraries and tools for Dart and Flutter.

🌐 **Live:** [locorda.dev](https://locorda.dev)

## Tech Stack

- **Astro 5.17** - Static site generator
- **Starlight 0.37** - Documentation framework (for `/docs` section)
- **Custom Pages** - Marketing pages with gradient design

## Project Structure

```
locorda/
├── examples/
│   └── rdf/                    # Verified code examples
│       ├── 01_install.txt      # Installation command
│       ├── 02_parse_turtle.dart # Dart example
│       ├── 03_query_graph.dart # Dart example
│       └── test/               # Automated tests
├── src/
│   ├── components/             # Header, Footer, etc.
│   ├── content/
│   │   └── docs/
│   │       └── docs/          # Documentation (served at /docs)
│   │           ├── index.mdx  # Docs homepage (/docs/)
│   │           ├── sync-engine/ # Sync Engine docs
│   │           └── rdf/       # RDF libraries docs
│   ├── layouts/                # BaseLayout for pages
│   ├── pages/
│   │   ├── index.astro         # Homepage
│   │   ├── rdf.astro           # RDF marketing page
│   │   ├── impressum.astro     # Legal (German)
│   │   └── privacy.astro       # Privacy policy
├── public/logos/               # SVG logos
└── verify-examples.sh          # Test script
```

## Development

```bash
# Use Node.js 22.9.0 (via nvm)
nvm use

# Install dependencies
npm install

# Start dev server
npm run dev

# Verify code examples
npm run verify-examples

# Build (includes example verification)
npm run build

# Build without verification
npm run build:no-verify

# Preview production build
npm run preview
```

## Code Examples

**CRITICAL:** All code on the website must come from verified files in `examples/`.

### Adding New Examples

1. Create Dart file in `examples/rdf/`
2. Add test in `examples/rdf/test/`
3. Verify: `cd examples/rdf && dart test`
4. Update `src/pages/rdf.astro` to read the file
5. Test build: `npm run build`

### Testing Workflow

```bash
# Test examples locally
cd examples/rdf
dart pub get
dart test

# Or from root
npm run verify-examples
```

## CI/CD

GitHub Actions automatically:
1. Runs `dart test` on all examples
2. Only builds website if examples pass
3. Deploys to GitHub Pages

See [.github/workflows/verify-build.yml](../.github/workflows/verify-build.yml)

## Content Guidelines

- Code examples must be sourced from `examples/` (never invent syntax)
- Use actual locorda_rdf_core APIs
- RdfGraph is immutable - use `withTriple()` or `withTriples()`, not `add()`
- Query with `findTriples()` (returns triples) or `matching()` (returns graph)
- Always check [locorda_rdf_core README](../rdf/packages/locorda_rdf_core/README.md) for API details
- Test before committing

See [.github/copilot-instructions.md](../.github/copilot-instructions.md) for detailed guidelines.

## Architecture

- **Marketing pages** (`/`, `/rdf/`, `/impressum/`, `/privacy/`) - Custom Astro pages with BaseLayout
- **Examples** - Read at build time from `examples/rdf/`
- **Assets** - Logos in `public/logos/`, gradient blobs via CSS

## Legal

- Impressum (German law requirement)
- Privacy Policy (GDPR compliant)
- MIT License

---

Built with ❤️ for the decentralized web.
