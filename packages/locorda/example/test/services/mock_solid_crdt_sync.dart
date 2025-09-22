/// Mock LocordaSync implementation for testing.
library;

import 'dart:async';
import 'package:locorda_core/locorda_core.dart';

/// Simple mock implementation for testing
class MockLocordaSync implements LocordaSync {
  final List<dynamic> savedObjects = [];

  @override
  Future<void> save<T>(T object) async {
    savedObjects.add(object);
  }

  @override
  Future<void> close() async {}

  @override
  Future<void> deleteDocument<T>(T object) async {
    savedObjects.removeWhere((item) => item == object);
  }

  @override
  Future<StreamSubscription<HydrationResult<T>>> hydrateStreaming<T>({
    required Future<String?> Function() getCurrentCursor,
    required Future<void> Function(T item) onUpdate,
    required Future<void> Function(T item) onDelete,
    required Future<void> Function(String cursor) onCursorUpdate,
    String? localName,
    int limit = 100,
  }) async {
    // Mock implementation - return empty subscription
    return Stream<HydrationResult<T>>.empty().listen(null);
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
