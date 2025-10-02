# Proposed Specification Changes: Resource Identity and Clock Structure

## 1. HLC Clock Structure and Hash Computation

### Clock Entry as IRI Resource
- **Change**: `crdt:ClockEntry` MUST be an IRI resource (using fragment identifiers), NOT a blank node
- **Rationale**: Enables stable identification across backends and simplifies CRDT merging

### Clock Entry Fragment Generation
```turtle
# Clock entry uses framework-reserved fragment based on installation localId:
<doc#lcrd-clk-md5-{hash-of-installation-localId}>
  crdt:logicalTime 5 ;
  crdt:physicalTime 1704067200000 ;
  crdt:installationIri <backend-specific-installation-IRI> .
```
- Fragment: `#lcrd-clk-md5-{md5(installation-localId)}`
- Stable across all backends for the same installation

### Renamed Predicate
- **Old**: `crdt:installationId`
- **New**: `crdt:installationIri`
- **Type**: Multi-value property (OR-Set semantics)
- **Timing**: Added during sync, NOT during save
- **Purpose**: References the installation document in backend-specific form

### Clock Hash Computation
```
1. Collect ALL crdt:ClockEntry resources in the document
2. Verify clock entry IRIs are in internal form (tag:locorda.dev,2025:l:...)
3. For each clock entry, extract ONLY these triples:
   - (clockEntryIRI, crdt:logicalTime, value)
   - (clockEntryIRI, crdt:physicalTime, value)
4. Serialize to canonical N-Quads
5. Compute MD5 hash
6. Store as crdt:clockHash on sync:ManagedDocument
```

**Key properties**:
- Clock entry IRIs MUST already be in internal form
- Clock hash includes **only logical and physical time** (NOT installationIri)
- Clock hash is **stable across backends**

### Save vs Sync Timing

**On Save** (local operation):
```dart
1. Advance our clock entry (increment logicalTime, update physicalTime)
2. Compute clockHash from all clock entries (verify internal form, logical+physical only)
3. Store document + clock + clockHash to local DB
4. Track PropertyChange with isLocalChange = true
```

**On Sync** (network operation):
```dart
1. Fetch remote document
2. Translate remote IRIs → internal IRIs
3. Merge clocks (OR-Set union of clock entries)
4. Merge properties using CRDT rules
5. For changed properties due to merge:
   - Find remote clock entry with highest physicalTime among updated entries
   - Track PropertyChange with:
     * changedAtMs = that clock entry's physicalTime
     * changeLogicalClock = that clock entry's logicalTime
     * isLocalChange = false
6. Add backend-specific IRI to our clock entry's installationIri set
7. Recompute clockHash (if remote entries changed)
8. Translate internal IRIs → backend IRIs
9. Upload to backend
10. Save merged state to local DB
```

### PropertyChange for Remote-Caused Changes

When merge causes property changes:
```dart
PropertyChange(
  resourceIri: affectedResource,
  propertyIri: changedProperty,
  changedAtMs: remoteClock.physicalTime,     // Physical time of remote that won
  changeLogicalClock: remoteClock.logicalTime, // Logical time of remote that won
  isLocalChange: false,  // Marks as remote-caused
)
```

**Selection rule**: Among all remote clock entries updated since our version, use the one with **highest physicalTime** as the assumed source of the change.

## 2. Resource Identity

### Internal IRI Scheme

All framework-managed resources use internal IRIs:
```
tag:locorda.dev,2025:l:{namespace-b64}:{typeIri-b64}:{localId-b64}#{fragment}
```

**Components**:
- `namespace`: App-controlled namespace (base64url encoded)
- `typeIri`: RDF type IRI (base64url encoded)
- `localId`: Application-provided identifier (base64url encoded)
- `fragment`: Application-controlled (MUST NOT start with `lcrd-`)

**Framework-reserved fragments**: Fragments starting with `lcrd-` are reserved for framework use (clock entries, identified blank nodes, etc.)

### IRI Translation Rules

**Our IRIs**: Backend-specific IRIs created by this installation
- ✅ Translatable: Internal ↔ Backend (via ResourceLocator)

**Foreign IRIs**: Backend-specific IRIs from other installations/apps
- ❌ NOT translatable: Cannot determine (namespace, type, localId) from arbitrary backend IRIs
- Must be preserved as-is in properties

**Merge semantics**: When different applications create resources with the same remote IRI → treated as the same document and merged according to CRDT rules

### Namespace for Collaboration Control

**Purpose**: Namespace prevents unintentional document collisions between applications/users

**Example**:
```
App A (namespace: com.app-a:user-alice):
  tag:locorda.dev,2025:l:Y29tLmFwcC1hOnVzZXItYWxpY2U=:...:recipe-123

App B (namespace: com.app-b:user-alice):
  tag:locorda.dev,2025:l:Y29tLmFwcC1iOnVzZXItYWxpY2U=:...:recipe-123

→ Different namespaces → Different documents (no collision)
```

**Discovery**: Resources remain discoverable via backend indices (e.g., Solid Type Index) for intentional collaboration

## 3. Optional: App IRI Translation Layer

**Purpose**: Improve developer experience by exposing friendlier IRIs to applications

**Example**:
```dart
// Internal: tag:locorda.dev,2025:l:{ns-b64}:{type-b64}:{id-b64}#it
// App view: https://my.app/alice/recipes/tomato-soup

// LocordaGraphSync handles translation automatically
final recipe = await sync.get<Recipe>("tomato-soup");
// App never sees internal IRIs
```

**Status**: Optional sugar, not core specification requirement

## Open Questions

1. **Namespace encoding**:
   - Option A: Part of localId (current ResourceLocator)
   - Option B: Separate component in IRI scheme
   - **Recommendation**: Separate component for clarity

2. **Namespace control**: When/how does app set namespace?
   - During LocordaGraphSync initialization?
   - Per-resource via API?
   - **Recommendation**: Global default + per-resource override

3. **Namespace contents**: Should include user ID?
   - **Recommendation**: App-controlled, framework provides default pattern

4. **Backend translation optimization**: Create hash for `type+namespace` to optimize reverse lookups?
   - **Recommendation**: Implementation detail, not spec requirement

