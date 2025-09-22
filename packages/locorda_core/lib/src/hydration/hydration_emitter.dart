/// Handles emission of hydration results to both resource and index streams.
library;

import 'package:locorda_core/src/config/sync_graph_config.dart';
import 'package:locorda_core/src/hydration/convert_to_index_item.dart';
import 'package:locorda_core/src/locorda_graph_sync.dart';

import '../hydration_result.dart';
import 'hydration_stream_manager.dart';
import 'type_local_name_key.dart';

/// Emits hydration results to appropriate streams with index conversion.
///
/// This component handles the complex logic of emitting hydration results
/// to both resource streams and associated index streams, performing
/// type-safe conversion using registered converters.
class HydrationEmitter {
  final HydrationStreamManager _streamManager;

  HydrationEmitter({
    required HydrationStreamManager streamManager,
  }) : _streamManager = streamManager;

  /// Emit a hydration result to resource and index streams
  void emit(
      HydrationResult<IdentifiedGraph> result, ResourceGraphConfig config) {
    // Emit to resource stream
    _streamManager.emitToStream(TypeOrIndexKey(config.typeIri, null), result);

    // Emit to index streams
    for (final index in config.indices) {
      if (index.item != null) {
        final itemIndexKey = TypeOrIndexKey(config.typeIri, index.localName);
        if (!_streamManager.hasController(itemIndexKey)) {
          // No stream for this index - skip emitting
          continue;
        }

        final converter = (IdentifiedGraph resource) =>
            convertToIndexItem(config.typeIri, resource, index.item!);

        final indexItemHydrationResult = HydrationResult<IdentifiedGraph>(
          items: result.items.map(converter).toList(),
          deletedItems: result.deletedItems.map(converter).toList(),
          originalCursor: result.originalCursor,
          nextCursor: result.nextCursor,
          hasMore: result.hasMore,
        );

        // Emit to index stream
        _streamManager.emitToStream(itemIndexKey, indexItemHydrationResult);
      }
    }
  }
}
