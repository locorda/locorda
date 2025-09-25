# Resource Statements for Framework Metadata

**Status**: Proposed
**Context**: Extending framework/app data separation to handle resource-level metadata like resource tombstones

## Problem

The current specification defines:
- **Property tombstones**: For individual property values (using RDF reification)
- **Document tombstones**: For entire documents (using document-level `crdt:deletedAt`)

But we're missing:
- **Resource tombstones**: For entire resources within a document (e.g., when `<#person123>` is deleted but the document remains)

## Challenge: Maintaining Clean Separation

We cannot put framework metadata directly on app resources:

```turtle
# VIOLATES framework/app separation
<#person123> a schema:Person ;
             schema:name "John Doe" ;
             crdt:deletedAt "2024-01-01"^^xsd:dateTime .  # Framework data in app space
```

This would break our clean mental model where:
- Document level = framework concerns
- Primary topic subgraph = app concerns

## Proposed Solution: Resource Statements

Introduce `sync:ResourceStatement` for resource-level framework metadata:

```turtle
<> a sync:ManagedDocument ;
   sync:hasStatement _:resStatement ;
   sync:hasStatement _:propTombstone ;
   foaf:primaryTopic <#addressbook> .

# Resource tombstone - person123 no longer exists
_:resStatement a sync:ResourceStatement ;
               sync:resource <#person123> ;
               crdt:deletedAt "2024-01-01"^^xsd:dateTime .

# Property tombstone - the relationship is also gone
_:propTombstone a rdf:Statement ;
                rdf:subject <#addressbook> ;
                rdf:predicate schema:hasPart ;
                rdf:object <#person123> ;
                crdt:deletedAt "2024-01-01"^^xsd:dateTime .

# App data - clean, no traces of person123
<#addressbook> a schema:Collection ;
               schema:name "My Contacts" ;
               schema:hasPart <#person456> .

<#person456> a schema:Person ;
             schema:name "Jane Doe" ;
             schema:email "jane@example.com" .
```

## Vocabulary Extensions

### New Class
```turtle
sync:ResourceStatement a rdfs:Class ;
    rdfs:label "Resource Statement" ;
    rdfs:comment "A statement containing framework metadata about a specific resource within a managed document. Used for resource-level concerns like deletion tombstones while maintaining clean separation from application data." .
```

### New Property
```turtle
sync:resource a rdf:Property ;
    rdfs:label "resource" ;
    rdfs:comment "Points to the resource that this framework statement is about. Used in resource statements to identify which resource the metadata applies to." ;
    rdfs:domain sync:ResourceStatement ;
    rdfs:range rdfs:Resource .
```

### Required Mapping
```turtle
# In core-v1.ttl
sync:resource ms:identifying true .
```

## Resource Deletion Pattern

Deleting a resource typically requires both:
1. **Resource tombstone**: Marks the resource itself as deleted
2. **Property tombstones**: Removes all relationships pointing to/from that resource

This ensures complete cleanup while maintaining referential integrity in the tombstone records.

## Benefits

1. **Clean separation**: Framework metadata stays at document level
2. **Readable documents**: App data subgraph remains uncluttered
3. **Extensible**: Can handle future resource-level metadata beyond deletion
4. **Consistent**: Follows same pattern as property tombstones via `sync:hasStatement`
5. **Clear semantics**: Explicit about which resource the statement concerns
6. **Complete deletion**: Supports full resource removal with relationship cleanup

## Use Cases

- **Resource deletion**: Tombstone entire resources within multi-resource documents
- **Resource-level clocks**: Track resource-specific modification times
- **Resource lifecycle**: Creation timestamps, versioning metadata
- **Resource permissions**: Framework-managed access control metadata

## Implementation Notes

- Resource statements are linked to documents via existing `sync:hasStatement`
- Each resource can have at most one resource statement (since `sync:resource` is identifying)
- Resource statements are discovered during framework data traversal from document root
- App data traversal from primary topic never encounters resource statements
- Resource deletion requires coordinated property tombstones for relationships

## Automatic Generation

Libraries can automatically detect resource deletions by comparing app data states and generate the necessary tombstones:

1. **Resource detection**: Identify resources that existed in the old state but not in the new state
2. **Resource tombstone generation**: Create `sync:ResourceStatement` with `crdt:deletedAt` for each deleted resource
3. **Relationship cleanup**: Generate property tombstones for all relationships involving the deleted resource
4. **Coordinated updates**: Ensure both resource and property tombstones use consistent timestamps

This approach eliminates the need for manual tombstone management while ensuring complete cleanup.