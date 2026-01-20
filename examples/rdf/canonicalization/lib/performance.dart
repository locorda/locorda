import 'package:locorda_rdf_canonicalization/canonicalization.dart';
import 'package:locorda_rdf_core/core.dart';

void main() {
  // Canonicalization involves cryptographic operations, so it's
  // important to pre-compute canonical forms for efficient comparison
  // and avoid repeated work.

  final graphs = <RdfGraph>[];

  // Create multiple graphs for comparison
  for (int i = 0; i < 100; i++) {
    final graph = RdfGraph(triples: [
      Triple(BlankNodeTerm(), const IriTerm('http://example.org/id'),
          LiteralTerm.string('$i')),
    ]);
    graphs.add(graph);
  }

  // Wrap into CanonicalRdfGraph. A CanonicalRdfGraph will lazily compute the
  // canonical form on first access and cache it. Subsequent accesses to
  // the canonical form will be O(1).
  final canonicalGraphs = graphs.map((g) => CanonicalRdfGraph(g)).toList();

  // Now comparisons are O(1) string comparisons
  // instead of expensive graph isomorphism
  for (int i = 0; i < canonicalGraphs.length; i++) {
    for (int j = i + 1; j < canonicalGraphs.length; j++) {
      if (canonicalGraphs[i] == canonicalGraphs[j]) {
        print('Graphs $i and $j are isomorphic');
      }
    }
  }
}
