/// Handles emission of hydration results to both resource and index streams.
library;

import 'package:locorda_core/src/config/sync_graph_config.dart';
import 'package:locorda_core/src/locorda_graph_sync.dart';
import 'package:locorda_core/src/mapping/iri_translator.dart';
import 'package:rdf_core/rdf_core.dart';

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
  final IriTranslator _iriTranslator;

  HydrationEmitter({
    required HydrationStreamManager streamManager,
    required IriTranslator iriTranslator,
  })  : _iriTranslator = iriTranslator,
        _streamManager = streamManager;

  void emitForType(IriTerm typeIri, HydrationResult<IdentifiedGraph> result) {
    // Emit to resource stream
    _streamManager.emitToStream(
        TypeOrIndexKey(typeIri, null), result.convert(_externalize));
  }

  void emitForIndex(
    IriTerm typeIri,
    CrdtIndexGraphConfig index,
    HydrationResult<IdentifiedGraph> result,
  ) {
    // Emit to index streams

    if (index.item != null) {
      final itemIndexKey = TypeOrIndexKey(typeIri, index.localName);
      if (!_streamManager.hasController(itemIndexKey)) {
        // No stream for this index - skip emitting
        return;
      }
      // Emit to index stream
      _streamManager.emitToStream(itemIndexKey, result.convert(_externalize));
    }
  }

  IdentifiedGraph _externalize(IdentifiedGraph e) => (
        _iriTranslator.internalToExternal(e.$1),
        _iriTranslator.translateGraphToExternal(e.$2)
      );
}
