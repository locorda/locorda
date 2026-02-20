# Documentation TODO

This document tracks the implementation of the Locorda documentation structure.

## Progress Overview

- [x] Initial Starlight integration at `/docs`
- [x] Getting Started guide (minimal example)
- [x] Phase 1: Foundation complete
- [ ] Comprehensive Sync Engine documentation structure
- [ ] RDF Libraries documentation

---

## Sync Engine Documentation Structure

### Core Pages

- [x] `/docs/sync-engine/getting-started.mdx` - Quick start with minimal task app (moved to guides/)
- [x] `/docs/sync-engine/index.mdx` - Hub page with overview and navigation cards

### Guides (Task-oriented)

- [x] `/docs/sync-engine/guides/getting-started.mdx` - Move current getting-started here
- [x] `/docs/sync-engine/guides/repository-pattern.mdx` - State management, transactions, queries
- [ ] `/docs/sync-engine/guides/testing.mdx` - Unit testing, integration testing, mocking
- [ ] `/docs/sync-engine/guides/production-deployment.mdx` - Backend setup, monitoring, scaling

### Core Concepts (Understanding internals)

- [x] `/docs/sync-engine/core-concepts/architecture.mdx` - Detailed architecture, worker thread, storage layers
- [x] `/docs/sync-engine/core-concepts/conflict-resolution.mdx` - HLC, merge contracts, custom resolution strategies
- [x] `/docs/sync-engine/core-concepts/sync-lifecycle.mdx` - Sync states, error handling, retry logic
- [ ] `/docs/sync-engine/core-concepts/data-model.mdx` - RDF foundation, triples, quads, named graphs

**Priority:** Conflict resolution should be comprehensive - current "Understanding Conflicts" section is too shallow for production use. ✅ DONE

### Data Modeling (Designing your data structures)

- [ ] `/docs/sync-engine/data-modeling/root-resources.mdx` - `@RootResource` deep dive, IRI generation
- [ ] `/docs/sync-engine/data-modeling/sub-resources.mdx` - `@SubResource`, composition, relationships
- [ ] `/docs/sync-engine/data-modeling/local-resources.mdx` - `@LocalResource`, device-specific data, non-synced
- [x] `/docs/sync-engine/data-modeling/merge-contracts.mdx` - How RootResource, SubResource, LocalResource, and merge contracts interact
- [ ] `/docs/sync-engine/data-modeling/annotations-reference.mdx` - Complete reference of all annotations

**Priority:** `merge-contracts.mdx` is foundational - should be created early as it explains the relationship between all resource types. ✅ DONE

### Vocabularies

- [ ] `/docs/sync-engine/vocabularies/generated-vocabularies.mdx` - How auto-generation works from `@AppVocab`
- [ ] `/docs/sync-engine/vocabularies/external-vocabularies.mdx` - Using schema.org, FOAF, Dublin Core, etc.
- [ ] `/docs/sync-engine/vocabularies/custom-vocabularies.mdx` - Manually defining vocabularies
- [ ] `/docs/sync-engine/vocabularies/vocabulary-evolution.mdx` - Versioning, migration, backwards compatibility

### Advanced Features

- [ ] `/docs/sync-engine/advanced-features/indexing.mdx` - Index items, group indices, data in index items
- [ ] `/docs/sync-engine/advanced-features/lazy-loading.mdx` - Lazy fetching, pagination, performance optimization
- [ ] `/docs/sync-engine/advanced-features/selective-sync.mdx` - Partial sync, filters, subscriptions
- [ ] `/docs/sync-engine/advanced-features/multi-user-collaboration.mdx` - Permissions, sharing, access control

**Source:** Topics demonstrated in `personal_notes_app` example (index items, lazy fetching, group indices, data in index items).

### Storage Backends

- [ ] `/docs/sync-engine/storage-backends/overview.mdx` - Comparison matrix, when to use which backend
- [ ] `/docs/sync-engine/storage-backends/solid-pods.mdx` - Setup, authentication, WebID, permissions
- [ ] `/docs/sync-engine/storage-backends/google-drive.mdx` - Setup, OAuth, quotas, limitations
- [ ] `/docs/sync-engine/storage-backends/local-directory.mdx` - Development/testing use cases
- [ ] `/docs/sync-engine/storage-backends/custom-backend.mdx` - Implementing your own storage backend

**Note:** Emphasize supporting multiple backends so users can choose.

### Examples (Complete walkthroughs)

- [ ] `/docs/sync-engine/examples/minimal-task-app.mdx` - Links to current getting-started, kept simple
- [ ] `/docs/sync-engine/examples/personal-notes.mdx` - Based on `personal_notes_app` showing advanced features
- [ ] `/docs/sync-engine/examples/multi-user-chat.mdx` - Future example for collaborative features

**Source Repositories:**
- Minimal: `sync-engine/packages/locorda/example/minimal`
- Personal Notes: `sync-engine/packages/locorda/example/personal_notes_app`

### Reference

- [ ] `/docs/sync-engine/reference/api-overview.mdx` - Key classes (SyncEngine, Repository, etc.) and their roles
- [ ] `/docs/sync-engine/reference/generated-code.mdx` - What `build_runner` generates and why
- [ ] `/docs/sync-engine/reference/configuration.mdx` - All configuration options
- [ ] `/docs/sync-engine/reference/troubleshooting.mdx` - Common issues, debugging techniques, error messages

---

## RDF Libraries Documentation

### Structure (To be defined)

- [x] `/docs/rdf/index.mdx` - Placeholder with package links

**Future sections needed:**
- Getting started guides for each package
- SPARQL tutorial
- Object-RDF mapping guide
- Custom vocabulary creation
- Performance optimization

**Reference examples:** Content from `examples/rdf/` directory in this repo.

---

## Implementation Phases

### Phase 1: Foundation ✅ COMPLETE
1. ✅ Create Sync Engine hub page (`sync-engine/index.mdx`)
2. ✅ Reorganize getting-started into `guides/` subdirectory
3. ✅ Create `guides/repository-pattern.mdx` (task-oriented guide)
4. ✅ Create `data-modeling/merge-contracts.mdx` (foundational concept)
5. ✅ Create `core-concepts/conflict-resolution.mdx` (expand beyond current shallow coverage)
6. ✅ Create `core-concepts/architecture.mdx` (components, layers, worker thread)
7. ✅ Create `core-concepts/sync-lifecycle.mdx` (sync flow, offline mode, error handling)
8. ✅ Update Starlight sidebar configuration

### Phase 2: Core Documentation
1. Complete remaining Core Concepts pages (data-model.mdx)
2. Complete all Data Modeling pages
3. Create Vocabularies section (generated + external)
4. Storage Backends overview and Solid Pods guide

### Phase 3: Advanced & Examples
1. Advanced Features section (indexing, lazy loading)
2. Personal Notes example walkthrough
3. Repository pattern deep dive
4. Complete storage backends coverage

### Phase 4: Reference & Polish
1. API reference pages
2. Testing guide
3. Production deployment guide
4. Troubleshooting guide

---

## Sidebar Configuration

✅ **Updated** - `astro.config.mjs` sidebar now reflects new structure with collapsible groups:

- Overview section with Introduction
- Sync Engine with nested sections:
  - Overview (hub page)
  - Guides (Getting Started)
  - Core Concepts (Conflict Resolution)
  - Data Modeling (Merge Contracts)
- RDF Libraries section

**Next**: Add pages to sidebar as they're created in subsequent phases.

---

## Key Principles

- **Keep getting-started focused:** It should remain a simple, fast introduction using the minimal example
- **Separate concepts from tasks:** Core Concepts (understanding) vs. Guides (doing)
- **Progressive disclosure:** Basic → Intermediate → Advanced
- **Link to source code:** Every example should link to working code in GitHub
- **Consider the audience:** Expert developers, so use technical terms, focus on "why" not basic "what"

---

## Notes

- Personal notes app demonstrates: SubResource, LocalResource, index items, lazy fetching, group indices, data in index items
- Merge contracts are central to understanding how RootResource/SubResource/LocalResource work together
- Conflict resolution needs much deeper coverage than current "Understanding Conflicts" section
- External vocabularies enable interoperability - important use case to document well

---
## "Mut zur Lücke" - TBD

### sync-lifecycle.mdx
- [ ] Batching
- [ ] Testing Sync Behavior
- [ ] Testing Offline Mode
- [ ] Testing Conflict Resolution
- [ ] Performance Considerations