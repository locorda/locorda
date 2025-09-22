import 'package:rdf_core/rdf_core.dart';

class Rdf {
  static const IriTerm type =
      IriTerm.prevalidated('http://www.w3.org/1999/02/22-rdf-syntax-ns#type');

  static IriTerm getIdentifier(RdfGraph graph, IriTerm type) {
    final localIdTriple =
        graph.findTriples(predicate: Rdf.type, object: type).single;
    return localIdTriple.subject as IriTerm;
  }
}
