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

  Iterable<Node> createPropertyValueMetadata(
          IriTerm documentIri,
          IdTerm<RdfSubject> subject,
          RdfPredicate predicate,
          IdTerm<RdfObject> value,
          List<Triple> Function(RdfSubject) createMetadataTriples) =>
      _createPropertyValueMetadata(documentIri, subject, createMetadataTriples,
          predicate: predicate, value: value);

  Iterable<Node> createPropertyMetadata(
          IriTerm documentIri,
          IdTerm<RdfSubject> subject,
          RdfPredicate predicate,
          List<Triple> Function(RdfSubject) createMetadataTriples) =>
      _createPropertyValueMetadata(
        documentIri,
        subject,
        createMetadataTriples,
        predicate: predicate,
      );

  Iterable<Node> createResourceMetadata(
          IriTerm documentIri,
          IdTerm<RdfSubject> subject,
          List<Triple> Function(RdfSubject) createMetadataTriples) =>
      _createPropertyValueMetadata(documentIri, subject, createMetadataTriples);

  Iterable<Node> _createPropertyValueMetadata(
    IriTerm documentIri,
    IdTerm<RdfSubject> subject,
    List<Triple> Function(RdfSubject) createMetadataTriples, {
    RdfPredicate? predicate,
    IdTerm<RdfObject>? value,
  }) {
    final expandedSubject = subject.localSubjectIris;
    final List<RdfObject>? expandedObject = switch (value?.value) {
      LiteralTerm lt => [lt],
      IriTerm iri => [iri],
      BlankNodeTerm ibn =>
        value!.identifiers ?? (throw UnidentifiedBlankNodeException(ibn)),
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
        final idGraph = RdfGraph.fromTriples(_createIdentifyingTriples(
            temporaryIdSubject, subj, predicate, obj));
        final stmtIri = _frameworkIriGenerator.generateSimpleCanonicalIri(
            documentIri, 'stmt', idGraph.triples,
            labels: {temporaryIdSubject: 'stmt0'});
        final metadataTriples = createMetadataTriples(stmtIri);
        if (metadataTriples.any((m) => m.object is BlankNodeTerm)) {
          throw ArgumentError(
              'Metadata triples must not contain blank node objects: $metadataTriples');
        }
        final graph = RdfGraph.fromTriples([
          ..._createIdentifyingTriples(stmtIri, subj, predicate, obj),
          ...metadataTriples,
        ]);
        return (stmtIri, graph);
      });
    });

    return graphs;
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
}

extension IdTermSubjectExtension on IdTerm<RdfSubject> {
  List<IriTerm> get subjectIris {
    return switch (value) {
      IriTerm iri => [iri],
      BlankNodeTerm bn =>
        identifiers ?? (throw UnidentifiedBlankNodeException(bn)),
    };
  }

  List<IriTerm> get localSubjectIris {
    final result = subjectIris;
    if (!result.every(LocalResourceLocator.isLocalIri)) {
      throw ArgumentError(
          'Resource metadata cannot be created for local IRIs: $result');
    }
    return result;
  }
}

class IdTerm<T extends RdfTerm> {
  final T value;
  final List<IriTerm>? identifiers;

  IdTerm._(this.value, this.identifiers);

  factory IdTerm.create(
      T value, IdentifiedBlankNodes<IriTerm> identifiedBlankNodes) {
    return switch (value) {
      BlankNodeTerm ibn => identifiedBlankNodes.hasIdentifiedNodes(ibn)
          ? IdTerm._(ibn as T, identifiedBlankNodes.getIdentifiedNodes(ibn))
          : IdTerm._(value, null),
      _ => IdTerm._(value, null)
    };
  }
  @override
  String toString() => 'IdentifiedOrTerm($value, $identifiers)';
}
