import 'dart:async';
import 'package:test/test.dart';
import 'package:rdf_core/rdf_core.dart';
import 'package:locorda_core/src/hydration/hydration_stream_manager.dart';
import 'package:locorda_core/src/hydration/type_local_name_key.dart';
import 'package:locorda_core/src/hydration_result.dart';

typedef IdentifiedGraph = (IriTerm id, RdfGraph graph);

void main() {
  group('HydrationStreamManager', () {
    late HydrationStreamManager manager;
    late IriTerm testTypeIri;
    late IriTerm otherTypeIri;

    setUp(() {
      manager = HydrationStreamManager();
      testTypeIri = const IriTerm('https://example.com/TestDocument');
      otherTypeIri = const IriTerm('https://example.com/OtherDocument');
    });

    tearDown(() async {
      await manager.close();
    });

    test('should create and return stream controller', () {
      final controller = manager.getOrCreateController(testTypeIri, 'test');

      expect(controller, isNotNull);
      expect(controller.stream, isNotNull);
    });

    test('should return same controller for same type and index name', () {
      final controller1 = manager.getOrCreateController(testTypeIri, 'test');
      final controller2 = manager.getOrCreateController(testTypeIri, 'test');

      expect(controller1, equals(controller2));
    });

    test('should return different controllers for different types', () {
      final controller1 = manager.getOrCreateController(testTypeIri, 'test');
      final controller2 = manager.getOrCreateController(otherTypeIri, 'test');

      expect(controller1, isNot(equals(controller2)));
    });

    test('should return different controllers for different index names', () {
      final controller1 = manager.getOrCreateController(testTypeIri, 'test1');
      final controller2 = manager.getOrCreateController(testTypeIri, 'test2');

      expect(controller1, isNot(equals(controller2)));
    });

    test('should emit to correct stream', () async {
      final controller = manager.getOrCreateController(testTypeIri, 'test');
      final key = TypeOrIndexKey(testTypeIri, 'test');

      final documentIri = const IriTerm('https://example.com/doc1');
      final graph = RdfGraph(triples: [
        Triple(documentIri, const IriTerm('https://example.com/title'),
            LiteralTerm('Test Document'))
      ]);

      final result = HydrationResult<IdentifiedGraph>(
        items: [(documentIri, graph)],
        deletedItems: [],
        originalCursor: null,
        nextCursor: 'cursor1',
        hasMore: false,
      );

      // Listen to the stream
      final streamEvents = <HydrationResult<IdentifiedGraph>>[];
      final subscription = controller.stream.listen(streamEvents.add);

      // Emit to the stream
      manager.emitToStream(key, result);

      // Wait for async emission
      await Future.delayed(Duration.zero);

      expect(streamEvents, hasLength(1));
      expect(streamEvents.first, equals(result));

      await subscription.cancel();
    });

    test('should throw when emitting to non-existent stream', () {
      final key = TypeOrIndexKey(testTypeIri, 'nonexistent');

      final documentIri = const IriTerm('https://example.com/doc1');
      final graph = RdfGraph(triples: [
        Triple(documentIri, const IriTerm('https://example.com/title'),
            LiteralTerm('Test Document'))
      ]);

      final result = HydrationResult<IdentifiedGraph>(
        items: [(documentIri, graph)],
        deletedItems: [],
        originalCursor: null,
        nextCursor: null,
        hasMore: false,
      );

      // Should throw StateError for programming errors
      expect(
        () => manager.emitToStream(key, result),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('No stream controller exists for key'),
        )),
      );
    });

    test('should handle multiple concurrent listeners', () async {
      final controller = manager.getOrCreateController(testTypeIri, 'test');
      final key = TypeOrIndexKey(testTypeIri, 'test');

      final documentIri = const IriTerm('https://example.com/doc1');
      final graph = RdfGraph(triples: [
        Triple(documentIri, const IriTerm('https://example.com/title'),
            LiteralTerm('Broadcast Document'))
      ]);

      final result = HydrationResult<IdentifiedGraph>(
        items: [(documentIri, graph)],
        deletedItems: [],
        originalCursor: null,
        nextCursor: null,
        hasMore: false,
      );

      // Set up multiple listeners
      final events1 = <HydrationResult<IdentifiedGraph>>[];
      final events2 = <HydrationResult<IdentifiedGraph>>[];

      final sub1 = controller.stream.listen(events1.add);
      final sub2 = controller.stream.listen(events2.add);

      // Emit once
      manager.emitToStream(key, result);
      await Future.delayed(Duration.zero);

      // Both should receive the event
      expect(events1, hasLength(1));
      expect(events2, hasLength(1));
      expect(events1.first, equals(result));
      expect(events2.first, equals(result));

      await sub1.cancel();
      await sub2.cancel();
    });

    test('should close all controllers', () async {
      final controller1 = manager.getOrCreateController(testTypeIri, 'test1');
      final controller2 = manager.getOrCreateController(otherTypeIri, 'test2');

      expect(controller1.isClosed, isFalse);
      expect(controller2.isClosed, isFalse);

      await manager.close();

      expect(controller1.isClosed, isTrue);
      expect(controller2.isClosed, isTrue);
    });
  });
}
