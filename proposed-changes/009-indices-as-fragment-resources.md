# Use Fragment Identifiers for Index and Shard Resources

**Date:** 2025-10-08
**Status:** Accepted
**Impact:** Implementation simplification, architectural consistency

## Change Summary

Indices and shards will use the standard ManagedDocument pattern with fragment identifiers (#it) for the actual resource, rather than placing index/shard payload at the document level.

**NOTE:** We also do not make heavy use of (property identified) blank nodes, but rather should use IRIs!

## Before (Spec Assumption)

```turtle
<https://alice.pod/indices/recipes/index-full-abc123/index>
  a idx:FullIndex ;
  sync:isGovernedBy <mappings:index-v1> ;
  crdt:hasClockEntry [...] ;
  idx:indexesClass schema:Recipe ;
  idx:shardingAlgorithm [...] ;
  idx:hasShard <shard-mod-md5-1-0-v1_0_0> .
```

## After (Implementation)

```turtle
<https://alice.pod/indices/recipes/index-full-abc123/index>
  a sync:ManagedDocument ;
  sync:managedResourceType idx:FullIndex ;
  foaf:primaryTopic <https://alice.pod/indices/recipes/index-full-abc123/index#it> ;
  sync:isGovernedBy <mappings:index-v1> ;
  crdt:hasClockEntry [...] ;
  crdt:clockHash "abc123" ;
  crdt:createdAt "..." .

<https://alice.pod/indices/recipes/index-full-abc123/index#it>
  a idx:FullIndex ;
  idx:indexesClass schema:Recipe ;
  idx:shardingAlgorithm [...] ;
  idx:hasShard <shard-mod-md5-1-0-v1_0_0> .
```

## Rationale

1. **Code Reuse:** Can use existing `SyncEngine.save()` infrastructure without special-case storage logic
2. **Consistency:** Same CRDT merge semantics everywhere (idx:hasShard uses OR-Set, idx:populationState uses LWW-Register per spec)
3. **Simpler Architecture:** No dual storage paths to maintain
4. **Already Partially There:** GC index template already shows `sync:isGovernedBy` and `crdt:hasClockEntry`, indicating CRDT participation

## Implementation Notes

- Indices (FullIndex, GroupIndex, GroupIndexTemplate) use fragment identifier `#it`
- Shards use fragment identifier `#it`
- All index/shard operations go through `SyncEngine.save()`
- CRDT merge contracts apply (mappings:index-v1, mappings:shard-v1)

## Spec Updates Needed

- Update examples in SHARDING.md to show fragment identifiers
- Update examples in GROUP-INDEXING.md to show fragment identifiers
- Clarify in locorda-SPECIFICATION.md that indices are ManagedDocuments with fragment resources
- Templates (gc-index-template.ttl, etc.) already partially follow this pattern
