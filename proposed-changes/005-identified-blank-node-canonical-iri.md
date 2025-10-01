# Canonical IRI Generation for Identified Blank Nodes

## Problem Statement

Identified blank nodes need stable, persistent references that survive RDF serialization/deserialization for:
1. **Property change tracking**: Storing `PropertyChange` records in the database
2. **Resource deletion tombstones**: Recording when an identified blank node resource is deleted
3. **Property value tombstones**: OR-Set deletions of blank node values
4. **Merge operations**: Matching identified blank nodes across local and remote documents

The challenge: `BlankNodeTerm` instances are recreated on each parse, so direct blank node references are unstable across serialization boundaries.

## Solution: Fragment Identifier with Persistent Mapping

### Overview

Generate a canonical fragment identifier for each identified blank node using:
1. Deterministic RDF graph construction from identification pattern
2. Optimized canonicalization with stable blank node labels
3. Hash-based fragment generation
4. Persistent mapping storage using fragment identifiers in the document

### Canonical Fragment Generation Algorithm

#### Step 1: Build Identification Graph

Construct a minimal RDF graph containing only the identification information:

```turtle
# Example: Ingredient identified by (parent=<recipe#it>, name="Tomato", unit="cup")

_:root <sync:parent> <recipe#it> .
_:root schema:name "Tomato" .
_:root schema:unit "cup" .
```

For nested identified blank nodes:
```turtle
# Clock entry: (parent=<doc>, installationId=<install-123>)
# Nested clock value: (parent=clockEntry, type="physical", value=123456)

_:root <sync:parent> <doc> .
_:root crdt:installationId <install-123> .

_:child <sync:parent> _:root .
_:child crdt:type "physical" .
_:child crdt:value "123456" .
```

**Key properties:**
- Only identifying properties included (not all properties)
- Parent relationships explicit via `sync:parent` predicate
- Recursive nesting handled naturally

#### Step 2: Assign Deterministic Blank Node Labels

Instead of arbitrary labels, assign stable labels based on position in parent chain:

```turtle
# Target identified blank node (leaf)
_:ibn0 <sync:parent> _:ibn1 .
_:ibn0 schema:name "Tomato" .
_:ibn0 schema:unit "cup" .

# Parent of target (also an identified blank node)
_:ibn1 <sync:parent> <recipe#it> .
_:ibn1 schema:category "ingredient" .
```

**Algorithm:**
1. Start with the target identified blank node
2. Assign label _:ibn0 to the target
3. Recursively process parent chain, assigning _:ibn1, _:ibn2, etc.
4. Labels are assigned in leaf-to-root order along the parent chain
5. Ensures deterministic labels for identical identification patterns

**Optimization benefit:** Skip expensive RDF canonicalization algorithm since labels are already deterministic.

#### Step 3: Serialize to N-Quads

```nquads
_:ibn0 <sync:parent> <recipe#it> .
_:ibn0 <http://schema.org/name> "Tomato" .
_:ibn0 <http://schema.org/unit> "cup" .
```

**Key points:**
- Sorted triple order (subject, predicate, object lexicographic)
- Full IRI expansion (no prefixes)
- Deterministic serialization - use canonical nquads serialization as specified in RDF Canonicalization

#### Step 4: Hash and Generate Fragment Identifier

```
hash = MD5(nquads_string)
fragment_id = "#lcrd-ibn-md5-{hash}"
```

**Example:** `<doc#lcrd-ibn-md5-a3f9e2d1c4b5e6f7a8b9c0d1e2f3a4b5>`

**Namespace reservation:** The `#lcrd-` prefix (derived from "locorda") is reserved for framework use. Application data must not use fragments starting with `#lcrd-`.

**Fragment format:** The fragment explicitly includes the hash algorithm identifier (`md5`) to make documents self-describing and support future algorithm evolution without format ambiguity.

**Hash algorithm choice:**
- **MD5**: Fast, 128-bit, sufficient for collision resistance in this domain
- Consistent with existing framework usage (shard naming)
- Alternative algorithms (SHA-256) are not currently used but could be added in future versions (see FUTURE-TOPICS.md)

### Persistent Mapping Storage

Store fragment ↔ blank node mapping using framework-reserved fragments:

```turtle
<doc> a sync:ManagedDocument ;
  # ... other framework metadata ...
  sync:hasBlankNodeMapping <doc#lcrd-ibn-md5-a3f9e2d1c4b5e6f7> ,
                            <doc#lcrd-ibn-md5-f4e2c1a39b8d7c6a> .

# Blank node mappings using framework-reserved fragments
<doc#lcrd-ibn-md5-a3f9e2d1c4b5e6f7> sync:blankNode _:ingredient1 .
<doc#lcrd-ibn-md5-f4e2c1a39b8d7c6a> sync:blankNode _:ingredient2 .

# Application data
<doc#it> schema:ingredients _:ingredient1, _:ingredient2 .

_:ingredient1 schema:name "Tomato" ;
              schema:unit "cup" ;
              schema:amount "2" .

_:ingredient2 schema:name "Basil" ;
              schema:unit "bunch" ;
              schema:amount "1" .
```

**Key benefits:**
- Fragment identifiers are standard IRIs - standard CRDT merge handling applies
- No nested blank node structures requiring special merge logic
- Clear namespace separation between framework (`#lcrd-*`) and application data
- RDF parser behavior unchanged: one `BlankNodeTerm` per label, reused throughout document

### Usage in Framework Metadata

#### Property Value Tombstones (OR-Set)

```turtle
<doc> sync:hasStatement [
  rdf:subject <doc#it> ;
  rdf:predicate schema:ingredients ;
  rdf:object <doc#lcrd-ibn-md5-a3f9e2d1c4b5e6f7> ;  # Fragment identifier instead of blank node
  crdt:deletedAt "2025-01-15T10:30:00Z"^^xsd:dateTime
] .
```

#### Property Changes (Database Storage)

```sql
-- PropertyChange table
INSERT INTO property_changes (
  document_iri,
  resource_iri,  -- Can be IRI or fragment identifier for blank nodes
  property_iri,
  changed_at_ms,
  change_logical_clock
) VALUES (
  'https://example.org/recipe-123',
  'https://example.org/recipe-123#lcrd-ibn-md5-a3f9e2d1c4b5e6f7',  -- Fragment identifier
  'http://schema.org/amount',
  1705318200000,
  15
);
```

**Note:** Deletion handling is left open for implementation decisions.

### Vocabulary Extensions

New class and predicates needed in `sync:` vocabulary (in `sync.ttl`):

```turtle
sync:BlankNodeMapping a rdfs:Class;
  rdfs:label "Blank Node Mapping";
  rdfs:comment "Represents a mapping between a canonical IRI and a blank node in the document. Used for stable references to identified blank nodes across serialization boundaries." .

sync:hasBlankNodeMapping a rdf:Property ;
  rdfs:domain sync:ManagedDocument ;
  rdfs:range sync:BlankNodeMapping ;
  rdfs:comment "Links the managed document to framework-reserved fragment identifiers for identified blank nodes." .

sync:blankNode a rdf:Property ;
  rdfs:domain sync:BlankNodeMapping ;
  rdfs:comment "Links a framework-reserved fragment identifier to the actual blank node in the document." .

sync:parent a rdf:Property ;
  rdfs:comment "Internal predicate for linking identified blank nodes to their parent in identification graphs. Not used in application data." .
```

**Merge contract mappings** needed in `core-v1.ttl`:

```turtle
# Add to mc:classMapping list in the DocumentMapping:
<#blank-node-mapping>

# New ClassMapping for BlankNodeMapping:
<#blank-node-mapping> a mc:ClassMapping;
  mc:appliesToClass sync:BlankNodeMapping;
  mc:rule
    [ mc:predicate sync:blankNode; algo:mergeWith algo:LWW_Register; mc:stopTraversal true ] .

# Add to <#managed-document> ClassMapping rules:
[ mc:predicate sync:hasBlankNodeMapping; algo:mergeWith algo:OR_Set ]

```

## Performance Characteristics

### With Persistent Mapping

**Loading existing document:**
- Parse RDF: O(triples)
- Extract mapping: O(identified_blank_nodes)
- **No canonicalization needed**

**Saving new/modified data:**
- Compute IdentifiedBlankNodes: O(blank_nodes × properties)
- Build identification graphs: O(identified_blank_nodes × identifying_properties)
- Assign deterministic labels: O(identified_blank_nodes)
- Serialize to N-Quads: O(identifying_properties)
- Hash: O(nquads_length)
- Store mapping: O(identified_blank_nodes)

**Total computation:** Only for new/changed blank nodes

### Optimization Benefits

1. **No repeated canonicalization**: Stored documents reuse cached mapping
2. **Faster canonicalization**: Deterministic labels skip expensive algorithm
3. **Efficient merge**: Direct lookup via canonical IRI
4. **Minimal overhead**: O(n) mapping storage and extraction

### Example: Document with 50 Identified Blank Nodes

**Without persistent mapping:**
- Every load: 50 × canonicalization_cost (~100ms)

**With persistent mapping:**
- First load: 50 × optimized_canonicalization (~50ms)
- Subsequent loads: mapping extraction (~5ms)
- **Savings: ~95ms per load (95% reduction)**

## Edge Cases and Considerations

### Identification Pattern Changes

If identifying properties change:
```turtle
# Old: <doc#lcrd-ibn-md5-abc123...> (name="Tomato")
# New: <doc#lcrd-ibn-md5-def456...> (name="Roma Tomato")
```

**Handling:**
1. Detect fragment identifier mismatch during save
2. Treat as deletion of old + creation of new (semantically correct)
3. Handle deletion according to chosen strategy (implementation decision)
4. Store new mapping for new fragment identifier

### Non-Identified Blank Nodes

Blank nodes without identifying properties:
- **Not included** in canonical IRI mapping
- Handled via deep structural equality during property comparison
- Use LWW-Register semantics at property level
- Cannot have property-level CRDT tracking (only document-level)

### Hash Collisions

**Probability:** Extremely low with MD5 (2^-128 for random collisions)

**In practice:** Collision would require two different identified blank nodes with:
- Different parent contexts, OR
- Different identifying property values

...to produce identical identification graphs after canonicalization. This is effectively impossible with meaningful data.

**Mitigation:** If collision concern exists, use SHA-256 (2^-256 collision probability)

### Compatibility with Standard RDF Tools

The approach uses standard RDF:
- ✅ Valid RDF triples
- ✅ Parseable by any RDF parser
- ✅ Framework metadata clearly separated via `sync:` namespace and `#lcrd-` fragment prefix
- ✅ Fragment identifiers are standard IRIs with full CRDT merge support

**Benefits over custom IRI schemes:**
- Standard fragment identifiers avoid custom URI scheme issues
- Clear namespace separation via reserved prefix
- Simplified merge logic - fragments are just IRIs

## Integration with Existing Architecture

### Document Structure

```turtle
# Framework metadata layer
<doc> a sync:ManagedDocument ;
  sync:managedResourceType schema:Recipe ;
  sync:isGovernedBy ( <mapping-v1.ttl> ) ;
  crdt:hasClockEntry [...] ;
  crdt:clockHash "..." ;
  sync:hasBlankNodeMapping <doc#lcrd-ibn-md5-a3f9e2d1c4b5e6f7> ,
                            <doc#lcrd-ibn-md5-f4e2c1a39b8d7c6a> .

# Blank node mappings using framework-reserved fragments
<doc#lcrd-ibn-md5-a3f9e2d1c4b5e6f7> sync:blankNode _:ing1 .
<doc#lcrd-ibn-md5-f4e2c1a39b8d7c6a> sync:blankNode _:ing2 .

# Framework metadata referencing blank nodes via fragment identifiers
<doc> sync:hasStatement [
  rdf:subject <doc#it> ;
  rdf:predicate schema:ingredients ;
  rdf:object <doc#lcrd-ibn-md5-a3f9e2d1c4b5e6f7> ;
  crdt:deletedAt "..."
] .

# Application data layer (unchanged)
<doc#it> a schema:Recipe ;
  schema:name "Tomato Soup" ;
  schema:ingredients _:ing1, _:ing2 .

_:ing1 schema:name "Tomato" ; schema:amount "2" .
_:ing2 schema:name "Basil" ; schema:amount "1" .
```

### CRDT Metadata Generation

When generating CRDT metadata (`_generateCrdtMetadataForChanges`):
1. Compute fragment identifiers for identified blank nodes
2. Use fragment identifiers in all framework metadata
3. Store PropertyChanges with fragment identifiers
4. Store mappings using framework-reserved fragments with `sync:blankNode` predicate

## Benefits Summary

1. **Stable references**: Fragment identifiers survive serialization/deserialization
2. **Performance**: Persistent mapping eliminates repeated canonicalization
3. **Correctness**: Standards-based RDF approach using standard fragment identifiers
4. **Simplicity**: Fragments are standard IRIs - uniform CRDT handling applies
5. **Merge-friendly**: No special handling needed for blank node mapping structures
6. **Clear separation**: `#lcrd-` prefix convention clearly distinguishes framework from app data
7. **Compatibility**: Works with standard RDF tools
8. **Scalability**: Efficient even with many identified blank nodes

## Future Considerations

### Alternative Hash Algorithms

Current: MD5 (128-bit, fast)
- **SHA-256**: 256-bit, cryptographic strength, slower, longer fragment identifiers
- **BLAKE3**: Fast, modern, 256-bit (if needed later)

### Fragment Convention Evolution

Current: `#lcrd-ibn-md5-{hash}`
- Algorithm identifier explicitly included in fragment format
- Future algorithms use same pattern: `#lcrd-ibn-sha256-{hash}`, `#lcrd-ibn-blake3-{hash}`, etc.
- Multiple hash algorithms can coexist: same blank node may have mappings for multiple algorithms
- Cross-version compatibility through algorithm-specific matching (see FUTURE-TOPICS.md)
