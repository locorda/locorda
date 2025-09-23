# DriftStorage Tests

## Running Tests

The `locorda_drift` package tests use `flutter_test` and should be run in a Flutter context:

```bash
# From the locorda_drift package directory
flutter test
```

## Comprehensive Test Coverage

### DriftStorage Tests (`drift_storage_test.dart`)
- ✅ Document operations (save, retrieve, update)
- ✅ Property change operations with logical clock filtering
- ✅ Sync query operations with proper ordering and limits
- ✅ Database initialization and cleanup
- ✅ Factory constructor validation
- ✅ Transaction behavior with property changes

### SyncDatabase Tests (`sync_database_test.dart`)
- ✅ IriBatchLoader mixin functionality
  - Batch IRI creation and retrieval
  - IRI ID reuse optimization
  - Empty set handling
  - Large batch efficiency (1500+ items)
- ✅ SyncDocumentDao operations
  - Document CRUD operations
  - Content retrieval with metadata
  - Timestamp-based queries
  - Query limits and ordering
- ✅ SyncPropertyChangeDao operations
  - Batch property change recording
  - Logical clock filtering
  - Multiple resource/property efficiency
- ✅ Database schema validation
  - Table and index creation
  - Foreign key constraint enforcement
- ✅ Transaction rollback behavior

## Test Implementation

The tests use `testWidgets` from `flutter_test` to ensure proper Flutter binding initialization. Key features tested:

- **Storage Interface Compliance**: All Storage methods implemented correctly
- **Performance Optimizations**: Batch operations prevent N+1 query problems
- **CRDT Support**: Property-level change tracking with timestamps and logical clocks
- **Data Integrity**: Transaction atomicity and foreign key constraints
- **Query Performance**: Proper indexing for sync operations
- **Error Handling**: Graceful handling of edge cases

## Test Environment

Tests create in-memory SQLite databases using the default DriftStorage constructor, which automatically uses appropriate test-friendly database configurations in the Flutter test environment.