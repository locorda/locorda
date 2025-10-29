# Group Index Test Cases - Implementation Status

This document tracks the comprehensive test coverage for Group Index functionality added to `all_tests.json`.

## Test Cases Overview

### ✅ Implemented & Passing
- **save_31**: First save with group index - creates template and group

### 🔧 Implemented Tests (Expected to Fail Initially)

The following test cases have been fully specified with input files and expected behavior documented. They are expected to fail until the corresponding features are implemented.

#### Core Functionality Tests

**save_32: Multiple Groups (OR-Set)**
- **Priority**: 🔴 Critical
- **Description**: Recipe with `recipeCategory=['Desserts', 'Quick Meals']` should create entries in both group index shards
- **Tests**: Multiple shard membership, `idx:belongsToIndexShard` with multiple values
- **Implementation needed**: Multi-group assignment logic

**save_36: Foreign Shard Discovery**
- **Priority**: 🔴 Critical  
- **Description**: Application dynamically discovers and updates shard by reading template, evaluating grouping rules, and constructing shard IRI
- **Tests**: Core dynamic shard discovery mechanism without pre-existing references
- **Implementation needed**: Template-driven shard IRI construction, dynamic shard loading/creation

#### Group Membership Mutation Tests

**save_33: Update Group Membership (Change Category)**
- **Priority**: 🔴 Critical
- **Description**: Changing category from 'Desserts' → 'Main Course' should remove from old shard (tombstone) and add to new
- **Tests**: Shard migration, bidirectional index maintenance, tombstone creation in old shard
- **Implementation needed**: Shard removal logic, tombstone generation for old membership

**save_34: Add Group Membership (OR-Set Add)**
- **Priority**: 🟡 Important
- **Description**: Adding 'Quick Meals' to existing `['Desserts']` should add entry to second shard
- **Tests**: OR-Set addition semantics, maintaining existing shard entries
- **Implementation needed**: Incremental shard addition

**save_35: Remove Group Membership (OR-Set Remove)**
- **Priority**: 🟡 Important
- **Description**: Removing 'Quick Meals' from `['Desserts', 'Quick Meals']` should tombstone entry in second shard
- **Tests**: OR-Set removal semantics, tombstone creation, `belongsToIndexShard` update
- **Implementation needed**: Selective shard removal with tombstones

#### Edge Cases & Robustness

**save_38: Missing Property - Skip Strategy**
- **Priority**: 🔴 Critical
- **Description**: Recipe without `recipeCategory` should be skipped from group index
- **Tests**: `missingValueStrategy: skip` behavior
- **Implementation needed**: Missing property handling

**save_39: Missing Property - Default Value**
- **Priority**: 🔴 Critical
- **Description**: Recipe without `recipeCategory` should use default value 'Uncategorized'
- **Tests**: `missingValueStrategy: useDefault` with `defaultValue` configuration
- **Implementation needed**: Default value substitution

#### Advanced Features

**save_37: Hierarchical Grouping (Multi-Level)**
- **Priority**: 🟡 Important
- **Description**: Extract year and month from `dateCreated` using composite identification key `(sourceProperty, hierarchyLevel)`
- **Tests**: Nested shard paths like `2024/01`, validates composite key fix from earlier session
- **Implementation needed**: Hierarchical path construction, multi-property evaluation

**save_40: Property Transformation (Lowercase)**
- **Priority**: 🟡 Important
- **Description**: Category 'DESSERTS' should be transformed to lowercase 'desserts' for shard path
- **Tests**: Transform chain execution, LowercaseTransform implementation
- **Implementation needed**: Transform pipeline execution

#### Performance & Optimization

**save_41: No-Op Save with Group Index**
- **Priority**: 🟢 Nice-to-Have
- **Description**: Re-saving with identical category should not update index shards
- **Tests**: Change detection optimization, avoiding unnecessary shard writes
- **Implementation needed**: Index-aware change detection

## Configuration Files

Three new configuration files created:

1. **`hierarchical_group_index_config.json`**
   - Multi-level grouping with `hierarchyLevel` 1 and 2
   - Regex transforms for date extraction (year, month)

2. **`group_index_with_default_config.json`**
   - `missingValueStrategy: "useDefault"`
   - `defaultValue: "Uncategorized"`

3. **`group_index_with_transform_config.json`**
   - `LowercaseTransform` for category normalization

## Implementation Priority

### Phase 1: Core Functionality (🔴 Critical)
1. **save_36**: Foreign shard discovery - validates core mechanism
2. **save_32**: Multiple groups - essential feature
3. **save_33**: Update group membership - mutation handling
4. **save_38/39**: Missing property handling - robustness

### Phase 2: Mutation & Edge Cases (🟡 Important)
5. **save_34/35**: Add/Remove in OR-Set
6. **save_37**: Hierarchical grouping - validates composite key fix
7. **save_40**: Property transformations

### Phase 3: Optimization (🟢 Nice-to-Have)
8. **save_41**: No-op detection

## Known Limitations

### Not Yet Tested
- **Shard splitting/resharding**: When shards reach `maxSize` limits
  - Tracked in TODO.md for future implementation
  - Multi-shard scenarios with `numberOfShards > 1`
  
### Test Asset Status
- All tests have `input_resource.ttl` and `stored_graph_before.ttl` (where needed)
- Expected output files (`expected_stored_graph.ttl`, `expected_shard_*.ttl`) contain TODOs for:
  - Clock hash values (computed at runtime)
  - Entry hash values (computed at runtime)
  - Some IRI constructions (validated against actual implementation)

## Testing Strategy

The test cases are designed to fail initially, revealing exactly what needs to be implemented. As each feature is implemented in priority order, the corresponding tests should begin passing, providing clear validation of correctness.

Run specific test: `dart test test/sync/sync_engine_test.dart --name "save_XX"`

## Specification Questions Resolved

During test creation, we identified a spec ambiguity:

**Question**: Should items be explicitly removed from old shards when group membership changes?

**Answer**: Yes, per spec line 1100:
> "Removing a document from an index means removing both its shard entry and updating the document to remove its `idx:belongsToIndexShard` reference to that shard."

This applies to group membership changes where the item moves from one group to another. Test save_33 validates this behavior with explicit tombstone expectations in the old shard.
