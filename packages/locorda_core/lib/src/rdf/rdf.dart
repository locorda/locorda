import 'package:rdf_core/rdf_core.dart';

typedef Node = (RdfObject node, RdfGraph triples);

class Rdf {
  static const String namespace = 'http://www.w3.org/1999/02/22-rdf-syntax-ns#';
  static const IriTerm type = IriTerm('$namespace#type');
  static const IriTerm subject = IriTerm('$namespace#subject');
  static const IriTerm predicate = IriTerm('$namespace#predicate');
  static const IriTerm object = IriTerm('$namespace#object');
  static const IriTerm first = IriTerm('$namespace#first');
  static const IriTerm nil = IriTerm('$namespace#nil');
  static const IriTerm rest = IriTerm('$namespace#rest');
}

extension RdfGraphExtensions on RdfGraph {
  IriTerm getIdentifier(IriTerm type) {
    final localIdTriple = findTriples(predicate: Rdf.type, object: type).single;
    return localIdTriple.subject as IriTerm;
  }

  RdfObject? findSingleObject(RdfSubject subject, IriTerm predicate) {
    final triple =
        findTriples(subject: subject, predicate: predicate).singleOrNull;
    return triple?.object;
  }

  List<RdfObject> getListObjects(RdfSubject listRoot) {
    return subgraph(listRoot, filter: (t, depth) {
      if (t.predicate == Rdf.rest) {
        if (t.object == Rdf.nil) {
          return TraversalDecision.skip;
        }
        return TraversalDecision.skipButDescend;
      }
      if (t.predicate == Rdf.first) {
        // the actual file
        return TraversalDecision.includeButDontDescend;
      }
      return TraversalDecision.skip;
    }).triples.map((t) => t.object).toList();
  }
}

extension TripleListExtensions on List<Triple> {
  void addRdfList(
      RdfSubject subject, RdfPredicate predicate, List<RdfObject> items) {
    if (items.isEmpty) {
      add(Triple(subject, predicate, Rdf.nil));
      return;
    }

    // Create blank nodes for each list item
    final blankNodes = List.generate(items.length, (index) => BlankNodeTerm());

    for (var i = 0; i < items.length; i++) {
      final currentNode = blankNodes[i];
      final nextNode = (i < items.length - 1) ? blankNodes[i + 1] : Rdf.nil;

      // Add rdf:first triple
      add(Triple(currentNode, Rdf.first, items[i]));

      // Add rdf:rest triple
      add(Triple(currentNode, Rdf.rest, nextNode));
    }

    // Link the head of the list to the subject via the predicate
    add(Triple(subject, predicate, blankNodes.first));
  }

  void addNodes(RdfSubject subject, RdfPredicate predicate, List<Node> nodes) {
    for (final node in nodes) {
      {
        final (objectTerm, graph) = node;
        add(Triple(
          subject,
          predicate,
          objectTerm,
        ));
        addAll(graph.triples);
      }
    }
  }

  RdfGraph toRdfGraph() {
    return RdfGraph.fromTriples(this);
  }
}
