import 'dart:async';

import 'package:locorda_core/locorda_core.dart';
import 'package:locorda_core/src/hydration/hydration_emitter.dart';
import 'package:locorda_core/src/hydration/hydration_stream_manager.dart';
import 'package:locorda_core/src/hydration/type_local_name_key.dart';
import 'package:locorda_core/src/mapping/iri_translator.dart';
import 'package:rdf_core/rdf_core.dart';
import 'package:test/test.dart';

/// Test implementation of HydrationStreamManager that tracks emissions
class TestHydrationStreamManager implements HydrationStreamManager {
  final List<_EmittedData> emittedData = [];
  final Set<TypeOrIndexKey> _existingControllers = {};

  @override
  void emitToStream(
      TypeOrIndexKey key, HydrationResult<IdentifiedGraph> result) {
    emittedData.add(_EmittedData(key, result));
  }

  @override
  StreamController<HydrationResult<IdentifiedGraph>> getOrCreateController(
      IriTerm type,
      [String? indexName]) {
    throw UnimplementedError('Not needed for these tests');
  }

  @override
  bool hasController(TypeOrIndexKey key) {
    return _existingControllers.contains(key);
  }

  @override
  Future<void> close() async {}

  void addController(TypeOrIndexKey key) {
    _existingControllers.add(key);
  }

  void clear() {
    emittedData.clear();
  }
}

class _EmittedData {
  final TypeOrIndexKey key;
  final HydrationResult<IdentifiedGraph> result;

  _EmittedData(this.key, this.result);
}

void main() {
  group('HydrationEmitter', () {
    late TestHydrationStreamManager streamManager;
    late HydrationEmitter emitter;
    late IriTranslator iriTranslator;

    // Test vocabulary
    final testTypeIri = IriTerm('https://example.org/TestNote');
    final titlePredicate = IriTerm('https://schema.org/name');
    final contentPredicate = IriTerm('https://example.org/content');

    // Internal/External IRI pairs for translation
    final internalResourceIri = IriTerm('http://internal.local/notes/123');

    setUp(() {
      streamManager = TestHydrationStreamManager();

      // Set up IRI translator with mapping
      iriTranslator = IriTranslator(
        resourceLocator: LocalResourceLocator(
          iriTermFactory: IriTerm.validated,
        ),
        resourceConfigs: [
          ResourceGraphConfig(
            typeIri: testTypeIri,
            crdtMapping: Uri.parse('http://example.org/mapping'),
            indices: [],
          ),
        ],
      );

      emitter = HydrationEmitter(
        streamManager: streamManager,
        iriTranslator: iriTranslator,
      );
    });

    group('emitForType', () {
      test('should emit result to resource stream with null index name',
          () async {
        final resourceGraph = RdfGraph.fromTriples([
          Triple(
              internalResourceIri, titlePredicate, LiteralTerm.string('Test')),
          Triple(internalResourceIri, contentPredicate,
              LiteralTerm.string('Content')),
        ]);

        final result = HydrationResult<IdentifiedGraph>(
          items: [(internalResourceIri, resourceGraph)],
          deletedItems: [],
          originalCursor: 'cursor1',
          nextCursor: 'cursor2',
          hasMore: false,
        );

        emitter.emitForType(testTypeIri, result);

        // Verify emission
        expect(streamManager.emittedData, hasLength(1));

        final emission = streamManager.emittedData.first;
        expect(emission.key.typeIri, equals(testTypeIri));
        expect(emission.key.indexName, isNull);

        // Verify result structure
        expect(emission.result.items, hasLength(1));
        expect(emission.result.deletedItems, isEmpty);
        expect(emission.result.originalCursor, equals('cursor1'));
        expect(emission.result.nextCursor, equals('cursor2'));
        expect(emission.result.hasMore, isFalse);

        // Verify IRI translation happened (internal -> external)
        final (emittedIri, _) = emission.result.items.first;
        expect(emittedIri, equals(internalResourceIri));
      });

      test('should emit multiple items in batch', () async {
        final resource1Iri = IriTerm('http://internal.local/notes/1');
        final resource2Iri = IriTerm('http://internal.local/notes/2');

        final graph1 = RdfGraph.fromTriples([
          Triple(resource1Iri, titlePredicate, LiteralTerm.string('Note 1')),
        ]);

        final graph2 = RdfGraph.fromTriples([
          Triple(resource2Iri, titlePredicate, LiteralTerm.string('Note 2')),
        ]);

        final result = HydrationResult<IdentifiedGraph>(
          items: [
            (resource1Iri, graph1),
            (resource2Iri, graph2),
          ],
          deletedItems: [],
          originalCursor: null,
          nextCursor: 'cursor1',
          hasMore: true,
        );

        emitter.emitForType(testTypeIri, result);

        expect(streamManager.emittedData, hasLength(1));
        expect(streamManager.emittedData.first.result.items, hasLength(2));
        expect(streamManager.emittedData.first.result.hasMore, isTrue);
      });

      test('should emit deleted items', () async {
        final deletedIri = IriTerm('http://internal.local/notes/deleted');
        final deletedGraph = RdfGraph.fromTriples([]);

        final result = HydrationResult<IdentifiedGraph>(
          items: [],
          deletedItems: [(deletedIri, deletedGraph)],
          originalCursor: 'cursor1',
          nextCursor: 'cursor2',
          hasMore: false,
        );

        emitter.emitForType(testTypeIri, result);

        expect(streamManager.emittedData, hasLength(1));
        expect(streamManager.emittedData.first.result.items, isEmpty);
        expect(
            streamManager.emittedData.first.result.deletedItems, hasLength(1));

        final (deletedEmittedIri, _) =
            streamManager.emittedData.first.result.deletedItems.first;
        expect(deletedEmittedIri, equals(deletedIri));
      });

      test('should emit empty result', () async {
        final result = HydrationResult<IdentifiedGraph>(
          items: [],
          deletedItems: [],
          originalCursor: 'cursor1',
          nextCursor: null,
          hasMore: false,
        );

        emitter.emitForType(testTypeIri, result);

        expect(streamManager.emittedData, hasLength(1));
        expect(streamManager.emittedData.first.result.items, isEmpty);
        expect(streamManager.emittedData.first.result.deletedItems, isEmpty);
        expect(streamManager.emittedData.first.result.nextCursor, isNull);
      });
    });

    group('emitForIndex', () {
      test('should emit result to index stream when controller exists',
          () async {
        final indexConfig = FullIndexGraphConfig(
          localName: 'title-index',
          item: IndexItemGraphConfig({
            IdxShardEntry.resource,
            titlePredicate,
          }),
        );

        // Register controller for this index
        streamManager.addController(TypeOrIndexKey(testTypeIri, 'title-index'));

        final resourceGraph = RdfGraph.fromTriples([
          Triple(
              internalResourceIri, titlePredicate, LiteralTerm.string('Test')),
        ]);

        final result = HydrationResult<IdentifiedGraph>(
          items: [(internalResourceIri, resourceGraph)],
          deletedItems: [],
          originalCursor: 'cursor1',
          nextCursor: 'cursor2',
          hasMore: false,
        );

        emitter.emitForIndex(testTypeIri, indexConfig, result);

        // Verify emission
        expect(streamManager.emittedData, hasLength(1));

        final emission = streamManager.emittedData.first;
        expect(emission.key.typeIri, equals(testTypeIri));
        expect(emission.key.indexName, equals('title-index'));
        expect(emission.result.items, hasLength(1));
      });

      test('should skip emission when no controller exists for index',
          () async {
        final indexConfig = FullIndexGraphConfig(
          localName: 'title-index',
          item: IndexItemGraphConfig({
            IdxShardEntry.resource,
            titlePredicate,
          }),
        );

        // No controller registered

        final resourceGraph = RdfGraph.fromTriples([
          Triple(
              internalResourceIri, titlePredicate, LiteralTerm.string('Test')),
        ]);

        final result = HydrationResult<IdentifiedGraph>(
          items: [(internalResourceIri, resourceGraph)],
          deletedItems: [],
          originalCursor: 'cursor1',
          nextCursor: 'cursor2',
          hasMore: false,
        );

        emitter.emitForIndex(testTypeIri, indexConfig, result);

        // Should not emit anything
        expect(streamManager.emittedData, isEmpty);
      });

      test('should skip emission when index has no item config', () async {
        final indexConfig = FullIndexGraphConfig(
          localName: 'title-index',
          item: null, // No item config
        );

        // Register controller
        streamManager.addController(TypeOrIndexKey(testTypeIri, 'title-index'));

        final resourceGraph = RdfGraph.fromTriples([
          Triple(
              internalResourceIri, titlePredicate, LiteralTerm.string('Test')),
        ]);

        final result = HydrationResult<IdentifiedGraph>(
          items: [(internalResourceIri, resourceGraph)],
          deletedItems: [],
          originalCursor: 'cursor1',
          nextCursor: 'cursor2',
          hasMore: false,
        );

        emitter.emitForIndex(testTypeIri, indexConfig, result);

        // Should not emit anything
        expect(streamManager.emittedData, isEmpty);
      });

      test('should emit to multiple different indices', () async {
        final titleIndexConfig = FullIndexGraphConfig(
          localName: 'title-index',
          item: IndexItemGraphConfig({
            IdxShardEntry.resource,
            titlePredicate,
          }),
        );

        final contentIndexConfig = FullIndexGraphConfig(
          localName: 'content-index',
          item: IndexItemGraphConfig({
            IdxShardEntry.resource,
            contentPredicate,
          }),
        );

        // Register both controllers
        streamManager.addController(TypeOrIndexKey(testTypeIri, 'title-index'));
        streamManager
            .addController(TypeOrIndexKey(testTypeIri, 'content-index'));

        final resourceGraph = RdfGraph.fromTriples([
          Triple(
              internalResourceIri, titlePredicate, LiteralTerm.string('Test')),
          Triple(internalResourceIri, contentPredicate,
              LiteralTerm.string('Content')),
        ]);

        final result = HydrationResult<IdentifiedGraph>(
          items: [(internalResourceIri, resourceGraph)],
          deletedItems: [],
          originalCursor: 'cursor1',
          nextCursor: 'cursor2',
          hasMore: false,
        );

        // Emit to both indices
        emitter.emitForIndex(testTypeIri, titleIndexConfig, result);
        emitter.emitForIndex(testTypeIri, contentIndexConfig, result);

        // Verify both emissions
        expect(streamManager.emittedData, hasLength(2));

        final titleEmission = streamManager.emittedData[0];
        expect(titleEmission.key.indexName, equals('title-index'));

        final contentEmission = streamManager.emittedData[1];
        expect(contentEmission.key.indexName, equals('content-index'));
      });

      test('should emit index result with deleted items', () async {
        final indexConfig = FullIndexGraphConfig(
          localName: 'title-index',
          item: IndexItemGraphConfig({
            IdxShardEntry.resource,
            titlePredicate,
          }),
        );

        streamManager.addController(TypeOrIndexKey(testTypeIri, 'title-index'));

        final deletedIri = IriTerm('http://internal.local/notes/deleted');
        final deletedGraph = RdfGraph.fromTriples([]);

        final result = HydrationResult<IdentifiedGraph>(
          items: [],
          deletedItems: [(deletedIri, deletedGraph)],
          originalCursor: 'cursor1',
          nextCursor: 'cursor2',
          hasMore: false,
        );

        emitter.emitForIndex(testTypeIri, indexConfig, result);

        expect(streamManager.emittedData, hasLength(1));
        expect(
            streamManager.emittedData.first.result.deletedItems, hasLength(1));
        expect(streamManager.emittedData.first.result.items, isEmpty);
      });
    });

    group('IRI Translation', () {
      test('should apply IRI translation to items', () async {
        // Use a mock translator that changes IRIs
        final mockTranslator = _MockIriTranslator();
        final emitterWithMock = HydrationEmitter(
          streamManager: streamManager,
          iriTranslator: mockTranslator,
        );

        final internalIri = IriTerm('http://internal.local/test');
        final graph = RdfGraph.fromTriples([
          Triple(internalIri, titlePredicate, LiteralTerm.string('Test')),
        ]);

        final result = HydrationResult<IdentifiedGraph>(
          items: [(internalIri, graph)],
          deletedItems: [],
          originalCursor: null,
          nextCursor: null,
          hasMore: false,
        );

        emitterWithMock.emitForType(testTypeIri, result);

        expect(streamManager.emittedData, hasLength(1));

        final (translatedIri, translatedGraph) =
            streamManager.emittedData.first.result.items.first;

        // Verify translation was called
        expect(translatedIri.value, contains('TRANSLATED'));
        expect(mockTranslator.internalToExternalCalled, isTrue);
        expect(mockTranslator.translateGraphCalled, isTrue);
      });

      test('should apply IRI translation to deleted items', () async {
        final mockTranslator = _MockIriTranslator();
        final emitterWithMock = HydrationEmitter(
          streamManager: streamManager,
          iriTranslator: mockTranslator,
        );

        final internalIri = IriTerm('http://internal.local/deleted');
        final graph = RdfGraph.fromTriples([]);

        final result = HydrationResult<IdentifiedGraph>(
          items: [],
          deletedItems: [(internalIri, graph)],
          originalCursor: null,
          nextCursor: null,
          hasMore: false,
        );

        emitterWithMock.emitForType(testTypeIri, result);

        expect(streamManager.emittedData, hasLength(1));

        final (translatedIri, _) =
            streamManager.emittedData.first.result.deletedItems.first;

        expect(translatedIri.value, contains('TRANSLATED'));
        expect(mockTranslator.internalToExternalCalled, isTrue);
      });
    });
  });
}

/// Mock IRI translator for testing translation behavior
class _MockIriTranslator implements IriTranslator {
  bool internalToExternalCalled = false;
  bool translateGraphCalled = false;

  @override
  bool get canTranslate => true;

  @override
  IriTerm internalToExternal(IriTerm internal) {
    internalToExternalCalled = true;
    return IriTerm('${internal.value}-TRANSLATED');
  }

  @override
  RdfGraph translateGraphToExternal(RdfGraph graph) {
    translateGraphCalled = true;
    // Simple translation: add suffix to all subjects
    final translatedTriples = graph.triples.map((triple) {
      final newSubject = triple.subject is IriTerm
          ? IriTerm('${(triple.subject as IriTerm).value}-TRANSLATED')
          : triple.subject;
      return Triple(newSubject, triple.predicate, triple.object);
    }).toList();
    return RdfGraph.fromTriples(translatedTriples);
  }

  @override
  IriTerm externalToInternal(IriTerm external) =>
      throw UnimplementedError('Not needed for these tests');

  @override
  RdfGraph translateGraphToInternal(RdfGraph graph) =>
      throw UnimplementedError('Not needed for these tests');
}
