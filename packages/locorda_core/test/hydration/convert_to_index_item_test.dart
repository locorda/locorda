import 'package:locorda_core/src/hydration/convert_to_index_item.dart';
import 'package:rdf_core/rdf_core.dart';
import 'package:locorda_core/src/config/sync_graph_config.dart';
import 'package:locorda_core/src/vocabulary/idx_vocab.dart';
import 'package:test/test.dart';

typedef IdentifiedGraph = (IriTerm id, RdfGraph graph);

void main() {
  group('convertToIndexItem', () {
    // Test vocabulary
    final testTypeIri = const IriTerm('https://example.org/TestNote');
    final titlePredicate = const IriTerm('https://schema.org/name');
    final contentPredicate = const IriTerm('https://example.org/content');
    final createdPredicate = const IriTerm('https://schema.org/dateCreated');
    final modifiedPredicate = const IriTerm('https://schema.org/dateModified');
    final keywordsPredicate = const IriTerm('https://schema.org/keywords');

    test('converts resource to index item with filtered properties', () {
      // Create a test resource with multiple properties
      final resourceSubject =
          const IriTerm('https://example.org/notes/test-note');
      final resourceGraph = RdfGraph(triples: [
        Triple(
            resourceSubject, titlePredicate, LiteralTerm.string('Test Note')),
        Triple(resourceSubject, contentPredicate,
            LiteralTerm.string('This is the full content')),
        Triple(resourceSubject, createdPredicate,
            LiteralTerm.string('2023-01-01T10:00:00Z')),
        Triple(resourceSubject, modifiedPredicate,
            LiteralTerm.string('2023-01-02T15:30:00Z')),
        Triple(resourceSubject, keywordsPredicate, LiteralTerm.string('work')),
        Triple(resourceSubject, keywordsPredicate,
            LiteralTerm.string('important')),
      ]);

      final identifiedGraph = (resourceSubject, resourceGraph);

      // Define index item configuration with only selected properties
      final indexItem = IndexItemGraphConfig({
        IdxVocab.resource,
        titlePredicate,
        createdPredicate,
        modifiedPredicate,
        keywordsPredicate,
      });

      // Convert to index item
      final (indexSubject, indexGraph) = convertToIndexItem(
        testTypeIri,
        identifiedGraph,
        indexItem,
      );

      // Verify the index graph contains only the specified properties
      final indexTriples = indexGraph.triples.toList();

      // Should have the idx:resource reference
      expect(
          indexTriples.any((t) =>
              t.predicate == IdxVocab.resource && t.object == resourceSubject),
          isTrue,
          reason: 'Should include idx:resource reference');

      // Should have filtered properties
      expect(indexTriples.any((t) => t.predicate == titlePredicate), isTrue,
          reason: 'Should include title');

      expect(indexTriples.any((t) => t.predicate == createdPredicate), isTrue,
          reason: 'Should include creation date');

      expect(indexTriples.any((t) => t.predicate == keywordsPredicate), isTrue,
          reason: 'Should include keywords');

      // Should NOT have the content property (filtered out)
      expect(indexTriples.any((t) => t.predicate == contentPredicate), isFalse,
          reason: 'Should filter out content property');

      // Should use the original resource subject as the ID
      expect(indexSubject, equals(resourceSubject));
    });

    test('handles resource with minimal properties', () {
      final resourceSubject =
          const IriTerm('https://example.org/notes/minimal');
      final resourceGraph = RdfGraph(triples: [
        Triple(resourceSubject, titlePredicate,
            LiteralTerm.string('Minimal Note')),
        Triple(resourceSubject, createdPredicate,
            LiteralTerm.string('2023-01-01T10:00:00Z')),
      ]);

      final identifiedGraph = (resourceSubject, resourceGraph);

      final indexItem = IndexItemGraphConfig({
        IdxVocab.resource,
        titlePredicate,
        createdPredicate,
        keywordsPredicate, // This property doesn't exist in the resource
      });

      final (indexSubject, indexGraph) = convertToIndexItem(
        testTypeIri,
        identifiedGraph,
        indexItem,
      );

      final indexTriples = indexGraph.triples.toList();

      // Should still include available properties
      expect(indexTriples.any((t) => t.predicate == titlePredicate), isTrue,
          reason: 'Should include available title');

      expect(indexTriples.any((t) => t.predicate == createdPredicate), isTrue,
          reason: 'Should include available creation date');

      // Should include idx:resource reference
      expect(indexTriples.any((t) => t.predicate == IdxVocab.resource), isTrue,
          reason: 'Should include idx:resource reference');

      // Should not include missing properties (keywords)
      expect(indexTriples.any((t) => t.predicate == keywordsPredicate), isFalse,
          reason: 'Should not include missing keywords property');

      expect(indexSubject, equals(resourceSubject));
    });

    test('always includes idx:resource reference', () {
      final resourceSubject = const IriTerm('https://example.org/notes/test');
      final resourceGraph = RdfGraph(triples: [
        Triple(resourceSubject, titlePredicate, LiteralTerm.string('Test')),
        Triple(
            resourceSubject, contentPredicate, LiteralTerm.string('Content')),
      ]);

      final identifiedGraph = (resourceSubject, resourceGraph);

      final indexItem = IndexItemGraphConfig({
        titlePredicate, // Note: not explicitly including IdxVocab.resource
      });

      final (indexSubject, indexGraph) = convertToIndexItem(
        testTypeIri,
        identifiedGraph,
        indexItem,
      );

      final indexTriples = indexGraph.triples.toList();

      // The idx:resource should be automatically added by the converter
      expect(
          indexTriples.any((t) =>
              t.predicate == IdxVocab.resource && t.object == resourceSubject),
          isTrue,
          reason: 'Should automatically add idx:resource reference');

      // Should include the title property
      expect(indexTriples.any((t) => t.predicate == titlePredicate), isTrue,
          reason: 'Should include requested title property');

      // Should not include content (not requested)
      expect(indexTriples.any((t) => t.predicate == contentPredicate), isFalse,
          reason: 'Should not include unrequested content property');
    });

    test('handles empty property set', () {
      final resourceSubject = const IriTerm('https://example.org/notes/empty');
      final resourceGraph = RdfGraph(triples: [
        Triple(resourceSubject, titlePredicate, LiteralTerm.string('Title')),
        Triple(
            resourceSubject, contentPredicate, LiteralTerm.string('Content')),
      ]);

      final identifiedGraph = (resourceSubject, resourceGraph);

      final indexItem = IndexItemGraphConfig({}); // Empty property set

      final (indexSubject, indexGraph) = convertToIndexItem(
        testTypeIri,
        identifiedGraph,
        indexItem,
      );

      final indexTriples = indexGraph.triples.toList();

      // Should only have the idx:resource reference
      expect(indexTriples, hasLength(1),
          reason: 'Should only contain idx:resource reference');

      expect(indexTriples.first.predicate, equals(IdxVocab.resource));
      expect(indexTriples.first.object, equals(resourceSubject));
    });
  });
}
