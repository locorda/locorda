# Path-Identified Blank Nodes

**Status**: Accepted
**Context**: Complementary identification mechanism for single-valued blank node properties

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

Extend the identification mechanism to support **path-based identification** for single-valued properties.

### Core Concept

For blank nodes at **single-valued properties**, use the property path as identification:

**Identification Pattern**: `(parent_resource, property_path)`

This complements existing property-based identification:
- **Property-identified**: `(parent_resource, identifying_property_values)` - for OR-Set collections
- **Path-identified**: `(parent_resource, property_path)` - for LWW-Register single-valued properties

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

Declare path-identification in merge contract using new `mc:isPathIdentifying` flag:

```turtle
<#category-mapping> a mc:ClassMapping;
  mc:appliesToClass pnotes:NotesCategory;
  mc:rule
    [ mc:predicate pnotes:displaySettings;
      algo:mergeWith algo:LWW_Register;
      mc:isPathIdentifying true ] .  # NEW: Declares path-based identification

<#display-settings-mapping> a mc:ClassMapping;
  mc:appliesToClass pnotes:CategoryDisplaySettings;
  mc:rule
    [ mc:predicate pnotes:sortOrder; algo:mergeWith algo:LWW_Register ],
    [ mc:predicate pnotes:defaultView; algo:mergeWith algo:LWW_Register ],
    [ mc:predicate pnotes:showArchived; algo:mergeWith algo:LWW_Register ] .
```

**Constraint**: `mc:isPathIdentifying true` is **only valid** with algorithms that support single-valued semantics (LWW-Register, Immutable, FWW-Register).

### Blank Node Type Comparison

| Type | Identification | Property Cardinality | CRDT Granularity | Declaration |
|------|----------------|---------------------|------------------|-------------|
| **Unidentified** | None | Single or multi-valued (LWW) | Atomic replacement | No special flags |
| **Path-identified** | Property path | Single valued (LWW) | Property-level tracking | `mc:isPathIdentifying true` |
| **Property-identified** | Property values | Single- or Multi-valued (supports also OR-Set in addition to LWW etc) | Property-level tracking | `mc:isIdentifying true` |

### Example: Category Display Settings

**Mapping declaration**:
```turtle
<#category-mapping> a mc:ClassMapping;
  mc:appliesToClass pnotes:NotesCategory;
  mc:rule
    [ mc:predicate pnotes:displaySettings;
      algo:mergeWith algo:LWW_Register;
      mc:isPathIdentifying true ] .

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
mc:isPathIdentifying a rdf:Property;
  rdfs:label "is path identifying";
  rdfs:comment "A boolean flag used within mc:Rule to declare that blank nodes at this predicate are identified by their property path. Only valid for single-valued properties (LWW-Register). When true, the framework generates canonical IRIs based on the property path rather than property values.";
  rdfs:domain mc:Rule;
  rdfs:range xsd:boolean .
```

### Validation Rules

**Strict validation required**:

1. **Single-valued algorithm constraint**: `mc:isPathIdentifying true` is only valid with algorithms that support single-valued semantics
   - Valid: LWW-Register, Immutable, FWW-Register
   - Invalid: OR-Set, 2P-Set (inherently multi-valued)
   - Error if used with multi-valued algorithms

2. **Path uniqueness**: Only one blank node may exist at a path declared with `mc:isPathIdentifying true`
   - Error on save/merge if multiple blank nodes found

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
  if referenced_by_property has mc:isPathIdentifying true:
    validate: property has a single-value compatible algorithm like algo:LWW_Register
    validate: only one blank node at this path
    → generate path-based canonical IRI
  else if blank_node has properties with mc:isIdentifying true:
    → generate property-based canonical IRI (proposal 005)
  else:
    → unidentified blank node (no canonical IRI)
```

**Performance**: Same as property-identified blank nodes (O(parent_chain_depth), typically 1-3 levels)

### Benefits

1. **Idiomatic RDF**: No artificial UUID properties for single-valued structures
2. **Property-level merging**: Enables fine-grained CRDT tracking within blank nodes
3. **Stable references**: Canonical IRIs survive serialization
4. **Validation**: Framework enforces single-valued constraint
5. **Complementary**: Works alongside property-identified blank nodes for different use cases

### When to Use Each Type

**Unidentified blank node**:
- Atomic replacement is **desired** - treating structure as indivisible unit
- Example: Postal address where all fields should change together conceptually
- Multi-valued LWW where property-identification not possible and atomicity is **acceptable** (compromise, not ideal)

**Path-identified blank node** (this proposal):
- Default for structured objects in LWW properties
- Property-level tracking desired
- Example: Display settings, user preferences, configuration objects

**Property-identified blank node** (existing):
- Multiple instances in collections (OR-Set)
- Need individual item identity via property values
- Example: Ingredients, checklist items, comments

**Note**: Unidentified blank nodes should be a rare exception, not the default pattern.

## Migration Path

Existing unidentified blank nodes can be upgraded to path-identified by:
1. Adding merge contract declaration: `mc:isPathIdentifying true`
2. Framework automatically generates path-based canonical IRIs on next save
3. No changes to application data structure required
4. Existing property-level changes become trackable

## Open Questions

1. **Error handling for violations**: Strict rejection or graceful degradation when multiple blank nodes found at path-identified property?
   - **Proposed**: Strict rejection during save/merge - this is a data modeling error

2. **Blank node deletion**: How to represent deletion of path-identified blank node?
   - Like all deleted resources, this will lead to a resource deletion tombstone
   - Removal of single value is actually a separate topic that we did not clarify yet and which is connected to the crdt algorithm implementation. A tombstone for the property value is one option, but this needs to be thoroughly checked. Anyways, an identified blank node will behave like an IRI or a Literal in that context, so no special logic needed in this proposal.

3. **Compatibility with annotations**: Should code generator infer `mc:isPathIdentifying` automatically for single-valued blank node properties?
   - **Proposed**: Yes, if property is LWW-Register and type is blank node class without identifying properties
