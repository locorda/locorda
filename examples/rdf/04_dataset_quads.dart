import 'package:locorda_rdf_core/core.dart';

void main() {
  // Create quads with graph context
  final alice = const IriTerm('http://example.org/alice');
  final bob = const IriTerm('http://example.org/bob');
  final foafName = const IriTerm('http://xmlns.com/foaf/0.1/name');
  final foafKnows = const IriTerm('http://xmlns.com/foaf/0.1/knows');
  final peopleGraph = const IriTerm('http://example.org/graphs/people');

  final quads = [
    Quad(alice, foafName, LiteralTerm.string('Alice')), // default graph
    Quad(alice, foafKnows, bob, peopleGraph), // named graph
    Quad(bob, foafName, LiteralTerm.string('Bob'), peopleGraph), // named graph
  ];

  // Create dataset from quads
  final dataset = RdfDataset.fromQuads(quads);

  // Encode to N-Quads
  final nquadsData = nquads.encode(dataset);
  print('N-Quads output:');
  print(nquadsData);

  // Decode N-Quads back to dataset
  final decodedDataset = nquads.decode(nquadsData);

  // Access default and named graphs
  print(
      'Default graph has ${decodedDataset.defaultGraph.triples.length} triples');
  print('Dataset has ${decodedDataset.namedGraphs.length} named graphs');

  for (final namedGraph in decodedDataset.namedGraphs) {
    print(
        'Named graph ${namedGraph.name} has ${namedGraph.graph.triples.length} triples');
  }
}
