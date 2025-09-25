# Framework/App Data Separation Strategy

**Status**: Proposed
**Context**: Implementing clean separation between sync framework metadata and application data in RDF documents

## Problem

The sync framework needs to distinguish between:
- **Framework data**: CRDT metadata, tombstones, sync state, etc.
- **App data**: The actual application data that should be passed to/from apps

This separation is critical for:
1. **Change detection**: Computing diffs between old/new app data only
2. **Clean interfaces**: Apps shouldn't see framework internals
3. **Future compatibility**: New framework versions and different implementations
4. **Global unmapped data**: Unknown triples should flow to apps, not be lost

## Proposed Approach: Mapping-Driven Reachability Traversal

### Core Rule
- **Framework data**: All triples reachable from document level `<>`, with traversal stopped at predicates marked with `mc:stopTraversal` in merge contracts
- **App data**: Everything else, including primary resource and its connected subgraph

### Mapping-Driven Stop Predicates

Stop predicates are defined in merge contract mappings using the `mc:stopTraversal` property:

```turtle
# In core-v1.ttl
<#traversal-boundaries> a mc:PredicateMapping;
   mc:rule
     [ mc:predicate foaf:primaryTopic; mc:stopTraversal true ],
     [ mc:predicate rdf:subject; mc:stopTraversal true ],
     [ mc:predicate rdf:predicate; mc:stopTraversal true ],
     [ mc:predicate rdf:object; mc:stopTraversal true ] .
```

Applications can extend or override these boundaries in their own merge contracts.

### Framework Statement Linking

**Breaking Change**: Framework statements (tombstones, etc.) must now be linked to the document via `sync:hasStatement`

```turtle
<> a sync:ManagedDocument ;
   sync:hasStatement _:tombstone .

_:tombstone a rdf:Statement ;
            rdf:subject <#it> ;
            rdf:predicate schema:text ;
            rdf:object "deleted value" ;
            crdt:deletedAt "2024-01-01"^^xsd:dateTime .
```

This ensures framework metadata is discoverable during document-level traversal while maintaining clean separation from app data.


### Example

```turtle
# Framework data (reachable from <>)
<> a sync:ManagedDocument ;
   crdt:clock "abc123" ;
   sync:hasStatement _:tombstone ;
   foaf:primaryTopic <#it> .  # STOP - mc:stopTraversal in merge contract

_:tombstone a rdf:Statement ;           # Standard RDF reification
            rdf:subject <#it> ;         # STOP - mc:stopTraversal in merge contract
            rdf:predicate schema:text ; # STOP - mc:stopTraversal in merge contract
            rdf:object "deleted value" ;
            crdt:deletedAt "2024-01-01"^^xsd:dateTime .

# App data (not reachable due to mapping-defined stops)
<#it> a schema:Note ;
      schema:text "Hello world" ;
      schema:dateCreated "2024-01-01"^^xsd:dateTime .
```

## Benefits

1. **Domain-specific boundaries**: Applications can define custom traversal boundaries in their merge contracts
2. **Standard compliance**: Uses established semantic web predicates with declarative extension mechanism
3. **Version resilient**: Stop predicates defined in versioned merge contracts, not hardcoded in implementations
4. **Clean app data**: Apps get pure connected subgraphs without framework pollution
5. **Extensible**: Applications can add domain-specific stop predicates without framework changes
6. **Public contracts**: Stop rules are discoverable in merge contracts for interoperability

## Breaking Changes from Current Spec

**Current assumption**: Framework statements (tombstones) exist as unconnected triples in the document
**New requirement**: Framework statements must be linked via `sync:hasStatement` for discoverability

This change is necessary because the separation algorithm needs to discover all framework metadata by traversing from the document root `<>`.

## Implementation Notes

- Framework metadata must be connected to document via `sync:hasStatement`
- Standard RDF reification for property tombstones
- Primary resource traversal remains entirely within app data
- Unknown/future predicates default to app data (globalUnmapped friendly)
- Stop predicates loaded from merge contracts via `sync:isGovernedBy`
- Merge contract hierarchy allows framework defaults with application overrides

## Vocabulary Extensions

### New Property

```turtle
# In merge-contract.ttl
mc:stopTraversal a rdf:Property;
    rdfs:label "stop traversal";
    rdfs:comment "A boolean flag used within mc:Rule to mark a predicate as a boundary for framework/app data separation during graph traversal.";
    rdfs:domain mc:Rule;
    rdfs:range xsd:boolean .
```

This integrates cleanly with the existing merge contract system alongside `mc:isIdentifying` and CRDT algorithm declarations.