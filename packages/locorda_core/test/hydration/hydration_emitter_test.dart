import 'dart:async';

import 'package:locorda_core/locorda_core.dart';
import 'package:locorda_core/src/hydration/hydration_emitter.dart';
import 'package:locorda_core/src/hydration/hydration_stream_manager.dart';
import 'package:locorda_core/src/hydration/type_local_name_key.dart';
import 'package:rdf_core/rdf_core.dart';
import 'package:test/test.dart';

typedef IdentifiedGraph = (IriTerm id, RdfGraph graph);

// Test implementation of HydrationStreamManager
class TestHydrationStreamManager implements HydrationStreamManager {
  final List<String> emittedKeys = [];
  final List<HydrationResult<IdentifiedGraph>> emittedResults = [];
  final Set<TypeOrIndexKey> _existingControllers = {};

  @override
  void emitToStream(
      TypeOrIndexKey key, HydrationResult<IdentifiedGraph> result) {
    emittedKeys.add(key.toString());
    emittedResults.add(result);
  }

  @override
  StreamController<HydrationResult<IdentifiedGraph>> getOrCreateController(
      IriTerm type,
      [String? indexName]) {
    final key = TypeOrIndexKey(type, indexName);
    _existingControllers.add(key);
    return StreamController<HydrationResult<IdentifiedGraph>>.broadcast();
  }

  @override
  bool hasController(TypeOrIndexKey key) {
    return _existingControllers.contains(key);
  }

  @override
  Future<void> close() async {}

  void clear() {
    emittedKeys.clear();
    emittedResults.clear();
    _existingControllers.clear();
  }

  void addController(TypeOrIndexKey key) {
    _existingControllers.add(key);
  }
}

void main() {
  group('HydrationEmitter', () {
    late TestHydrationStreamManager streamManager;
    late HydrationEmitter emitter;

    // Test vocabulary
    final testTypeIri = const IriTerm('https://example.org/TestNote');
    final titlePredicate = const IriTerm('https://schema.org/name');
    final contentPredicate = const IriTerm('https://example.org/content');

    setUp(() {
      streamManager = TestHydrationStreamManager();
      emitter = HydrationEmitter(
        streamManager: streamManager,
      );
    });

    test('should emit to resource stream only when no indices', () {
      // Config without indices
      final config = ResourceGraphConfig(
        typeIri: testTypeIri,
        crdtMapping: Uri.parse('http://example.org/mapping'),
        indices: [],
      );

      final resourceSubject = const IriTerm('https://example.org/notes/test');
      final resourceGraph = RdfGraph(triples: [
        Triple(resourceSubject, titlePredicate, LiteralTerm.string('Test')),
        Triple(
            resourceSubject, contentPredicate, LiteralTerm.string('Content')),
      ]);

      final result = HydrationResult<IdentifiedGraph>(
        items: [(resourceSubject, resourceGraph)],
        deletedItems: [],
        originalCursor: 'cursor1',
        nextCursor: 'cursor2',
        hasMore: false,
      );

      emitter.emit(result, config);

      // Should emit only to resource stream
      expect(streamManager.emittedKeys, hasLength(1));
      expect(streamManager.emittedKeys.first, contains(testTypeIri.value));
      expect(
          streamManager.emittedKeys.first, contains('null')); // No index name
      expect(streamManager.emittedResults.first, equals(result));
    });

    test(
        'should emit to both resource and index streams when index stream exists',
        () {
      // Set up index configuration
      final indexItem = IndexItemGraphConfig({
        IdxShardEntry.resource,
        titlePredicate,
      });
      final index = FullIndexGraphConfig(
        localName: 'title-index',
        item: indexItem,
      );

      final config = ResourceGraphConfig(
        typeIri: testTypeIri,
        crdtMapping: Uri.parse('http://example.org/mapping'),
        indices: [index],
      );

      // Add index controller to stream manager
      final indexKey = TypeOrIndexKey(testTypeIri, 'title-index');
      streamManager.addController(indexKey);

      final resourceSubject = const IriTerm('https://example.org/notes/test');
      final resourceGraph = RdfGraph(triples: [
        Triple(
            resourceSubject, titlePredicate, LiteralTerm.string('Test Title')),
        Triple(
            resourceSubject, contentPredicate, LiteralTerm.string('Content')),
      ]);

      final result = HydrationResult<IdentifiedGraph>(
        items: [(resourceSubject, resourceGraph)],
        deletedItems: [],
        originalCursor: 'cursor1',
        nextCursor: 'cursor2',
        hasMore: false,
      );

      emitter.emit(result, config);

      // Should emit to both streams
      expect(streamManager.emittedKeys, hasLength(2));

      // Check resource stream emission
      expect(streamManager.emittedKeys[0], contains(testTypeIri.value));
      expect(streamManager.emittedKeys[0], contains('null'));
      expect(streamManager.emittedResults[0], equals(result));

      // Check index stream emission
      expect(streamManager.emittedKeys[1], contains(testTypeIri.value));
      expect(streamManager.emittedKeys[1], contains('title-index'));

      final indexResult = streamManager.emittedResults[1];
      expect(indexResult.items, hasLength(1));
      expect(indexResult.originalCursor, equals('cursor1'));
      expect(indexResult.nextCursor, equals('cursor2'));

      // Verify index item contains filtered properties
      final (indexSubject, indexGraph) = indexResult.items.first;
      final indexTriples = indexGraph.triples.toList();
      expect(indexTriples.any((t) => t.predicate == titlePredicate), isTrue);
      expect(indexTriples.any((t) => t.predicate == IdxShardEntry.resource),
          isTrue);
      expect(indexTriples.any((t) => t.predicate == contentPredicate),
          isFalse); // Filtered out
    });

    test('should handle deletions in index conversion', () {
      final indexItem = IndexItemGraphConfig({
        IdxShardEntry.resource,
        titlePredicate,
      });
      final index = FullIndexGraphConfig(
        localName: 'title-index',
        item: indexItem,
      );

      final config = ResourceGraphConfig(
        typeIri: testTypeIri,
        crdtMapping: Uri.parse('http://example.org/mapping'),
        indices: [index],
      );

      final indexKey = TypeOrIndexKey(testTypeIri, 'title-index');
      streamManager.addController(indexKey);

      final deletedSubject = const IriTerm('https://example.org/notes/deleted');
      final deletedGraph = RdfGraph(triples: [
        Triple(deletedSubject, titlePredicate,
            LiteralTerm.string('Deleted Title')),
        Triple(deletedSubject, contentPredicate,
            LiteralTerm.string('Deleted Content')),
      ]);

      final result = HydrationResult<IdentifiedGraph>(
        items: [],
        deletedItems: [(deletedSubject, deletedGraph)],
        originalCursor: 'cursor1',
        nextCursor: 'cursor2',
        hasMore: false,
      );

      emitter.emit(result, config);

      // Check index deletion conversion
      expect(streamManager.emittedKeys, hasLength(2));
      final indexResult = streamManager.emittedResults[1];
      expect(indexResult.deletedItems, hasLength(1));
      expect(indexResult.items, isEmpty);

      // Verify deleted index item structure
      final (deletedIndexSubject, deletedIndexGraph) =
          indexResult.deletedItems.first;
      final indexTriples = deletedIndexGraph.triples.toList();
      expect(indexTriples.any((t) => t.predicate == titlePredicate), isTrue);
      expect(indexTriples.any((t) => t.predicate == IdxShardEntry.resource),
          isTrue);
    });

    test('should skip index emission when no stream controller exists', () {
      final indexItem = IndexItemGraphConfig({
        IdxShardEntry.resource,
        titlePredicate,
      });
      final index = FullIndexGraphConfig(
        localName: 'unregistered-index',
        item: indexItem,
      );

      final config = ResourceGraphConfig(
        typeIri: testTypeIri,
        crdtMapping: Uri.parse('http://example.org/mapping'),
        indices: [index],
      );

      // Don't add the index controller to stream manager

      final resourceSubject = const IriTerm('https://example.org/notes/test');
      final resourceGraph = RdfGraph(triples: [
        Triple(resourceSubject, titlePredicate, LiteralTerm.string('Test')),
        Triple(
            resourceSubject, contentPredicate, LiteralTerm.string('Content')),
      ]);

      final result = HydrationResult<IdentifiedGraph>(
        items: [(resourceSubject, resourceGraph)],
        deletedItems: [],
        originalCursor: null,
        nextCursor: null,
        hasMore: false,
      );

      emitter.emit(result, config);

      // Should emit only to resource stream (no controller for index)
      expect(streamManager.emittedKeys, hasLength(1));
      expect(streamManager.emittedKeys.first, contains(testTypeIri.value));
      expect(streamManager.emittedKeys.first, contains('null'));
    });

    test('should handle index with null item', () {
      final index = FullIndexGraphConfig(
        localName: 'null-item-index',
        item: null,
      );

      final config = ResourceGraphConfig(
        typeIri: testTypeIri,
        crdtMapping: Uri.parse('http://example.org/mapping'),
        indices: [index],
      );

      final resourceSubject = const IriTerm('https://example.org/notes/test');
      final resourceGraph = RdfGraph(triples: [
        Triple(resourceSubject, titlePredicate, LiteralTerm.string('Test')),
        Triple(
            resourceSubject, contentPredicate, LiteralTerm.string('Content')),
      ]);

      final result = HydrationResult<IdentifiedGraph>(
        items: [(resourceSubject, resourceGraph)],
        deletedItems: [],
        originalCursor: null,
        nextCursor: null,
        hasMore: false,
      );

      // Should not throw and should only emit to resource stream
      expect(() => emitter.emit(result, config), returnsNormally);
      expect(streamManager.emittedKeys, hasLength(1));
    });

    test('should handle multiple indices', () {
      final titleIndexItem = IndexItemGraphConfig({
        IdxShardEntry.resource,
        titlePredicate,
      });
      final contentIndexItem = IndexItemGraphConfig({
        IdxShardEntry.resource,
        contentPredicate,
      });

      final titleIndex = FullIndexGraphConfig(
        localName: 'title-index',
        item: titleIndexItem,
      );

      final contentIndex = FullIndexGraphConfig(
        localName: 'content-index',
        item: contentIndexItem,
      );

      final config = ResourceGraphConfig(
        typeIri: testTypeIri,
        crdtMapping: Uri.parse('http://example.org/mapping'),
        indices: [titleIndex, contentIndex],
      );

      // Register only title index controller
      final titleKey = TypeOrIndexKey(testTypeIri, 'title-index');
      streamManager.addController(titleKey);
      // contentIndex controller not added

      final resourceSubject = const IriTerm('https://example.org/notes/test');
      final resourceGraph = RdfGraph(triples: [
        Triple(
            resourceSubject, titlePredicate, LiteralTerm.string('Test Title')),
        Triple(resourceSubject, contentPredicate,
            LiteralTerm.string('Test Content')),
      ]);

      final result = HydrationResult<IdentifiedGraph>(
        items: [(resourceSubject, resourceGraph)],
        deletedItems: [],
        originalCursor: null,
        nextCursor: null,
        hasMore: false,
      );

      emitter.emit(result, config);

      // Should emit to resource stream + title index only
      expect(streamManager.emittedKeys, hasLength(2));
      expect(streamManager.emittedKeys[0], contains(testTypeIri.value));
      expect(streamManager.emittedKeys[0], contains('null'));
      expect(streamManager.emittedKeys[1], contains(testTypeIri.value));
      expect(streamManager.emittedKeys[1], contains('title-index'));
    });

    test('should preserve all HydrationResult fields in conversion', () {
      final indexItem = IndexItemGraphConfig({
        IdxShardEntry.resource,
        titlePredicate,
      });
      final index = FullIndexGraphConfig(
        localName: 'title-index',
        item: indexItem,
      );

      final config = ResourceGraphConfig(
        typeIri: testTypeIri,
        crdtMapping: Uri.parse('http://example.org/mapping'),
        indices: [index],
      );

      final indexKey = TypeOrIndexKey(testTypeIri, 'title-index');
      streamManager.addController(indexKey);

      final itemSubject = const IriTerm('https://example.org/notes/item');
      final itemGraph = RdfGraph(triples: [
        Triple(itemSubject, titlePredicate, LiteralTerm.string('Item')),
        Triple(itemSubject, contentPredicate, LiteralTerm.string('Content')),
      ]);

      final deletedSubject = const IriTerm('https://example.org/notes/deleted');
      final deletedGraph = RdfGraph(triples: [
        Triple(deletedSubject, titlePredicate, LiteralTerm.string('Deleted')),
        Triple(deletedSubject, contentPredicate, LiteralTerm.string('Content')),
      ]);

      final result = HydrationResult<IdentifiedGraph>(
        items: [(itemSubject, itemGraph)],
        deletedItems: [(deletedSubject, deletedGraph)],
        originalCursor: 'original-cursor',
        nextCursor: 'next-cursor',
        hasMore: true,
      );

      emitter.emit(result, config);

      final indexResult = streamManager.emittedResults[1];
      expect(indexResult.originalCursor, equals('original-cursor'));
      expect(indexResult.nextCursor, equals('next-cursor'));
      expect(indexResult.hasMore, equals(true));
      expect(indexResult.items, hasLength(1));
      expect(indexResult.deletedItems, hasLength(1));
    });
  });
}
