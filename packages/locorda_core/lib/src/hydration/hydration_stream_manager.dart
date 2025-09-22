/// Manager for hydration stream controllers.
library;

import 'dart:async';
import 'package:locorda_core/locorda_core.dart';
import 'package:rdf_core/rdf_core.dart';

import 'type_local_name_key.dart';

/// Manages stream controllers for hydration updates.
///
/// Handles creation, storage, and emission for broadcast streams
/// keyed by (Type, localName) pairs.
class HydrationStreamManager {
  final Map<TypeOrIndexKey, StreamController> _controllers = {};

  /// Get or create a stream controller for the given type and local name
  StreamController<HydrationResult<IdentifiedGraph>> getOrCreateController(
      IriTerm type,
      [String? indexName]) {
    final key = TypeOrIndexKey(type, indexName);
    if (!_controllers.containsKey(key)) {
      _controllers[key] =
          StreamController<HydrationResult<IdentifiedGraph>>.broadcast();
    }
    return _controllers[key]!
        as StreamController<HydrationResult<IdentifiedGraph>>;
  }

  bool hasController(TypeOrIndexKey key) {
    return _controllers.containsKey(key);
  }

  /// Emit a result to the stream identified by the given key
  void emitToStream(
      TypeOrIndexKey key, HydrationResult<IdentifiedGraph> result) {
    final controller = _controllers[key];
    if (controller == null) {
      throw StateError(
          'No stream controller exists for key $key. This indicates a programming error - ensure the stream is created before emitting to it.');
    }
    Future.microtask(() => controller.add(result));
  }

  /// Close all stream controllers and free resources
  Future<void> close() async {
    for (final controller in _controllers.values) {
      await controller.close();
    }
    _controllers.clear();
  }
}
