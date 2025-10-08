# Index Entry IRI Identification

## Status
Proposed

## Context

Index shard documents need to contain entries that reference data resources. The current specification uses blank nodes for these entries, but the implementation requires IRI-identified entries to avoid blank node complexity and ensure deterministic fragment generation across all installations.

## Decision

Index entries are identified by **deterministic fragment IRIs** derived from the resource IRI they reference, not by blank nodes or context-identification mechanisms.

### Shard Document Structure

```turtle
# Shard = ManagedDocument (like all framework documents)
<> a sync:ManagedDocument;
   sync:isGovernedBy mappings:shard-v1;
   foaf:primaryTopic <#shard>;
   sync:managedResourceType idx:Shard;
   crdt:hasClockEntry [ ... ];
   crdt:clockHash "xxh64:...";
   crdt:createdAt "2024-08-10T10:00:00Z"^^xsd:dateTime .

# Shard Resource (primary topic)
<#shard> a idx:Shard;
   idx:isShardOf <../index>;
   idx:containsEntry <#entry-XXX>, <#entry-YYY> .  # OR-Set of Entry IRIs

# Entry Subjects (IRI-identified, no blank nodes)
<#entry-a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6>
   idx:resource <../../../../data/notes/note-123>;
   crdt:clockHash "xxh64:abcdef1234567890" .
```

### Fragment Generation Algorithm

All implementations **MUST** use the following algorithm to ensure convergence:

```
fragment_id = "entry-" + MD5(resource_IRI_as_UTF8)
```

Where:
- `MD5()` computes the MD5 hash as a lowercase 32-character hexadecimal string
- `resource_IRI_as_UTF8` is the complete resource IRI (not prefixed form) encoded as UTF-8 bytes
- The resulting fragment identifier is exactly 38 characters: `entry-` (6 chars) + 32 hex chars

**Example:**
```turtle
# Resource: <https://example.org/data/notes/note-123>
# MD5 hash of "https://example.org/data/notes/note-123": a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6
# Entry IRI: <#entry-a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6>
```

### CRDT Merge Semantics

Index entries use standard RDF subject identification (via fragment IRI), not context-identification:

**Shard Level:**
- `idx:containsEntry` → **OR-Set** (union of all entry IRIs from all installations)

**Entry Level (per fragment IRI):**
- `idx:resource` → **Immutable** (resource IRI must not change)
- `crdt:clockHash` → **LWW-Register** (newest hash wins)
- Optional header properties (e.g., `schema:name`) → **LWW-Register**

### Rationale

1. **Deterministic Convergence**: All installations generate identical fragment identifiers for the same resource, ensuring CRDT merge works correctly without coordination

2. **No Blank Node Complexity**: Using IRI-identified subjects avoids the complexity of blank node identification and canonical IRI generation

3. **Standard RDF Semantics**: Entries are normal RDF subjects, merged using standard CRDT rules from `mappings:shard-v1`

4. **Collision Safety**: MD5 with 32 hex characters (2^128 possible values) provides sufficient collision resistance for shard sizes (typically 1000-10000 entries)

5. **Consistent with Framework**: Matches the pattern used for other framework-level fragment identifiers

## Implementation Requirements

### Fragment Generation (Dart Example)

```dart
/// Generates deterministic fragment identifier for index entry.
/// 
/// Uses MD5 hash of resource IRI to ensure all installations
/// generate identical fragment identifiers for the same resource.
/// 
/// This is a specification requirement - all implementations MUST
/// use this exact algorithm for interoperability.
String generateEntryFragment(IriTerm resourceIri) {
  // Use full IRI value, not prefixed form
  final md5Hash = md5.convert(utf8.encode(resourceIri.value)).toString();
  return 'entry-$md5Hash';  // Full 32-character hex string
}
```

### Index Entry Generation

```dart
class IndexManager {
  RdfGraph generateIndexEntry({
    required IriTerm shardDocumentIri,
    required IriTerm shardResourceIri,
    required IriTerm itemResourceIri,
    required String clockHash,
    Map<IriTerm, RdfObject>? headerProperties,
  }) {
    // Generate deterministic fragment from resource IRI
    final entryFragment = _generateEntryFragment(itemResourceIri);
    final entryIri = IriTerm('${shardDocumentIri.value}#$entryFragment');
    
    final triples = <Triple>[
      // Link from shard to entry (OR-Set membership)
      Triple(shardResourceIri, IdxShard.containsEntry, entryIri),
      
      // Entry properties
      Triple(entryIri, Idx.resource, itemResourceIri),  // Immutable
      Triple(entryIri, Crdt.clockHash, LiteralTerm(clockHash)),  // LWW-Register
    ];
    
    // Optional header properties (all LWW-Register)
    if (headerProperties != null) {
      for (final entry in headerProperties.entries) {
        triples.add(Triple(entryIri, entry.key, entry.value));
      }
    }
    
    return triples.toRdfGraph();
  }
}
```

## Consequences

### Positive

- **Interoperability**: All compliant implementations converge on identical shard documents
- **Simplicity**: No need for blank node skolemization or context-identification
- **Performance**: Fragment generation is fast (single MD5 hash)
- **Debuggability**: Fragment identifiers are deterministic and can be computed manually

### Negative

- **Fragment Length**: 38-character fragments are longer than minimal identifiers, but acceptable for URIs
- **Hash Algorithm Dependency**: Changing hash algorithm would break compatibility (not planned)

### Neutral

- **No Human Readability**: Fragment identifiers are opaque hashes (but entries are internal framework data)

## Migration Path

This is a breaking change from the current spec's blank node approach. Migration:

1. **Specification Update**: Update Section 5.3.8 examples to show IRI-identified entries
2. **Add New Section**: Add Section 5.3.X "Index Entry Identification" with algorithm details
3. **Mapping Contract**: Update `mappings:shard-v1` to reflect entry properties (remove blank node context-identification references)

## Related Changes

- Affects `IndexManager` implementation (entry generation)
- Affects `CrdtDocumentManager` (shard persistence)
- Affects merge contract `mappings:shard-v1`
- Related to proposal 006 (local-remote duality) - entries use local IRIs

## References

- Section 5.3: The Indexing Layer
- Section 5.3.8: Index Structure Examples
- Blank node identification discussion
