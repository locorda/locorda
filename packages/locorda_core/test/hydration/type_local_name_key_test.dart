import 'package:test/test.dart';
import 'package:rdf_core/rdf_core.dart';
import 'package:locorda_core/src/hydration/type_local_name_key.dart';

void main() {
  group('TypeOrIndexKey', () {
    test('should create key with type IRI and index name', () {
      final typeIri = IriTerm('https://example.com/TestDocument');
      final key = TypeOrIndexKey(typeIri, 'test');

      expect(key.typeIri, equals(typeIri));
      expect(key.indexName, equals('test'));
    });

    test('should implement equality correctly', () {
      final typeIri1 = IriTerm('https://example.com/TestDocument');
      final typeIri2 = IriTerm('https://example.com/TestDocument');
      final typeIri3 = IriTerm('https://example.com/OtherDocument');

      final key1 = TypeOrIndexKey(typeIri1, 'test');
      final key2 = TypeOrIndexKey(typeIri2, 'test');
      final key3 = TypeOrIndexKey(typeIri3, 'test');
      final key4 = TypeOrIndexKey(typeIri1, 'other');

      expect(key1, equals(key2));
      expect(key1, isNot(equals(key3)));
      expect(key1, isNot(equals(key4)));
    });

    test('should implement hashCode correctly', () {
      final typeIri1 = IriTerm('https://example.com/TestDocument');
      final typeIri2 = IriTerm('https://example.com/TestDocument');
      final typeIri3 = IriTerm('https://example.com/OtherDocument');

      final key1 = TypeOrIndexKey(typeIri1, 'test');
      final key2 = TypeOrIndexKey(typeIri2, 'test');
      final key3 = TypeOrIndexKey(typeIri3, 'test');

      expect(key1.hashCode, equals(key2.hashCode));
      expect(key1.hashCode, isNot(equals(key3.hashCode)));
    });

    test('should have meaningful toString', () {
      final typeIri = IriTerm('https://example.com/TestDocument');
      final key = TypeOrIndexKey(typeIri, 'test');

      expect(key.toString(), contains('TypeOrIndexKey'));
      expect(key.toString(), contains('https://example.com/TestDocument'));
      expect(key.toString(), contains('test'));
    });
  });
}
