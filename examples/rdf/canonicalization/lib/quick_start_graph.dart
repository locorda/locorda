import 'package:locorda_rdf_canonicalization/canonicalization.dart';
import 'package:locorda_rdf_core/core.dart';

void main() {
  // Two Turtle/N-Triples documents with identical semantic content
  // but different blank node labels
  final turtle1 = '''
    _:alice <http://xmlns.com/foaf/0.1/name> "Alice" .
    _:alice <http://xmlns.com/foaf/0.1/knows> _:bob .
    _:bob <http://xmlns.com/foaf/0.1/name> "Bob" .
  ''';

  final turtle2 = '''
    _:person1 <http://xmlns.com/foaf/0.1/name> "Alice" .
    _:person1 <http://xmlns.com/foaf/0.1/knows> _:person2 .
    _:person2 <http://xmlns.com/foaf/0.1/name> "Bob" .
  ''';

  // Parse both documents
  final graph1 = turtle.decode(turtle1);
  final graph2 = turtle.decode(turtle2);

  // They are different as strings and objects
  print('Strings identical: ${turtle1 == turtle2}'); // false
  print('Objects equal: ${graph1 == graph2}'); // false

  // But they are semantically equivalent (isomorphic)
  print('Isomorphic: ${isIsomorphicGraphs(graph1, graph2)}'); // true

  // Canonicalization produces identical output
  final canonical1 = canonicalizeGraph(graph1);
  final canonical2 = canonicalizeGraph(graph2);
  print('Canonical identical: ${canonical1 == canonical2}'); // true
}
