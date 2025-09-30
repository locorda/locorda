# Canonical IRI Generation for Identified Blank Nodes

**IMPORTANT CHANGE:** objects of identifying predicates **must not** be blank nodes!

## Problem Statement

Identified blank nodes need stable, persistent references that survive RDF serialization/deserialization for:
1. **Property change tracking**: Storing `PropertyChange` records in the database
2. **Resource deletion tombstones**: Recording when an identified blank node resource is deleted
3. **Property value tombstones**: OR-Set deletions of blank node values
4. **Merge operations**: Matching identified blank nodes across local and remote documents

The challenge: `BlankNodeTerm` instances are recreated on each parse, so direct blank node references are unstable across serialization boundaries.

## Solution: Canonical IRI with Persistent Mapping

### Overview

Generate a canonical IRI for each identified blank node using:
1. Deterministic RDF graph construction from identification pattern
2. Optimized canonicalization with stable blank node labels
3. Hash-based IRI generation
4. Persistent mapping storage in framework metadata

### Canonical IRI Generation Algorithm

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

#### Step 4: Hash and Generate IRI

```
hash = MD5(nquads_string)
canonical_iri = "locorda:md5:{hash}"
```

**Example:** `locorda:md5:a3f9e2d1c4b5e6f7a8b9c0d1e2f3a4b5`

**Hash algorithm choice:**
- **MD5**: Fast, 128-bit, sufficient for collision resistance in this domain
- Consistent with existing framework usage (shard naming)
- Alternative: SHA-256 for cryptographic strength (slower, longer IRIs)

### Persistent Mapping Storage

Store canonical IRI ↔ blank node mapping in framework metadata:

```turtle
<doc> a sync:ManagedDocument ;
  # ... other framework metadata ...

  # Blank node mapping
  sync:hasBlankNodeMapping [
    sync:canonicalIri locorda:md5:a3f9e2d1... ;
    sync:blankNode _:ingredient1  # Direct RDF reference
  ] , [
    sync:canonicalIri locorda:md5:f4e2c1a3... ;
    sync:blankNode _:ingredient2
  ] .

# Application data
<doc#it> schema:ingredients _:ingredient1, _:ingredient2 .

_:ingredient1 schema:name "Tomato" ;
              schema:unit "cup" ;
              schema:amount "2" .

_:ingredient2 schema:name "Basil" ;
              schema:unit "bunch" ;
              schema:amount "1" .
```

**RDF parser behavior:** When parsing this document, the parser creates one `BlankNodeTerm` instance per unique blank node label (`_:ingredient1`, `_:ingredient2`), and reuses that instance everywhere the label appears. This allows the framework metadata to successfully reference app data blank nodes.

### Usage in Framework Metadata

#### Property Value Tombstones (OR-Set)

```turtle
<doc> sync:hasStatement [
  rdf:subject <doc#it> ;
  rdf:predicate schema:ingredients ;
  rdf:object locorda:md5:a3f9e2d1... ;  # Canonical IRI instead of blank node
  crdt:deletedAt "2025-01-15T10:30:00Z"^^xsd:dateTime
] .
```

#### Resource Deletion Tombstones

```turtle
<doc> sync:hasStatement [
  rdf:subject locorda:md5:f4e2c1a3... ;  # Deleted identified blank node
  crdt:deletedAt "2025-01-15T10:30:00Z"^^xsd:dateTime
] .
```

#### Property Changes (Database Storage)

```sql
-- PropertyChange table
INSERT INTO property_changes (
  document_iri,
  resource_iri,  -- Can be IRI or canonical IRI for blank nodes
  property_iri,
  changed_at_ms,
  change_logical_clock
) VALUES (
  'https://example.org/recipe-123',
  'locorda:md5:a3f9e2d1...',  -- Identified blank node
  'http://schema.org/amount',
  1705318200000,
  15
);
```

### Vocabulary Extensions

New predicates needed in `sync:` vocabulary:

```turtle
sync:hasBlankNodeMapping a rdf:Property ;
  rdfs:domain sync:ManagedDocument ;
  rdfs:range sync:BlankNodeMapping ;
  rdfs:comment "Links a managed document to blank node canonical IRI mappings." .

sync:BlankNodeMapping a rdfs:Class ;
  rdfs:comment "Represents a mapping between a canonical IRI and a blank node in the document." .

sync:canonicalIri a rdf:Property ;
  rdfs:domain sync:BlankNodeMapping ;
  rdfs:range xsd:anyURI ;
  rdfs:comment "The canonical IRI for an identified blank node." .

sync:blankNode a rdf:Property ;
  rdfs:domain sync:BlankNodeMapping ;
  rdfs:comment "Reference to the actual blank node in the document." .
```

New predicate for identification graphs (internal use only):

```turtle
sync:parent a rdf:Property ;
  rdfs:comment "Internal predicate for linking identified blank nodes to their parent in identification graphs. Not used in application data." .
```

Note: sync:canonicalIri must be marked as identifying in core-v1.ttl mapping document, sync:blankNode will
be removed when the blank node is tombstoned, leaving a blank node with only sync:canonicalIri. Both sync:canonicalIri and sync:blankNode must be marked with stopTraversal in the mapping document

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
# Old: locorda:md5:abc123... (name="Tomato")
# New: locorda:md5:def456... (name="Roma Tomato")
```

**Handling:**
1. Detect canonical IRI mismatch during save
2. Treat as deletion of old + creation of new (semantically correct)
3. Generate deletion tombstone for old canonical IRI
4. Store new mapping for new canonical IRI

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
- ✅ Framework metadata clearly separated via `sync:` namespace
- ✅ Canonical IRIs use custom scheme but are valid IRIs

**Limitation:** `locorda:md5:...` IRIs are not resolvable, but this is acceptable for internal framework references.

## Integration with Existing Architecture

### Document Structure

```turtle
# Framework metadata layer
<doc> a sync:ManagedDocument ;
  sync:managedResourceType schema:Recipe ;
  sync:isGovernedBy ( <mapping-v1.ttl> ) ;
  crdt:hasClockEntry [...] ;
  crdt:clockHash "..." ;

  # Canonical IRI mapping (new)
  sync:hasBlankNodeMapping [ ... ] ;

  # Framework metadata referencing blank nodes via canonical IRIs
  sync:hasStatement [
    rdf:subject locorda:md5:... ;  # Uses canonical IRI
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
1. Compute canonical IRIs for identified blank nodes
2. Use canonical IRIs in all framework metadata
3. Store PropertyChanges with canonical IRIs
4. Store mapping in framework metadata

## Benefits Summary

1. **Stable references**: Canonical IRIs survive serialization/deserialization
2. **Performance**: Persistent mapping eliminates repeated canonicalization
3. **Correctness**: Standards-based RDF approach
4. **Simplicity**: Uniform handling (canonical IRI is just an IRI)
5. **Compatibility**: Works with standard RDF tools
6. **Scalability**: Efficient even with many identified blank nodes

## Future Considerations

### Alternative Hash Algorithms

Current: MD5 (128-bit, fast)
- **SHA-256**: 256-bit, cryptographic strength, slower
- **BLAKE3**: Fast, modern, 256-bit (if needed later)

### IRI Scheme Evolution

Current: `locorda:md5:...`
- Could evolve to resolvable: `https://w3id.org/locorda/ibn/md5/...`
- Documentation at IRI location
- Backward compatibility maintained
