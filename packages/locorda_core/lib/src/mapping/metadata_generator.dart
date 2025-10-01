import 'package:locorda_core/src/generated/_index.dart';
import 'package:locorda_core/src/mapping/framework_iri_generator.dart';
import 'package:locorda_core/src/mapping/identified_blank_node_builder.dart';
import 'package:locorda_core/src/mapping/resource_locator.dart';
import 'package:locorda_core/src/rdf/rdf_extensions.dart';
import 'package:rdf_core/rdf_core.dart';

class MetadataGenerator {
  final FrameworkIriGenerator _frameworkIriGenerator;

  MetadataGenerator({required FrameworkIriGenerator frameworkIriGenerator})
      : _frameworkIriGenerator = frameworkIriGenerator;

  RdfGraph createPropertyValueMetadata(
          IriTerm documentIri,
          IdentifiedBlankNodes<IriTerm> identifiedBlankNodes,
          RdfSubject subject,
          RdfPredicate predicate,
          RdfObject value,
          List<Triple> Function(RdfSubject) createMetadataTriples) =>
      _createPropertyValueMetadata(
          documentIri, identifiedBlankNodes, subject, createMetadataTriples,
          predicate: predicate, value: value);

  RdfGraph createPropertyMetadata(
          IriTerm documentIri,
          IdentifiedBlankNodes<IriTerm> identifiedBlankNodes,
          RdfSubject subject,
          RdfPredicate predicate,
          List<Triple> Function(RdfSubject) createMetadataTriples) =>
      _createPropertyValueMetadata(
        documentIri,
        identifiedBlankNodes,
        subject,
        createMetadataTriples,
        predicate: predicate,
      );

  RdfGraph createResourceMetadata(
          IriTerm documentIri,
          IdentifiedBlankNodes<IriTerm> identifiedBlankNodes,
          RdfSubject subject,
          List<Triple> Function(RdfSubject) createMetadataTriples) =>
      _createPropertyValueMetadata(
          documentIri, identifiedBlankNodes, subject, createMetadataTriples);

  RdfGraph _createPropertyValueMetadata(
    IriTerm documentIri,
    IdentifiedBlankNodes<IriTerm> identifiedBlankNodes,
    RdfSubject subject,
    List<Triple> Function(RdfSubject) createMetadataTriples, {
    RdfPredicate? predicate,
    RdfObject? value,
  }) {
    final expandedSubject =
        expandLocalSubjectIris(subject, identifiedBlankNodes);
    final List<RdfObject>? expandedObject = switch (value) {
      LiteralTerm lt => [lt],
      IriTerm iri => [iri],
      BlankNodeTerm ibn => expandLocalSubjectIris(ibn, identifiedBlankNodes),
      null => null
    };

    /*
    Blank nodes can be represented by multiple IRIs, so we need to create
    all combinations of subject IRIs and object IRIs (if applicable), this
    will cause us to create multiple metadata graphs.
    */
    final temporaryIdSubject = BlankNodeTerm();
    final graphs = expandedSubject.expand((subj) {
      return (expandedObject?.cast<RdfObject?>() ?? [null]).map((obj) {
        final idGraph = RdfGraph.fromTriples(
            _createIdentifyingTriples(temporaryIdSubject, subj, predicate, obj));
        final stmtIri = _frameworkIriGenerator.generateSimpleCanonicalIri(
            documentIri, 'stmt', idGraph.triples,
            labels: {temporaryIdSubject: 'stmt0'});
        final metadataTriples = createMetadataTriples(stmtIri);
        if (metadataTriples.any((m) =>
            m.object is BlankNodeTerm &&
            identifiedBlankNodes.isNotIdentified(m.object as BlankNodeTerm))) {
          throw ArgumentError(
              'Metadata triples must not contain blank node objects: $metadataTriples');
        }
        final graph = RdfGraph.fromTriples([
          Triple(documentIri, SyncManagedDocument.hasStatement, stmtIri),
          ..._createIdentifyingTriples(stmtIri, subj, predicate, obj),
          ...metadataTriples,
        ]);
        return graph;
      });
    });

    return graphs.mergeGraphs();
  }

  List<Triple> _createIdentifyingTriples(RdfSubject idSubject, IriTerm subj,
      RdfPredicate? predicate, RdfObject? obj) {
    return [
      Triple(idSubject, RdfStatement.subject, subj),
      if (predicate != null)
        Triple(idSubject, RdfStatement.predicate,
            switch (predicate) { IriTerm iri => iri }),
      if (obj != null) Triple(idSubject, RdfStatement.object, obj),
    ];
  }

  List<IriTerm> expandLocalSubjectIris(
      RdfSubject subject, IdentifiedBlankNodes<IriTerm> identifiedBlankNodes) {
    final result = switch (subject) {
      IriTerm iri => [iri],
      BlankNodeTerm ibn => identifiedBlankNodes.getIdentifiedNodes(ibn) ??
          (throw ArgumentError(
              'No IRI found for blank node $ibn - unidentified blank nodes are not supported here.')),
    };
    if (!result.every(LocalResourceLocator.isLocalIri)) {
      throw ArgumentError(
          'Resource metadata cannot be created for local IRIs: $result');
    }
    return result;
  }
}
