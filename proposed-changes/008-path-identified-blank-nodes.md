# Path-Identified Blank Nodes

**Status**: Accepted
**Context**: Default identification mechanism for single-valued blank nodes using property paths

## Problem

The current blank node identification mechanism uses `mc:isIdentifying true` to mark properties whose **values** identify blank nodes:

```turtle
# Property-identified: blank node identified by property VALUES
<#ingredient-mapping> a mc:ClassMapping;
  mc:appliesToClass schema:Ingredient;
  mc:rule
    [ mc:predicate schema:name; algo:mergeWith algo:LWW_Register; mc:isIdentifying true ],
    [ mc:predicate schema:unit; algo:mergeWith algo:LWW_Register; mc:isIdentifying true ] .

# Usage: Multiple blank nodes in OR-Set, identified by (name, unit) values
<recipe#it> schema:ingredients _:ing1, _:ing2 .
_:ing1 schema:name "Tomato" ; schema:unit "cup" .
_:ing2 schema:name "Basil" ; schema:unit "bunch" .
```

However, for **single-valued properties** (LWW-Register), the blank node is uniquely identified by the **property path** itself, not by property values:

```turtle
# Current: CategoryDisplaySettings has no natural identifying properties
<category#it> pnotes:displaySettings _:settings .

_:settings pnotes:sortOrder "alphabetical" ;
           pnotes:defaultView "list" .
```

Here, `_:settings` is the **only** blank node at this path. Adding artificial ID properties (UUIDs) would be un-idiomatic for RDF.

**Problem**: Without a stable canonical IRI for path-identified blank nodes, we cannot:
1. Track property-level changes within the blank node
2. Store property-level CRDT metadata
3. Create property-level tombstones

**Current workaround**: Treat as unidentified blank node with atomic LWW replacement (no property-level merging).

## Proposed Solution

Make **path-based identification** the **default behavior** for all blank nodes. This provides property-level CRDT tracking without requiring artificial ID properties.

### Core Concept

**Default behavior**: Blank nodes are automatically identified by their property path:

**Identification Pattern**: `(parent_resource, property_path)`

This complements existing property-based identification:
- **Path-identified** (default): `(parent_resource, property_path)` - automatic for single-valued blank nodes
- **Property-identified**: `(parent_resource, identifying_property_values)` - for OR-Set collections, requires `mc:isIdentifying true`
- **Unidentified** (rare): No identification, atomic replacement - requires explicit `mc:disableBlankNodePathIdentification true`

### Canonical IRI Generation

Uses the same approach as property-identified blank nodes (proposal 005), but with `sync:parentProperty` instead of property values in the identification graph.

#### Step 1: Build Identification Graph

```turtle
# Example: Display settings at <category#it> → pnotes:displaySettings
_:ibn0 <sync:parent> <category#it> .
_:ibn0 <sync:parentProperty> <https://example.org/vocab/personal-notes#displaySettings> .
```

For nested paths:
```turtle
# Inner: display at preferences → pnotes:displaySettings
_:ibn0 <sync:parent> _:ibn1 .
_:ibn0 <sync:parentProperty> <https://example.org/vocab/personal-notes#displaySettings> .

# Outer: preferences at <note#it> → pnotes:preferences
_:ibn1 <sync:parent> <note#it> .
_:ibn1 <sync:parentProperty> <https://example.org/vocab/personal-notes#preferences> .
```

#### Step 2: Generate Canonical IRI

Same algorithm as proposal 005:
1. Assign deterministic blank node labels (`_:ibn0`, `_:ibn1`, etc.)
2. Serialize to canonical N-Quads
3. Hash with MD5: `hash = MD5(nquads_string)`
4. Generate fragment: `#lcrd-ibn-md5-{hash}`

**Result**: `<doc#lcrd-ibn-md5-c8d4f2e1a39b7c6a>`

Uses same fragment format as property-identified blank nodes (both are "identified blank nodes").

### Persistent Mapping Storage

Same infrastructure as proposal 005:

```turtle
<doc> a sync:ManagedDocument ;
  sync:hasBlankNodeMapping <doc#lcrd-ibn-md5-c8d4f2e1a39b7c6a> .

<doc#lcrd-ibn-md5-c8d4f2e1a39b7c6a> sync:blankNode _:settings .

# Application data
<doc#it> pnotes:displaySettings _:settings .

_:settings pnotes:sortOrder "alphabetical" ;
           pnotes:defaultView "list" .
```

### Merge Contract Declaration

**Default Behavior**: Path-identification is **automatic** for blank nodes with **single-value algorithms**:

```turtle
<#category-mapping> a mc:ClassMapping;
  mc:appliesToClass pnotes:NotesCategory;
  mc:rule
    [ mc:predicate pnotes:displaySettings;
      algo:mergeWith algo:LWW_Register ] .  # Path identification happens automatically

<#display-settings-mapping> a mc:ClassMapping;
  mc:appliesToClass pnotes:CategoryDisplaySettings;
  mc:rule
    [ mc:predicate pnotes:sortOrder; algo:mergeWith algo:LWW_Register ],
    [ mc:predicate pnotes:defaultView; algo:mergeWith algo:LWW_Register ],
    [ mc:predicate pnotes:showArchived; algo:mergeWith algo:LWW_Register ] .
```

**Algorithm Compatibility**:
- **Single-value algorithms** (LWW-Register, FWW-Register, Immutable): Path-identification is the **default** for blank nodes
- **Multi-value algorithms** (OR-Set, 2P-Set): Path-identification **not possible**; blank nodes **must** use property-identification (`mc:isIdentifying true`)

**Disabling Path Identification**: Use `mc:disableBlankNodePathIdentification true` to override the default (only valid with single-value algorithms):

```turtle
<#address-mapping> a mc:ClassMapping;
  mc:appliesToClass schema:PostalAddress;
  mc:rule
    [ mc:predicate schema:address;
      algo:mergeWith algo:LWW_Register;
      mc:disableBlankNodePathIdentification true ] .  # Treat as atomic unit
```

**When to disable** (rare cases, only with single-value algorithms):
1. **Atomic replacement desired**: All properties should change together as a unit (e.g., postal address where street/city/zip are conceptually inseparable)

**Important**: For multi-value algorithms (OR-Set, 2P-Set), blank nodes **must** use property-based identification (`mc:isIdentifying true`). Both path-identification and unidentified blank nodes are invalid with multi-value algorithms because:
- Path-identification requires single-value semantics (one blank node at the path)
- Unidentified blank nodes cannot be tombstoned in multi-value sets

### Blank Node Type Comparison

| Type | Identification | Algorithm Support | CRDT Granularity | Declaration |
|------|----------------|-------------------|------------------|-------------|
| **Path-identified** (default) | Property path | Single-value only (LWW, FWW, Immutable) | Property-level tracking | Automatic for single-value algorithms |
| **Property-identified** | Property values | All algorithms (LWW, FWW, Immutable, OR-Set, 2P-Set) | Property-level tracking | `mc:isIdentifying true` (required for OR-Set/2P-Set) |
| **Unidentified** | None | Single-value only (LWW, FWW, Immutable) | Atomic replacement | `mc:disableBlankNodePathIdentification true` (rare, only single-value) |

### Example: Category Display Settings

**Mapping declaration**:
```turtle
<#category-mapping> a mc:ClassMapping;
  mc:appliesToClass pnotes:NotesCategory;
  mc:rule
    [ mc:predicate pnotes:displaySettings;
      algo:mergeWith algo:LWW_Register ] .  # Path identification automatic

<#display-settings-mapping> a mc:ClassMapping;
  mc:appliesToClass pnotes:CategoryDisplaySettings;
  mc:rule
    [ mc:predicate pnotes:sortOrder; algo:mergeWith algo:LWW_Register ],
    [ mc:predicate pnotes:defaultView; algo:mergeWith algo:LWW_Register ],
    [ mc:predicate pnotes:showArchived; algo:mergeWith algo:LWW_Register ] .
```

**Document**:
```turtle
<category#it> pnotes:displaySettings _:settings .

_:settings a pnotes:CategoryDisplaySettings ;
           pnotes:sortOrder "dateModified" ;
           pnotes:defaultView "grid" ;
           pnotes:showArchived true .
```

**Merge scenario**:
- Device A: Changes `sortOrder` to "alphabetical" at HLC=100
- Device B: Changes `defaultView` to "list" at HLC=101
- **Result**: Both changes merge (property-level CRDT), unlike unidentified blank nodes (atomic replacement)

### Vocabulary Extensions

**Reuses from proposal 005**:
- `sync:BlankNodeMapping`, `sync:hasBlankNodeMapping`, `sync:blankNode`, `sync:parent`

**New additions**:

```turtle
# In sync.ttl
sync:parentProperty a rdf:Property ;
  rdfs:comment "The property IRI connecting the parent resource to this path-identified blank node. Used in identification graphs to represent the property path." .

# In merge-contract.ttl
mc:disableBlankNodePathIdentification a rdf:Property;
  rdfs:label "disable blank node path identification";
  rdfs:comment "A boolean flag used within mc:Rule to disable the default path-based identification for blank nodes at this predicate. When true, blank nodes are treated as unidentified (atomic replacement). This flag is rarely needed - property-based identification (mc:isIdentifying) should be preferred when blank nodes need stable identity. Use cases: (1) Atomic replacement desired where all blank node properties should change together as a conceptual unit, (2) Multi-valued blank nodes without identification where atomic LWW replacement is acceptable. Important: This flag only affects path-based identification; property-based identification (mc:isIdentifying true) can and should still be used for collections.";
  rdfs:domain mc:Rule;
  rdfs:range xsd:boolean .
```

### Validation Rules

**Strict validation required**:

1. **Path uniqueness for identified blank nodes**: Only one blank node may exist at a property path (default path-identification behavior)
   - Error on save/merge if multiple (non-property-identified) blank nodes found at a property without `mc:disableBlankNodePathIdentification true` 
   - To allow multiple (non-property-identified) blank nodes: explicitly set `mc:disableBlankNodePathIdentification true` (disables identification, enables atomic LWW replacement)

2. **Algorithm compatibility**: Path-identification (default) works only with single-value supporting algorithms
   - LWW-Register, FWW-Register, Immutable: Support both single-valued IRIs/literals AND single-valued blank nodes. For IRIs ans literals multi-valued are supported by treating them as one set which either "wins" or "loses" on merge, but is never merged together
   - OR-Set, 2P-Set: Support multi-valued IRIs/literals, but blank nodes must be property-identified. Path-Identified is not possible because of multi-value and non-identified blank nodes also are not possible because they cannot be tombstoned

### Edge Cases

**Multiple inbound paths to same blank node**:
```turtle
<doc#it> pnotes:primarySettings _:settings ;
         pnotes:fallbackSettings _:settings .  # Same blank node, two paths!
```

**Handling**: Same as property-identified blank nodes:
- Build identification graph for each inbound path
- Each yields a canonical IRI
- Blank node has multiple canonical IRIs
- During merge, blank nodes with non-empty intersection of canonical IRIs are considered equal
- This is a standard pattern, not an error

**Path changes due to refactoring**: If property IRI changes, new canonical IRI generated → treated as deletion + creation (semantically correct for structure changes).

### Implementation

**Detection algorithm**:
```
for each blank node:
  if blank_node has properties with mc:isIdentifying true:
    → generate property-based canonical IRI (proposal 005)
  else if referenced_by_property has mc:disableBlankNodePathIdentification true:
    → unidentified blank node (no canonical IRI, atomic replacement)
  else:
    → DEFAULT: generate path-based canonical IRI
    validate: only one blank node at this path (error if multiple found)
```

**Performance**: Same as property-identified blank nodes (O(parent_chain_depth), typically 1-3 levels)

### Benefits

1. **Idiomatic RDF**: No artificial UUID properties for single-valued structures
2. **Property-level merging**: Enables fine-grained CRDT tracking within blank nodes
3. **Stable references**: Canonical IRIs survive serialization
4. **Validation**: Framework enforces single-valued constraint
5. **Complementary**: Works alongside property-identified blank nodes for different use cases

### When to Use Each Type

**Path-identified blank node** (default for single-value algorithms):
- **Default behavior** - automatically used with LWW-Register, FWW-Register, Immutable
- Enables property-level tracking and merging
- Example: Display settings, user preferences, configuration objects
- No declaration needed - happens automatically

**Property-identified blank node**:
- **Required** for multi-value algorithms (OR-Set, 2P-Set)
- **Optional** for single-value algorithms when multiple instances exist
- Need individual item identity via property values
- Declared with `mc:isIdentifying true` on identifying properties
- Example: Ingredients (OR-Set), checklist items, comments

**Unidentified blank node** (rare, only single-value algorithms):
- Atomic replacement is **desired** - treating structure as indivisible unit
- Only valid with LWW-Register, FWW-Register, Immutable
- Declared with `mc:disableBlankNodePathIdentification true`
- Example: Postal address where all fields should change together conceptually

**Note**: For OR-Set/2P-Set, property-identification is **mandatory** - both path-identification and unidentified blank nodes are invalid.

## Migration Path

**Automatic upgrade**: Path-identification is now the default behavior.

Existing blank nodes automatically become path-identified unless:
1. They have `mc:isIdentifying true` properties (already property-identified)
2. They have `mc:disableBlankNodePathIdentification true` (explicit opt-out)

**No migration steps required**: Framework automatically generates path-based canonical IRIs on next save for all single-valued blank nodes.

## Open Questions

1. **Error handling for violations**: Strict rejection or graceful degradation when multiple blank nodes found at path-identified property (default behavior)?
   - **Proposed**: Strict rejection during save/merge - this is a data modeling error that should be caught early

2. **Blank node deletion**: How to represent deletion of path-identified blank node?
   - Like all deleted resources, this will lead to a resource deletion tombstone
   - Removal of single value is actually a separate topic that we did not clarify yet and which is connected to the crdt algorithm implementation. A tombstone for the property value is one option, but this needs to be thoroughly checked. Anyways, an identified blank node will behave like an IRI or a Literal in that context, so no special logic needed in this proposal.

3. **Compatibility with annotations**: Path-identification is now automatic. Should code generator provide warnings or validation?
   - **Proposed**: Warn if blank node class has no identifying properties AND is used in multi-valued context (likely modeling error)
   - Suggest either adding `mc:isIdentifying` properties or using `mc:disableBlankNodePathIdentification true`
