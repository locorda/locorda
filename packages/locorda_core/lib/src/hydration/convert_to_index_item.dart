import 'package:locorda_core/locorda_core.dart';
import 'package:rdf_core/rdf_core.dart';

/// Convert a resource to an index item using RDF transformation.
///
/// Takes a resource object of type [T] and converts it to an index item
/// of type [I] by filtering the RDF representation to only include
/// the properties specified in [indexItem].
///
/// Returns the converted index item, or throws if the conversion fails.
///
/// The conversion process:
/// 1. Find the primary subject (typed with the resource type)
/// 2. Filter triples to only those with predicates in indexItem.properties
/// 3. Create new RDF graph with filtered triples plus idx:resource type
IdentifiedGraph convertToIndexItem(IriTerm resourceType,
    IdentifiedGraph identifiedGraph, IndexItemGraphConfig indexItem) {
  // Find the primary subject for this resource type
  final (subject, resource) = identifiedGraph;

  // Get all triples for this subject
  final subjectTriples = resource.findTriples(subject: subject);

  // Create new subject for the index item
  final BlankNodeTerm indexItemSubject = BlankNodeTerm();

  // Filter to only the properties specified in the index item config
  final indexItemTriples = subjectTriples
      .where((t) => indexItem.properties.contains(t.predicate))
      .map((t) => Triple(indexItemSubject, t.predicate, t.object))
      .toList()
    ..add(Triple(indexItemSubject, IdxVocab.resource, subject));

  // Convert filtered RDF back to index item type

  return (subject, RdfGraph.fromTriples(indexItemTriples));
}
