/// Mock LocordaSync implementation for testing.
library;

import 'dart:async';
import 'package:locorda/locorda.dart';
import 'package:locorda_core/locorda_core.dart';
import 'package:locorda_core/src/sync/standard_sync_manager.dart';

class _MockSyncManager extends StandardSyncManager {
  _MockSyncManager()
      : super(
          syncFunction: (syncTime) async {},
          autoSyncConfig: const AutoSyncConfig.disabled(),
          physicalTimestampFactory: () => DateTime.now(),
        );
}

/// Simple mock implementation for testing
class MockLocordaSync implements LocordaSync {
  final List<dynamic> savedObjects = [];
  final _syncManager = _MockSyncManager();

  @override
  SyncManager get syncManager => _syncManager;

  @override
  Future<void> save<T>(T object) async {
    savedObjects.add(object);
  }

  @override
  Future<void> close() async {}

  @override
  Future<void> deleteDocument<T>(String id) async {
    savedObjects.removeWhere((item) => item.id == id);
  }

  @override
  Stream<TypedHydrationBatch<T>> hydrateStream<T>({
    String? cursor,
    String localName = 'default',
    int initialBatchSize = 100,
  }) {
    // Mock implementation - return empty stream
    return Stream.empty();
  }

  @override
  Future<StreamSubscription<TypedHydrationBatch<T>>> hydrateWithCallbacks<T>({
    required Future<String?> Function() getCurrentCursor,
    required Future<void> Function(T item) onUpdate,
    required Future<void> Function(String itemId) onDelete,
    required Future<void> Function(String cursor) onCursorUpdate,
    void Function(Object error, StackTrace stackTrace)? onError,
    String localName = 'default',
    int initialBatchSize = 100,
  }) async {
    // Mock implementation - return subscription to empty stream
    return Stream<TypedHydrationBatch<T>>.empty().listen((_) {});
  }

  @override
  Future<void> configureGroupIndexSubscription<G>(
      G groupKey, ItemFetchPolicy itemFetchPolicy,
      {String localName = defaultIndexLocalName}) async {
    // Mock implementation - do nothing
  }

  @override
  Future<T?> ensure<T>(String id,
      {required Future<T?> Function(String id) loadFromLocal,
      Duration? timeout = const Duration(seconds: 15)}) {
    return loadFromLocal(id);
  }
}
