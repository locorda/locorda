# List-Based Merge Contracts (sync:isGovernedBy)

**Status**: Implemented
**Context**: Extending merge contract system to support layered, extensible contract composition

## Problem

The current `sync:isGovernedBy` property uses a single URI to reference a merge contract, which creates limitations:

1. **No extensibility**: Cannot add new predicate mappings without creating entirely new contract files
2. **Version conflicts**: Different apps using different versions of the same base contract cannot interoperate
3. **Layering challenges**: Cannot compose core framework contracts with domain-specific and app-specific rules
4. **Evolution friction**: Contract updates require coordination across all consuming applications

Example of current limitation:
```turtle
# Recipe v1 - works fine
<#recipe> sync:isGovernedBy mappings:recipe-v1 .

# Recipe v2 - breaks compatibility with v1 installations
<#recipe> sync:isGovernedBy mappings:recipe-v2 .
```

## Proposed Solution: rdf:List-Based Contracts

Change `sync:isGovernedBy` from single URI to `rdf:List` of contract URIs, enabling layered composition.

### Key Design Decisions

1. **List-based governance**: `sync:isGovernedBy ( contract1 contract2 contract3 )`
2. **"First wins" merge semantics**: Earlier contracts in the list take precedence
3. **Append-only evolution**: New contracts should only append, never prepend
4. **OR_Set CRDT algorithm**: Supports append-only list semantics naturally

### Example Usage

```turtle
# Base recipe with core framework contracts
<#recipe> sync:isGovernedBy ( mappings:core-v1 mappings:recipe-v1 ) .

# Extended recipe with additional app-specific mappings (backwards compatible)
<#recipe> sync:isGovernedBy ( mappings:core-v1 mappings:recipe-v1 mappings:meal-planner-v1 ) .
```

### Precedence Rules

When resolving merge rules for a property, the system checks contracts in list order:
1. Local contract-specific rules (first contract with matching rule wins)
2. Predicate mappings within contracts (first contract with matching predicate)
3. Imported contract rules (following same precedence within imports)

## Implementation Changes

### 1. Vocabulary Update
```turtle
sync:isGovernedBy a rdf:Property;
    rdfs:comment "Links a data or index resource to an ordered list (rdf:List) of public mapping files that define its merge behavior. Documents are merged in list order with 'first wins' semantics - implementations should append only, not prepend, to avoid overriding existing definitions.";
    rdfs:range rdf:List . # Changed from rdfs:Resource
```

### 2. CRDT Mapping Update
```turtle
# In core-v1.ttl
[ mc:predicate sync:isGovernedBy; algo:mergeWith algo:OR_Set ], # Changed from algo:Immutable
```

### 3. Template Syntax Update
```turtle
# Old: sync:isGovernedBy mappings:client-installation-v1;
# New: sync:isGovernedBy ( mappings:client-installation-v1 );
```

## Benefits

1. **Additive Evolution**: Apps can add new predicate support without breaking existing installations
2. **Layered Architecture**: Separate concerns (core framework, domain, app-specific)
3. **Backwards Compatibility**: Existing installations with older contract lists remain functional
4. **Interoperability**: Apps using different contract layers can still sync core data
5. **Consistency**: Aligns with existing `mc:imports` pattern in merge contract vocabulary

## Migration Path

Since the project is pre-release, this is implemented as a breaking change:
- All existing `sync:isGovernedBy` references converted to single-item lists
- OR_Set algorithm supports future append operations
- Template files updated to demonstrate new syntax

## Relationship to mc:imports

This change makes `sync:isGovernedBy` conceptually similar to `mc:imports` but at the document level:
- `mc:imports`: Contract-internal composition (within DocumentMapping)
- `sync:isGovernedBy`: Document-level contract selection (which contracts apply)

Both use `rdf:List` with ordered precedence semantics, creating a consistent approach to contract composition throughout the system.