/// Main facade for the CRDT sync system.
library;

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:locorda_core/locorda_core.dart';
import 'package:locorda_core/src/crdt/crdt_types.dart';
import 'package:locorda_core/src/generated/_index.dart';
import 'package:locorda_core/src/hlc_service.dart';
import 'package:locorda_core/src/mapping/framework_iri_generator.dart';
import 'package:locorda_core/src/mapping/identified_blank_node_builder.dart';
import 'package:locorda_core/src/mapping/merge_contract.dart';
import 'package:locorda_core/src/mapping/metadata_generator.dart';
import 'package:locorda_core/src/rdf/rdf_extensions.dart';
import 'package:logging/logging.dart';
import 'package:rdf_core/rdf_core.dart';

final _log = Logger('LocalDocumentMerger');

/// Merges local document changes and generates necessary CRDT metadata.
///
/// Note that this is not for merging local and remote changes, but only
/// for local modifications to a document.
class LocalDocumentMerger {
  final CrdtTypeRegistry _crdtTypeRegistry;
  final FrameworkIriGenerator _iriGenerator;

  late final IdentifiedBlankNodeBuilder _identifiedBlankNodeBuilder =
      IdentifiedBlankNodeBuilder(iriGenerator: _iriGenerator);
  late final MetadataGenerator _metadataGenerator =
      MetadataGenerator(frameworkIriGenerator: _iriGenerator);

  LocalDocumentMerger({
    required FrameworkIriGenerator frameworkIriGenerator,
    required CrdtTypeRegistry crdtTypeRegistry,
  })  : _crdtTypeRegistry = crdtTypeRegistry,
        _iriGenerator = frameworkIriGenerator;

  ({
    IdentifiedBlankNodes<IriTerm> oldBlankNodes,
    IdentifiedBlankNodes<IriTerm> newBlankNodes,
    CrdtMetadataResult metadata,
  }) generateMetadata(
    IriTerm documentIri,
    RdfGraph appData,
    RdfGraph? oldAppData,
    RdfGraph? oldFrameworkGraph,
    MergeContract mergeContract,
    CurrentCrdtClock clock, {
    bool isFrameworkData = false,
    bool computeCanonicalBlankNodes = true,
  }) {
    // 4. Detect property changes between old and new app graphs and generate CRDT metadata
    final appBlankNodes = computeCanonicalBlankNodes
        ? _identifiedBlankNodeBuilder.computeCanonicalBlankNodes(
            documentIri, appData, mergeContract)
        : IdentifiedBlankNodes.empty<IriTerm>();
    final oldAppBlankNodes = (oldAppData == null || !computeCanonicalBlankNodes)
        ? IdentifiedBlankNodes.empty<IriTerm>()
        : _identifiedBlankNodeBuilder.computeCanonicalBlankNodes(
            documentIri, oldAppData, mergeContract);
    final crdtMetadata = _generateCrdtMetadataForChanges(
        documentIri,
        appData,
        appBlankNodes,
        oldAppData,
        oldFrameworkGraph,
        oldAppBlankNodes,
        mergeContract,
        clock,
        isFrameworkData: isFrameworkData);
    return (
      oldBlankNodes: oldAppBlankNodes,
      newBlankNodes: appBlankNodes,
      metadata: crdtMetadata
    );
  }

/**
 * For really simple cases like replacing index shards, we can avoid full CRDT merge
 * and just replace the relevant triples directly, generating necessary metadata.
 */
  Future<RdfGraph> replaceInDocument({
    required IriTerm documentIri,
    required RdfGraph document,
    required MergeContract mergeContract,
    required int physicalClock,
    required Iterable<
            ({
              RdfSubject subject,
              IriTerm subjectTypeIri,
              RdfPredicate predicate,
              Set<RdfObject> newObjects,
            })>
        changes,
  }) async {
    // Build updated document
    final updatedTriples = document.triples.toSet();

    for (final (
          subject: subject,
          subjectTypeIri: subjectTypeIri,
          predicate: predicate,
          newObjects: newObjects,
        ) in changes) {
      // Extract old shards
      final oldPredicateTriples = document.findTriples(
        subject: subject,
        predicate: predicate,
      );

      // If shards haven't changed, return original document
      final oldObjects = oldPredicateTriples.map((t) => t.object).toSet();
      if (SetEquality().equals(oldObjects, newObjects)) {
        break;
      }

      // Determine CRDT algorithm for idx:belongsToIndexShard
      final algorithmIri =
          mergeContract.getEffectiveMergeWith(subjectTypeIri, predicate);
      final crdtType = _crdtTypeRegistry.getType(algorithmIri);

      // Generate CRDT metadata for the shard change
      final metadata = crdtType.localValueChange(
        oldPropertyValue: oldPredicateTriples.isNotEmpty
            ? (
                documentIri: documentIri,
                appData:
                    document, // Using document as appData since shards are framework metadata
                // We are deliberately not supporting blank nodes here at the moment
                blankNodes: IdentifiedBlankNodes.empty<IriTerm>(),
                subject: subject,
                predicate: predicate,
                values: oldObjects,
              )
            : null,
        newPropertyValue: (
          documentIri: documentIri,
          appData: document,
          // We are deliberately not supporting blank nodes here at the moment
          blankNodes: IdentifiedBlankNodes.empty<IriTerm>(),
          subject: subject,
          predicate: predicate,
          values: newObjects,
        ),
        oldFrameworkGraph: document,
        mergeContext: CrdtMergeContext(
          iriGenerator: _iriGenerator,
          metadataGenerator: _metadataGenerator,
        ),
        physicalClock: physicalClock,
      );

      // Remove old shard triples
      oldPredicateTriples.forEach(updatedTriples.remove);

      // Add new shard triples
      updatedTriples
          .addAll(newObjects.map((obj) => Triple(subject, predicate, obj)));

      // Apply metadata changes
      for (final node in metadata.statementsToAdd) {
        updatedTriples
            .addNodes(documentIri, SyncManagedDocument.hasStatement, [node]);
      }
      for (final triple in metadata.triplesToRemove) {
        updatedTriples.remove(triple);
      }
    }

    return RdfGraph.fromTriples(updatedTriples);
  }

  Iterable<IdentifiedRdfSubject> _getIdentifiedSubjects(
          RdfGraph graph, IdentifiedBlankNodes<IriTerm> blankNodes) =>
      graph.subjects.map((subject) {
        if (subject is IriTerm) {
          return IdentifiedIriSubject(subject);
        } else if (subject is BlankNodeTerm) {
          if (blankNodes.hasIdentifiedNodes(subject)) {
            return IdentifiedBlankNodeSubject(
                subject, blankNodes.getIdentifiedNodes(subject));
          }
        }
        return null; // Unidentified blank node
      }).whereType<IdentifiedRdfSubject>();

  CrdtMetadataResult _generateCrdtMetadataForChanges(
      IriTerm documentIri,
      RdfGraph appData,
      IdentifiedBlankNodes<IriTerm> appBlankNodes,
      RdfGraph? oldAppGraph,
      RdfGraph? oldFrameworkGraph,
      IdentifiedBlankNodes<IriTerm> oldAppBlankNodes,
      MergeContract mergeContract,
      CurrentCrdtClock clock,
      {bool isFrameworkData = false}) {
    final statements = <Node>[];
    final triplesToRemove = <Triple>{};
    final propertyChanges = <PropertyChange>[];

    // Get all identifiable subjects from both graphs
    final identifiedSubjects =
        _getIdentifiedSubjects(appData, appBlankNodes).toSet();
    final oldIdentifiedSubjects = oldAppGraph == null
        ? const <IdentifiedRdfSubject>{}
        : _getIdentifiedSubjects(oldAppGraph, oldAppBlankNodes).toSet();

    // Partition subjects into added, deleted, and common
    final addedSubjects = identifiedSubjects.difference(oldIdentifiedSubjects);
    final deletedSubjects =
        oldIdentifiedSubjects.difference(identifiedSubjects);
    final commonSubjects = {
      for (final subject in identifiedSubjects)
        if (oldIdentifiedSubjects.contains(subject))
          subject: oldIdentifiedSubjects.lookup(subject)!
    };
    final context = CrdtMergeContext(
        iriGenerator: _iriGenerator, metadataGenerator: _metadataGenerator);

    // Process deleted subjects - add resource tombstones
    for (final deletedSubject in deletedSubjects) {
      _log.fine('Deleted subject detected: ${deletedSubject.subject} ');
      statements.addAll(_metadataGenerator.createResourceMetadata(
          documentIri,
          IdTerm.create(deletedSubject.subject, oldAppBlankNodes),
          (metadataSubject) => [
                Triple(
                    metadataSubject,
                    SyncManagedDocument.crdtDeletedAt,
                    LiteralTermExtensions.dateTimeFromMillisecondsSinceEpoch(
                        clock.physicalTime))
              ]));
    }

    // Process added subjects - generate initial value metadata
    for (final addedSubject in addedSubjects) {
      final subjectTerm = addedSubject.subject;
      var subjectTriples = appData.matching(subject: subjectTerm);
      final predicates = subjectTriples.predicates;
      final resourceType =
          appData.findSingleObject<IriTerm>(subjectTerm, Rdf.type);

      for (final predicate in predicates) {
        final values =
            subjectTriples.getMultiValueObjects(subjectTerm, predicate);

        // Get CRDT algorithm for this property
        final crdtType =
            _getCrdtAlgorithm(mergeContract, resourceType, predicate);

        // Generate initial value metadata
        final metadataGraph = crdtType.localValueChange(
            oldPropertyValue: null,
            newPropertyValue: (
              documentIri: documentIri,
              appData: appData,
              blankNodes: appBlankNodes,
              subject: subjectTerm,
              predicate: predicate,
              values: values,
            ),
            mergeContext: context,
            physicalClock: clock.physicalTime,
            oldFrameworkGraph: oldFrameworkGraph);

        statements.addAll(metadataGraph.statementsToAdd);
        triplesToRemove.addAll(metadataGraph.triplesToRemove);

        // Record property change using canonical IRI (for identified blank nodes) or IRI
        for (final propertyChangeIri in addedSubject.propertyChangeIris) {
          propertyChanges.add(PropertyChange(
            resourceIri: propertyChangeIri,
            propertyIri: predicate,
            changedAtMs: clock.physicalTime,
            changeLogicalClock: clock.logicalTime,
            isFrameworkProperty: isFrameworkData,
          ));
        }
      }
    }

    // Process common subjects - detect changes and generate change metadata
    for (final entry in commonSubjects.entries) {
      final subjectTerm = entry.key.subject;
      final oldSubjectTerm = entry.value.subject;

      final newTriples = appData.matching(subject: subjectTerm);
      final oldTriples = oldAppGraph!.matching(subject: oldSubjectTerm);

      final newPropertiesByPredicate = newTriples.predicates;
      final oldPropertiesByPredicate = oldTriples.predicates;

      final resourceType =
          appData.findSingleObject<IriTerm>(subjectTerm, Rdf.type);

      // Get all predicates from both old and new
      final allPredicates = {
        ...newPropertiesByPredicate,
        ...oldPropertiesByPredicate
      };

      for (final predicate in allPredicates) {
        final newValues =
            newTriples.getMultiValueObjects(subjectTerm, predicate);
        final oldValues =
            oldTriples.getMultiValueObjects(oldSubjectTerm, predicate);

        // Check if values changed (considering blank node deep equality)
        if (_valuesEqual(oldValues, newValues, oldAppGraph, appData,
            oldAppBlankNodes, appBlankNodes)) {
          continue; // No change
        }

        // Get CRDT algorithm for this property
        final crdtType =
            _getCrdtAlgorithm(mergeContract, resourceType, predicate);

        // Generate change metadata
        final metadataGraph = crdtType.localValueChange(
          oldPropertyValue: (
            documentIri: documentIri,
            appData: oldAppGraph,
            blankNodes: oldAppBlankNodes,
            subject: oldSubjectTerm,
            predicate: predicate,
            values: oldValues,
          ),
          newPropertyValue: (
            documentIri: documentIri,
            appData: appData,
            blankNodes: appBlankNodes,
            subject: subjectTerm,
            predicate: predicate,
            values: newValues,
          ),
          mergeContext: context,
          physicalClock: clock.physicalTime,
          oldFrameworkGraph: oldFrameworkGraph,
        );

        statements.addAll(metadataGraph.statementsToAdd);
        triplesToRemove.addAll(metadataGraph.triplesToRemove);

        // Record property change using canonical IRI (for identified blank nodes) or IRI
        for (final propertyChangeIri in entry.key.propertyChangeIris) {
          propertyChanges.add(PropertyChange(
            resourceIri: propertyChangeIri,
            propertyIri: predicate,
            changedAtMs: clock.physicalTime,
            changeLogicalClock: clock.logicalTime,
            isFrameworkProperty: isFrameworkData,
          ));
        }
        _log.fine('Property change detected on $subjectTerm for $predicate');
      }
    }

    return CrdtMetadataResult(
      statements: statements,
      triplesToRemove: triplesToRemove,
      propertyChanges: propertyChanges,
    );
  }

  CrdtType _getCrdtAlgorithm(MergeContract mergeContract, IriTerm? resourceType,
      RdfPredicate predicate) {
    // Get CRDT algorithm for this property
    final algorithmIri =
        mergeContract.getEffectiveMergeWith(resourceType, predicate);
    return _crdtTypeRegistry.getType(algorithmIri);
  }

  /// Check if two value lists are equal, considering deep equality for blank nodes
  bool _valuesEqual(
      List<RdfTerm> oldValues,
      List<RdfTerm> newValues,
      RdfGraph oldGraph,
      RdfGraph newGraph,
      IdentifiedBlankNodes oldBlankNodes,
      IdentifiedBlankNodes newBlankNodes) {
    if (oldValues.length != newValues.length) {
      return false;
    }

    // For each old value, try to find a matching new value
    final matchedNewValues = <RdfTerm>{};

    for (final oldValue in oldValues) {
      bool found = false;

      for (final newValue in newValues) {
        if (matchedNewValues.contains(newValue)) {
          continue; // Already matched to another old value
        }

        if (_valueEquals(oldValue, newValue, oldGraph, newGraph, oldBlankNodes,
            newBlankNodes)) {
          matchedNewValues.add(newValue);
          found = true;
          break;
        }
      }

      if (!found) {
        return false; // Old value has no match in new values
      }
    }

    return true;
  }

  /// Check if two RDF values are equal, considering deep equality for blank nodes
  bool _valueEquals(
      RdfTerm oldValue,
      RdfTerm newValue,
      RdfGraph oldGraph,
      RdfGraph newGraph,
      IdentifiedBlankNodes oldBlankNodes,
      IdentifiedBlankNodes newBlankNodes) {
    // Simple case: same term
    if (oldValue == newValue) {
      return true;
    }

    // For blank nodes, check if they're identified and equal
    if (oldValue is BlankNodeTerm && newValue is BlankNodeTerm) {
      final oldIdentifiers = oldBlankNodes.hasIdentifiedNodes(oldValue)
          ? oldBlankNodes.getIdentifiedNodes(oldValue)
          : null;
      final newIdentifiers = newBlankNodes.hasIdentifiedNodes(newValue)
          ? newBlankNodes.getIdentifiedNodes(newValue)
          : null;

      // If both are identified, check if they share any identifier
      if (oldIdentifiers != null && newIdentifiers != null) {
        if (oldIdentifiers.any((oldId) => newIdentifiers.contains(oldId))) {
          return true; // Identified as the same blank node
        }
      }

      // For non-identified blank nodes, do deep structural comparison
      return _deepBlankNodeEquals(
          oldValue, newValue, oldGraph, newGraph, oldBlankNodes, newBlankNodes);
    }

    return false;
  }

  /// Perform deep structural comparison of blank nodes
  bool _deepBlankNodeEquals(
      BlankNodeTerm oldBlankNode,
      BlankNodeTerm newBlankNode,
      RdfGraph oldGraph,
      RdfGraph newGraph,
      IdentifiedBlankNodes oldBlankNodes,
      IdentifiedBlankNodes newBlankNodes,
      [Set<BlankNodeTerm>? visited]) {
    visited ??= {};

    // Prevent infinite recursion
    if (visited.contains(oldBlankNode)) {
      return true; // Assume equal if we're in a cycle
    }
    visited.add(oldBlankNode);

    final oldTriples = oldGraph.matching(subject: oldBlankNode);
    final newTriples = newGraph.matching(subject: newBlankNode);

    final oldProps = oldTriples.predicates;
    final newProps = newTriples.predicates;

    // Must have same predicates
    if (!_isEqualSet(oldProps, newProps)) {
      return false;
    }

    // Check each predicate's values
    for (final predicate in oldProps) {
      final oldValues = oldGraph.getMultiValueObjects(oldBlankNode, predicate);
      final newValues = newGraph.getMultiValueObjects(newBlankNode, predicate);

      if (!_valuesEqual(oldValues, newValues, oldGraph, newGraph, oldBlankNodes,
          newBlankNodes)) {
        return false;
      }
    }

    return true;
  }
}

bool _isEqualSet<T>(Set<T> set, Set<T> set2) => SetEquality().equals(set, set2);

/// Result of CRDT metadata generation containing metadata triples and property changes
class CrdtMetadataResult {
  final List<Node> statements;
  final Set<Triple> triplesToRemove;
  final List<PropertyChange> propertyChanges;

  CrdtMetadataResult({
    required this.statements,
    required this.triplesToRemove,
    required this.propertyChanges,
  });
}
