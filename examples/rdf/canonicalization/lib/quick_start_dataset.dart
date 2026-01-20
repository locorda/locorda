import 'package:locorda_rdf_canonicalization/canonicalization.dart';
import 'package:locorda_rdf_core/core.dart';

void main() {
  // Actually, RDF Canonicalization is defined for RDF Datasets, so
  // this is how it looks with N-Quads and thus Datasets
  final nquads1 = '''
    _:alice <http://xmlns.com/foaf/0.1/name> "Alice" .
    _:alice <http://xmlns.com/foaf/0.1/knows> _:bob .
    _:bob <http://xmlns.com/foaf/0.1/name> "Bob" .
    _:alice <http://xmlns.com/foaf/0.1/age> "30" <http://example.org/graph1> .
  ''';

  final nquads2 = '''
    _:person1 <http://xmlns.com/foaf/0.1/name> "Alice" .
    _:person1 <http://xmlns.com/foaf/0.1/knows> _:person2 .
    _:person2 <http://xmlns.com/foaf/0.1/name> "Bob" .
    _:person1 <http://xmlns.com/foaf/0.1/age> "30" <http://example.org/graph1> .
  ''';

  // Parse both documents
  final dataset1 = nquads.decode(nquads1);
  final dataset2 = nquads.decode(nquads2);

  // They are different as strings and objects
  print('Strings identical: ${nquads1 == nquads2}'); // false
  print('Objects equal: ${dataset1 == dataset2}'); // false

  // But they are semantically equivalent (isomorphic)
  print('Isomorphic: ${isIsomorphic(dataset1, dataset2)}'); // true

  // Canonicalization produces identical output
  final canonical1 = canonicalize(dataset1);
  final canonical2 = canonicalize(dataset2);
  print('Canonical identical: ${canonical1 == canonical2}'); // true
}
