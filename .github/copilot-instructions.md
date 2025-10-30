# Locorda: AI Coding Agent Instructions

## Project Overview

**Locorda** is a Dart/Flutter library enabling offline-first applications that sync seamlessly to passive storage backends (Solid Pods, Google Drive, etc.) using state-based CRDTs for conflict-free collaboration. This is a **monorepo** using **Melos** for multipackage management.

**⚠️ Critical**: Specification in `spec/` is outdated. Implementation has diverged significantly. **Always prioritize actual code over spec documentation**.

## Architecture: 4-Layer Design

1. **Data Resource Layer**: Clean RDF using standard vocabularies (schema.org)
2. **Merge Contract Layer**: Property-level CRDT rules via `sync:` and `algo:` vocabularies
3. **Indexing Layer**: Performance via sharded indices (`idx:` vocab) - supports FullIndex (monolithic) and GroupIndex (partitioned)
4. **Sync Strategy Layer**: App-controlled sync patterns with ItemFetchPolicy (onRequest/prefetch)

**Key Innovation**: Hybrid Logical Clocks combine causality tracking (logical time) with intuitive tie-breaking (physical timestamps).

## Package Structure

```
packages/
├── locorda           # Main entry point, docs, examples
├── locorda_core      # Platform-agnostic CRDT sync engine (pure Dart)
├── locorda_annotations # CRDT merge strategy annotations  
├── locorda_drift     # Drift (SQLite) storage backend
├── locorda_solid     # Solid Pod integration utilities
├── locorda_solid_auth # Solid authentication (Flutter + solid-auth)
└── locorda_solid_ui  # Flutter UI components (login, sync status)
```

**Dependency Rule**: No circular deps, no re-exports between packages, clean separation.

## Essential Commands

### Setup & Testing
```bash
# Initial setup after clone
dart pub run melos bootstrap

# Run tests with coverage (PREFERRED)
dart tool/run_tests.dart

# All packages test
dart pub run melos test

# Record mode for test expectations (overwrites files)
RECORD_MODE=true dart test  # Review git diff carefully!
```

### Code Quality
```bash
dart pub run melos format    # Always before commits
dart pub run melos analyze   # Static analysis
dart pub run melos lint      # Combined check
```

### Version & Release
```bash
dart pub run melos version   # Update versions + changelog
dart pub run melos publish   # Publish to pub.dev
```

### Database Management (macOS)
```bash
# Clean corrupted Drift databases
rm -f ~/Library/Containers/com.example.personalNotesApp/Data/Documents/*.sqlite*
```

## Development Workflow Rules

### 🚨 CRITICAL: Discussion-First Approach

**Before implementing ANY API/class/package changes:**
1. **Stop and discuss** - Always ask "Should I implement this?" or "What API design do you prefer?"
2. **Start minimal** - Design for actual example app needs, not theoretical requirements
3. **Avoid over-engineering** - No complex schemas/hierarchies without explicit approval
4. **Iterative refinement** - Basic working API first, then add complexity if needed

**Bad**: Creating comprehensive interfaces and schemas when asked to create a storage package  
**Good**: Asking "What storage operations does the example app actually need?" and designing minimal interface

### Code Patterns

**CRDT Types**: LWW-Register (single-value), OR-Set (multi-value, re-addable), 2P-Set (permanent removal), Immutable (strict), G-Register (max wins)

**Repository-Based Hydration** - Main sync pattern:
```dart
// Repository provides callbacks for sync integration
syncSystem.hydrateStreaming<Note>(
  getCurrentCursor: () => repo.getCurrentCursor(),
  onUpdate: (graph, id) => repo.saveFromGraph(graph, id),
  onDelete: (id) => repo.deleteById(id),
  onCursorUpdate: (cursor) => repo.saveCursor(cursor),
);
```

**Save/Delete Operations**:
```dart
syncSystem.save<Note>(note);         // Triggers CRDT merge + sync
syncSystem.deleteDocument<Note>(id); // Framework-level deletion
```

**Deletion Philosophy**:
- **Framework deletion**: For storage optimization and retention policies (use sparingly)
- **Application soft deletion**: Domain-specific (`archived: true`, `hidden: true`) - preferred for user actions
- Both can coexist: soft deletion for UI, framework deletion for backend cleanup

### RDF & Semantic Web Focus

- Fragment identifiers (`it`) distinguish things from documents
- RDF reification for deletion tombstones (semantically correct vs RDF-Star)
- Public merge contracts for cross-app interoperability
- Standard vocabularies: `schema:`, `crdt:`, `algo:`, `sync:`, `idx:`

### Testing Patterns

**Record Mode**: Some tests support `RECORD_MODE=true dart test` to regenerate expected results
- Currently: `sync_engine_test.dart` (graph sync expectations)
- **Always** review `git diff` before committing record mode changes
- Used when test logic or CRDT behavior intentionally changes

**Test Structure**: Comprehensive coverage using JSON test suites (`packages/locorda_core/test/assets/graph/all_tests.json`)

## Key Files & Locations

### Documentation
- `CLAUDE.md` - Development guidelines (this project's primary dev guide)
- `IMPLEMENTATION.md` - Package structure & workflow
- `spec/docs/ARCHITECTURE.md` - Original architectural spec (⚠️ outdated)
- `spec/docs/CRDT-SPECIFICATION.md` - HLC mechanics & algorithms (⚠️ outdated)
- `spec/docs/GROUP-INDEXING.md` - Indexing system patterns

### RDF Vocabularies
- `spec/vocabularies/crdt-algorithms.ttl` - CRDT merge algorithms
- `spec/vocabularies/crdt-mechanics.ttl` - Framework infrastructure (HLC, installations)
- `spec/vocabularies/idx.ttl` - Indexing vocabulary
- `spec/vocabularies/sync.ttl` - Synchronization vocabulary
- `spec/mappings/core-v1.ttl` - Essential CRDT mappings (imported by all apps)

### Core Implementation
- `packages/locorda_core/lib/src/sync_engine.dart` - Main API facade (`SyncEngine`)
- `packages/locorda_core/lib/src/crdt_document_manager.dart` - CRDT merge logic
- `packages/locorda/example/` - Personal notes app (reference implementation)

## Code Quality Standards

- **Clean & minimal** - No legacy/backwards compatibility burden in this early phase
- **Idiomatic Dart** - Follow language conventions, use type system effectively
- **No over-engineering** - Solve actual problems, not theoretical ones
- **Documentation**: DartDoc for APIs + guides/examples for concepts
- **Format before commits**: `melos format`
- **Early dev phase**: Just delete wrong code, don't preserve it

## Scale & Constraints

- **Target**: 2-100 installations (optimal: 2-20) - personal to small team collaboration
- **Single-user storage focus**: CRDT sync within one user's backend (multi-user backend in v2/v3)
- **Passive storage**: All sync logic client-side, backend is simple file storage

## Anti-Patterns to Avoid

❌ Assuming spec documentation matches implementation  
❌ Creating complex abstractions without discussing design first  
❌ Over-engineering for theoretical future requirements  
❌ Generic advice without project-specific context  
❌ Breaking existing functionality with changes  
❌ Committing record mode test output without reviewing diffs

## When in Doubt

1. Check `CLAUDE.md` for development philosophy
2. Look at `packages/locorda/example/` for usage patterns
3. Ask before implementing - discuss API design first
4. Run tests frequently during development
5. Keep it simple - solve real needs, not imagined ones
