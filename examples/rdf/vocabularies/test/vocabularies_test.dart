/// Tests for RDF vocabulary examples
library;

import 'package:locorda_rdf_core/core.dart';
import 'package:locorda_rdf_terms_common/foaf.dart';
import 'package:locorda_rdf_terms_common/dc.dart';
import 'package:locorda_rdf_terms_core/rdf.dart';
import 'package:locorda_rdf_terms_schema/schema.dart';
import 'package:test/test.dart';

void main() {
  group('Class-Specific Approach', () {
    test('creates valid RDF graph with FOAF Person', () {
      final personIri = IriTerm('http://example.org/person/jane_doe');

      final graph = RdfGraph.fromTriples([
        Triple(personIri, FoafPerson.rdfType, FoafPerson.classIri),
        Triple(personIri, FoafPerson.name, LiteralTerm.string('Jane Doe')),
        Triple(personIri, FoafPerson.age, LiteralTerm.integer(42)),
      ]);

      expect(graph.triples, hasLength(3));
      expect(graph.findTriples(subject: personIri, predicate: FoafPerson.name),
          hasLength(1));
    });
  });

  group('Direct Vocabulary Approach', () {
    test('creates valid RDF graph mixing vocabularies', () {
      final personIri = IriTerm('http://example.org/person/jane_doe');

      final graph = RdfGraph.fromTriples([
        Triple(personIri, Rdf.type, Foaf.Person),
        Triple(personIri, Foaf.name, LiteralTerm.string('Jane Doe')),
        Triple(personIri, Dc.creator, LiteralTerm.string('System')),
      ]);

      expect(graph.triples, hasLength(3));
      expect(graph.findTriples(predicate: Rdf.type), hasLength(1));
      expect(graph.findTriples(predicate: Dc.creator), hasLength(1));
    });
  });

  group('Cross-Vocabulary Properties', () {
    test('SchemaPerson includes FOAF properties', () {
      final personIri = IriTerm('http://example.org/person/jane_doe');
      final friendIri = IriTerm('http://example.org/person/john_smith');

      final graph = RdfGraph.fromTriples([
        Triple(personIri, SchemaPerson.rdfType, SchemaPerson.classIri),
        Triple(personIri, SchemaPerson.name, LiteralTerm.string('Jane Doe')),
        Triple(personIri, SchemaPerson.foafAge, LiteralTerm.integer(42)),
        Triple(personIri, SchemaPerson.foafKnows, friendIri),
      ]);

      expect(graph.triples, hasLength(4));
      // Verify FOAF properties are accessible through SchemaPerson
      expect(graph.findTriples(predicate: SchemaPerson.foafAge), hasLength(1));
      expect(
          graph.findTriples(predicate: SchemaPerson.foafKnows), hasLength(1));
    });

    test('cross-vocabulary properties have correct IRIs', () {
      // Verify that SchemaPerson.foafAge points to the FOAF vocabulary
      expect(SchemaPerson.foafAge.value, contains('foaf'));
      expect(SchemaPerson.foafKnows.value, contains('foaf'));
    });
  });
}
