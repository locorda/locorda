import 'package:locorda_core/src/generated/_index.dart';
import 'package:locorda_core/src/mapping/framework_iri_generator.dart';
import 'package:locorda_core/src/mapping/identified_blank_node_builder.dart';
import 'package:locorda_core/src/mapping/metadata_generator.dart';
import 'package:locorda_core/src/rdf/rdf_extensions.dart';
import 'package:rdf_core/rdf_core.dart';

/// CRDT type definitions from the architecture specification.
///
/// Defines the state-based CRDT algorithms used for property-level
/// merge strategies as outlined in the crdt-algorithms vocabulary.

typedef PropertyValueContext = ({
  IriTerm documentIri,
  RdfGraph appData,
  IdentifiedBlankNodes<IriTerm> blankNodes,
  RdfSubject subject,
  RdfPredicate predicate,
  List<RdfObject> values,
});

/// Metadata changes resulting from a CRDT value change operation.
///
/// Contains both statements to add to the framework graph and statements
/// to remove (e.g., outdated tombstones that should be cleaned up).
typedef Metadata = ({
  Iterable<Node> statementsToAdd,
  Iterable<Triple> triplesToRemove,
});

const Metadata noMetadata = (statementsToAdd: [], triplesToRemove: []);
final _coreStatementPredicates = {
  RdfStatement.type,
  RdfStatement.subject,
  RdfStatement.predicate,
  RdfStatement.object,
};

/// Base interface for all CRDT types.
abstract interface class CrdtType {
  const CrdtType();

  bool get isSingleValueSupported;

  IriTerm get iri;

  /// Creates the metadata triples for a local property value change.
  /// The returned [Metadata] contains statements to add and statements to remove.
  ///
  /// [oldFrameworkGraph] provides access to existing framework metadata
  /// (e.g., tombstones) that may need to be cleaned up during this operation.
  Metadata localValueChange({
    required PropertyValueContext? oldPropertyValue,
    required PropertyValueContext newPropertyValue,
    required RdfGraph? oldFrameworkGraph,
    required CrdtMergeContext mergeContext,
    required int physicalClock,
  });
}

/// Last-Writer-Wins Register for single-value properties.
/// Uses Hybrid Logical Clock for conflict resolution.
class LwwRegister implements CrdtType {
  const LwwRegister();

  @override
  IriTerm get iri => AlgoLWW_Register.classIri;

  bool get isSingleValueSupported => true;

  @override
  Metadata localValueChange({
    required PropertyValueContext? oldPropertyValue,
    required PropertyValueContext newPropertyValue,
    required RdfGraph? oldFrameworkGraph,
    required CrdtMergeContext mergeContext,
    required int physicalClock,
  }) {
    // FIXME: what about the case when newValues is empty and oldValues is not? Do we need metadata for that?
    // No metadata needed for changing a LWW Register value - one will win based on the clock during merge, that is all
    return noMetadata;
  }
}

class Immutable implements CrdtType {
  const Immutable();

  @override
  IriTerm get iri => AlgoImmutable.classIri;

  bool get isSingleValueSupported => true;

  @override
  Metadata localValueChange({
    required PropertyValueContext? oldPropertyValue,
    required PropertyValueContext newPropertyValue,
    required RdfGraph? oldFrameworkGraph,
    required CrdtMergeContext mergeContext,
    required int physicalClock,
  }) {
    // No metadata needed for changing a Immutable value - there are not changes allowed.
    return noMetadata;
  }
}

/// First-Writer-Wins Register for immutable properties.
class FwwRegister implements CrdtType {
  const FwwRegister();

  @override
  IriTerm get iri => AlgoFWW_Register.classIri;

  bool get isSingleValueSupported => true;

  @override
  Metadata localValueChange({
    required PropertyValueContext? oldPropertyValue,
    required PropertyValueContext newPropertyValue,
    required RdfGraph? oldFrameworkGraph,
    required CrdtMergeContext mergeContext,
    required int physicalClock,
  }) {
    // FIXME: what about the case when newValues is empty and oldValues is not? Do we need metadata for that?
    // No metadata needed for changing a FWW Register value - one will win based on the clock during merge, that is all
    return noMetadata;
  }
}

/// Observed-Remove Set for multi-value properties.
class OrSet implements CrdtType {
  @override
  IriTerm get iri => AlgoOR_Set.classIri;

  bool get isSingleValueSupported => false;

  void validateBlankNodeValues(List<RdfObject> values,
      IdentifiedBlankNodes<IriTerm> blankNodes, String lbl) {
    for (final value in values) {
      if (value is BlankNodeTerm) {
        if (!blankNodes.hasIdentifiedNodes(value)) {
          throw UnidentifiedBlankNodeException(value, lbl);
        }
      }
    }
  }

  @override
  Metadata localValueChange({
    required PropertyValueContext? oldPropertyValue,
    required PropertyValueContext newPropertyValue,
    required RdfGraph? oldFrameworkGraph,
    required CrdtMergeContext mergeContext,
    required int physicalClock,
  }) {
    validateBlankNodeValues(
        newPropertyValue.values, newPropertyValue.blankNodes, "Or Set values");
    if (oldPropertyValue == null || oldFrameworkGraph == null) {
      // Initial value - no deletions
      return noMetadata;
    }
    assert(oldPropertyValue.documentIri == newPropertyValue.documentIri);
    assert(oldPropertyValue.predicate == newPropertyValue.predicate);
    validateBlankNodeValues(oldPropertyValue.values,
        oldPropertyValue.blankNodes, "Old Or Set values");
    final identifiedNewValues = newPropertyValue.values
        .map((v) => _identify(v, newPropertyValue.blankNodes))
        .toSet();
    final identifiedOldValues = oldPropertyValue.values
        .map((v) => _identify(v, oldPropertyValue.blankNodes))
        .toSet();
    // for an OR set, we need to add tombstones for removed values
    final removedValues = identifiedOldValues.toSet();
    removedValues.removeAll(identifiedNewValues);
    final deletionDate = physicalClock;
    final deletionDateTerm =
        LiteralTermExtensions.dateTimeFromMillisecondsSinceEpoch(deletionDate);
    var newSubject =
        IdTerm.create(newPropertyValue.subject, newPropertyValue.blankNodes);

    final statements =
        removedValues.expand(_expandIdentifiedValues).expand((value) {
      return mergeContext.metadataGenerator.createPropertyValueMetadata(
          newPropertyValue.documentIri,
          newSubject,
          newPropertyValue.predicate,
          IdTerm.create(value, oldPropertyValue.blankNodes),
          (metadataSubject) => removedValues
              .map((rv) => Triple(metadataSubject, RdfStatement.crdtDeletedAt,
                  deletionDateTerm))
              .toList());
    });

    // Find and remove outdated tombstones for re-added values
    final reAddedValues = identifiedNewValues.toSet();
    reAddedValues.removeAll(identifiedOldValues);

    final triplesToRemove = _findTombstonesToRemove(
        reAddedValues.expand(_expandIdentifiedValues).toSet(),
        oldFrameworkGraph,
        newPropertyValue,
        newSubject);

    return (statementsToAdd: statements, triplesToRemove: triplesToRemove);
  }

  /// Finds tombstone statements that should be removed for re-added values.
  ///
  /// When a value is re-added after being deleted, its old tombstone becomes
  /// outdated and should be removed from the framework graph. This implements
  /// the "Add-Wins" semantics by cleaning up obsolete deletion markers.
  ///
  /// Only removes tombstones that have no other predicates besides the standard
  /// RDF reification triples (subject, predicate, object, hasStatement) and
  /// crdt:deletedAt. If a tombstone has additional properties, it is preserved.
  Iterable<Triple> _findTombstonesToRemove(
    Set<RdfObject> reAddedCanonicalValues,
    RdfGraph oldFrameworkGraph,
    PropertyValueContext newPropertyValue,
    IdTerm<RdfSubject> canonicalOldSubject,
  ) {
    return _findStatementTriplesToRemove(
      newPropertyValue.documentIri,
      canonicalOldSubject.localSubjectIris,
      newPropertyValue.predicate,
      reAddedCanonicalValues,
      {RdfStatement.crdtDeletedAt},
      oldFrameworkGraph,
    );
  }

  Object _identify(RdfObject v, IdentifiedBlankNodes<IriTerm> newBlankNodes) {
    if (v is BlankNodeTerm) {
      return IdentifiedBlankNodeSubject(v, newBlankNodes.getIdentifiedNodes(v));
    } else {
      return v;
    }
  }
}

class CrdtMergeContext {
  final FrameworkIriGenerator iriGenerator;
  final MetadataGenerator metadataGenerator;
  CrdtMergeContext(
      {required this.iriGenerator, required this.metadataGenerator});
}

class CrdtTypeRegistry {
  final Map<IriTerm, CrdtType> _typesByIri;
  static const CrdtType fallback = LwwRegister();
  CrdtTypeRegistry._(List<CrdtType> types)
      : _typesByIri = {for (var type in types) type.iri: type};

  CrdtTypeRegistry.forStandardTypes()
      : this._([
          LwwRegister(),
          FwwRegister(),
          Immutable(),
          OrSet(),
        ]);

  /// Get the CRDT type instance for the given IRI - fallbacks to LWW Register.
  CrdtType getType(IriTerm? typeIri,
          {CrdtType fallback = CrdtTypeRegistry.fallback}) =>
      typeIri == null ? fallback : _typesByIri[typeIri] ?? fallback;

  bool hasType(IriTerm algo) => _typesByIri.containsKey(algo);
}

/// Removes specific properties from RDF statement reifications that match
/// the given triple patterns (subjects, predicate, objects).
///
/// This method finds statement reifications (using RDF reification vocabulary)
/// that describe triples matching the provided patterns, then determines whether
/// to remove only specific properties or the entire statement reification.
///
/// **How it works:**
/// 1. Finds all statement reifications matching: `(subjects, predicate, objects)`
/// 2. For each matching statement, checks if it has properties beyond:
///    - Core RDF reification: rdf:type, rdf:subject, rdf:predicate, rdf:object
///    - Properties to delete: specified in [predicatesToDelete]
/// 3. Decision:
///    - If statement has **additional properties**: Remove only [predicatesToDelete]
///    - If statement has **only core + to-delete**: Remove entire statement including
///      the document's `sync:hasStatement` link
///
/// **Use case - OR-Set tombstone cleanup:**
/// When a value is re-added after deletion, its tombstone becomes outdated.
/// This method removes the `crdt:deletedAt` property. If the statement reification
/// has no other custom properties, the entire statement is safely removed.
///
/// **Canonical Subjects:**
/// [subjects] supports multiple subjects to handle the "canonical subject" concept,
/// where identified blank nodes may have multiple equivalent representations.
///
/// **Parameters:**
/// - [documentIri]: The document containing the statements (for hasStatement link)
/// - [subjects]: Subject(s) of the triples to find (supports canonical identification)
/// - [predicate]: Predicate of the triples to find
/// - [objects]: Object(s) of the triples to find
/// - [predicatesToDelete]: Properties to remove from the statement (e.g., crdt:deletedAt)
/// - [frameworkGraph]: The framework metadata graph to search
///
/// **Returns:**
/// Triples to remove from the framework graph - either specific properties only,
/// or the entire statement reification plus its hasStatement link.
///
/// **Example:**
/// ```dart
/// // Remove crdt:deletedAt from statements about `:recipe schema:keywords "spicy"`
/// _removeStatementProperty(
///   documentIri,
///   [:recipe],                        // canonical subjects
///   schema.keywords,                  // predicate
///   ["spicy"],                        // objects
///   {RdfStatement.crdtDeletedAt},    // properties to delete
///   frameworkGraph,
/// );
/// ```
Iterable<Triple> _findStatementTriplesToRemove(
  IriTerm documentIri,
  Iterable<RdfSubject> subjects,
  RdfPredicate predicate,
  Iterable<RdfObject> objects,
  Iterable<IriTerm> predicatesToDelete,
  RdfGraph frameworkGraph,
) {
  if (objects.isEmpty) {
    return [];
  }
  final statementSubjectsForSubject = frameworkGraph
      .findTriples(
        predicate: RdfStatement.subject,
        objectIn: subjects,
      )
      .map((t) => t.subject)
      .toSet();
  final statementSubjectsForPredicate = frameworkGraph
      .findTriples(
          subjectIn: statementSubjectsForSubject,
          predicate: RdfStatement.predicate,
          object: switch (predicate) { IriTerm iri => iri })
      .map((t) => t.subject)
      .toSet();
  final statementSubjects = frameworkGraph
      .findTriples(
          subjectIn: statementSubjectsForPredicate,
          predicate: RdfStatement.object,
          objectIn: objects)
      .map((t) => t.subject)
      .toSet();
  return statementSubjects.expand((subj) {
    final stmt = frameworkGraph.matching(subject: subj);

    final stillNeeded = stmt.predicates.difference(
        {..._coreStatementPredicates, ...predicatesToDelete}).isNotEmpty;

    if (stillNeeded) {
      return frameworkGraph.findTriples(
          subject: subj, predicateIn: predicatesToDelete);
    }
    return [
      Triple(documentIri, SyncManagedDocument.hasStatement, subj),
      ...stmt.triples
    ];
  });
}

List<RdfObject> _expandIdentifiedValues(identifiedValue) =>
    switch (identifiedValue) {
      IdentifiedBlankNodeSubject ibn => ibn.identifiers,
      _ => [identifiedValue as RdfObject],
    };
