/// Mock LocordaSync implementation for testing.
library;

import 'dart:async';
import 'package:locorda/locorda.dart';
import 'package:locorda_core/locorda_core.dart';

class _MockHydrationSubscription implements HydrationSubscription {
  @override
  Future<void> cancel() {
    // Mock implementation - do nothing
    return Future.value();
  }

  @override
  bool get isActive => true;
}

class _MockSyncManager extends SyncManager {
  _MockSyncManager()
      : super(
          syncFunction: () async {},
          autoSyncConfig: const AutoSyncConfig.disabled(),
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
  Future<HydrationSubscription> hydrateStreaming<T>({
    required Future<String?> Function() getCurrentCursor,
    required Future<void> Function(T item) onUpdate,
    required Future<void> Function(T item) onDelete,
    required Future<void> Function(String cursor) onCursorUpdate,
    String? localName,
    int batchSize = 100,
  }) async {
    // Mock implementation - return empty subscription
    return _MockHydrationSubscription();
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
