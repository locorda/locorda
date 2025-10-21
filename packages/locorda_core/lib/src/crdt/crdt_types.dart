import 'package:collection/collection.dart';
import 'package:locorda_core/src/generated/_index.dart';
import 'package:locorda_core/src/hlc_service.dart';
import 'package:locorda_core/src/mapping/framework_iri_generator.dart';
import 'package:locorda_core/src/mapping/identified_blank_node_builder.dart';
import 'package:locorda_core/src/mapping/metadata_generator.dart';
import 'package:locorda_core/src/rdf/rdf_extensions.dart';
import 'package:locorda_core/src/sync/data_types.dart';
import 'package:logging/logging.dart';
import 'package:rdf_core/rdf_core.dart';

final _log = Logger('CrdtTypes');

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
  Iterable<RdfObject> values,
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

  MergeResults? remoteMerge({
    required MergeSubject subject,
    required RdfPredicate predicate,
    required OrganizedGraph local,
    required OrganizedGraph remote,
    required CrdtMergeContext mergeContext,
  });
}

class MetadataStatement {
  final MetadataStatementKey key;
  final Map<RdfPredicate, Iterable<RdfObject>> predicateObjectMap;

  const MetadataStatement(this.key, this.predicateObjectMap);

  MetadataStatement merge(MetadataStatement other) {
    assert(key == other.key);
    final mergedMap = <RdfPredicate, Set<RdfObject>>{};
    for (final entry in predicateObjectMap.entries) {
      mergedMap.putIfAbsent(entry.key, () => {}).addAll(entry.value);
    }
    for (final entry in other.predicateObjectMap.entries) {
      mergedMap.putIfAbsent(entry.key, () => {}).addAll(entry.value);
    }
    return MetadataStatement(
        key, mergedMap.map((key, value) => MapEntry(key, value.toList())));
  }
}

sealed class MetadataStatementKey {
  const MetadataStatementKey();

  factory MetadataStatementKey.fromTriple(Triple triple) {
    return TripleMetadataStatement(
        triple.subject, triple.predicate, triple.object);
  }

  factory MetadataStatementKey.fromSubjectPredicateObject(
      RdfSubject subject, RdfPredicate predicate, RdfObject object) {
    return TripleMetadataStatement(subject, predicate, object);
  }

  factory MetadataStatementKey.fromSubjectPredicate(
      RdfSubject subject, RdfPredicate predicate) {
    return SubjectPredicateMetadataStatement(subject, predicate);
  }

  factory MetadataStatementKey.fromSubject(RdfSubject subject) {
    return SubjectMetadataStatement(subject);
  }
}

class SubjectMetadataStatement extends MetadataStatementKey {
  final RdfSubject subject;

  const SubjectMetadataStatement(this.subject);

  @override
  bool operator ==(Object other) {
    if (other is! SubjectMetadataStatement) {
      return false;
    }
    return subject == other.subject;
  }

  @override
  int get hashCode => subject.hashCode;
}

class SubjectPredicateMetadataStatement extends MetadataStatementKey {
  final RdfSubject subject;
  final RdfPredicate predicate;

  const SubjectPredicateMetadataStatement(this.subject, this.predicate);

  @override
  bool operator ==(Object other) {
    if (other is! SubjectPredicateMetadataStatement) {
      return false;
    }
    return subject == other.subject && predicate == other.predicate;
  }

  @override
  int get hashCode => subject.hashCode ^ predicate.hashCode;
}

class TripleMetadataStatement extends MetadataStatementKey {
  final RdfSubject subject;
  final RdfPredicate predicate;
  final RdfObject object;

  const TripleMetadataStatement(this.subject, this.predicate, this.object);

  @override
  bool operator ==(Object other) {
    if (other is! TripleMetadataStatement) {
      return false;
    }
    return subject == other.subject &&
        predicate == other.predicate &&
        object == other.object;
  }

  @override
  int get hashCode => subject.hashCode ^ predicate.hashCode ^ object.hashCode;
}

/// Results from merging all subjects and their properties.
class MergeResults {
  /// All merged triples from all subjects
  final Set<Triple> mergedTriples;

  /// All merged statements (tombstones, etc.)
  final Map<MetadataStatementKey, MetadataStatement> mergedStatements;

  const MergeResults({
    required this.mergedTriples,
    required this.mergedStatements,
  });

  const MergeResults.empty()
      : this(mergedTriples: const {}, mergedStatements: const {});

  static MergeResults join(Iterable<MergeResults> results) =>
      results.fold(MergeResults(mergedTriples: {}, mergedStatements: {}),
          (acc, curr) {
        acc.mergedTriples.addAll(curr.mergedTriples);
        for (final entry in curr.mergedStatements.entries) {
          acc.mergedStatements.update(
            entry.key,
            (existing) => existing.merge(entry.value),
            ifAbsent: () => entry.value,
          );
        }
        return acc;
      });
}

enum _RdfObjectComparison {
  num,
  dateTime,
  //duration,
  string;

  RdfObject _max(Iterable<RdfObject> objects) => switch (this) {
        _RdfObjectComparison.num => objects
            .map((obj) => (obj, obj.numericValue))
            .reduce((a, b) => a.$2 > b.$2 ? a : b)
            .$1,
        _RdfObjectComparison.dateTime => objects
            .map((obj) => (obj, obj.dateTimeValue))
            .reduce((a, b) => a.$2.isAfter(b.$2) ? a : b)
            .$1,
        _RdfObjectComparison.string => objects
            .map((obj) => (obj, obj.stringValue))
            .reduce((a, b) => a.$2.compareTo(b.$2) > 0 ? a : b)
            .$1
      };

  static _RdfObjectComparison forRdfObject(RdfObject obj) {
    if (obj.isNumeric) {
      return _RdfObjectComparison.num;
    } else if (obj.isDateTime) {
      return _RdfObjectComparison.dateTime;
    } else if (obj.hasStringValue) {
      return _RdfObjectComparison.string;
    } else {
      throw StateError('Unsupported value type for comparison in CRDT: $obj');
    }
  }

  static RdfObject max(Iterable<RdfObject> values) {
    if (values.isEmpty) {
      throw StateError('Cannot determine maximum of empty value set');
    }
    final compareGroups = values.map(_RdfObjectComparison.forRdfObject).toSet();
    final compareGroup = compareGroups.length == 1
        ? compareGroups.first
        : _RdfObjectComparison.string;
    return compareGroup._max(values);
  }
}

class GRegister implements CrdtType {
  const GRegister();
  @override
  IriTerm get iri => AlgoG_Register.classIri;
  bool get isSingleValueSupported => true;

  @override
  Metadata localValueChange(
      {required PropertyValueContext? oldPropertyValue,
      required PropertyValueContext newPropertyValue,
      required RdfGraph? oldFrameworkGraph,
      required CrdtMergeContext mergeContext,
      required int physicalClock}) {
    var newValues =
        _toExpandedIdentifiedValues(newPropertyValue, "G Register new values")
            .toSet();
    var oldValues =
        _toExpandedIdentifiedValues(oldPropertyValue, "G Register old values");
    final all = {...newValues, ...oldValues};
    if (all.isEmpty) {
      return noMetadata;
    }
    final result = _RdfObjectComparison.max(all);
    if (!newValues.contains(result)) {
      throw new StateError(
          'G-Register local value change must only add new maximum value. '
          'Old values: $oldValues, New values: $newValues, Merged max: $result');
    }
    // No metadata changes needed
    return noMetadata;
  }

  @override
  Iterable<RdfObject>? remoteMerge(
      {required PropertyValueContext? localPropertyValue,
      required PropertyValueContext? remotePropertyValue,
      required RdfGraph? localFrameworkGraph,
      required RdfGraph? remoteFrameworkGraph,
      required CurrentCrdtClock localClock,
      required CurrentCrdtClock remoteClock,
      required CrdtMergeContext mergeContext}) {
    final all = {
      ..._toExpandedIdentifiedValues(
          localPropertyValue, "G Register local values"),
      ..._toExpandedIdentifiedValues(
          remotePropertyValue, "G Register remote values")
    };
    if (all.isEmpty) {
      return [];
    }
    final result = _RdfObjectComparison.max(all);
    return [result];
  }
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

  @override
  Iterable<RdfObject>? remoteMerge({
    required PropertyValueContext? localPropertyValue,
    required PropertyValueContext? remotePropertyValue,
    required RdfGraph? localFrameworkGraph,
    required RdfGraph? remoteFrameworkGraph,
    required CurrentCrdtClock localClock,
    required CurrentCrdtClock remoteClock,
    required CrdtMergeContext mergeContext,
  }) {
    // LWW-Register: Compare clocks to determine winner
    // Per spec: Check logical time dominance first, then physical time for tie-breaking

    final comparison = _compareClocks(localClock, remoteClock);

    return switch (comparison) {
      ClockComparison.localDominates => localPropertyValue?.values,
      ClockComparison.remoteDominates => remotePropertyValue?.values,
      ClockComparison.concurrent => _physicalTimeTieBreak(
          localPropertyValue?.values,
          remotePropertyValue?.values,
          localClock.physicalTime,
          remoteClock.physicalTime,
        ),
      ClockComparison.identical => handleIdenticalClocks(
          localPropertyValue,
          remotePropertyValue,
        ),
      ClockComparison.bothEmpty => handleBothEmptyClocks(
          localPropertyValue,
          remotePropertyValue,
        ),
    };
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

  @override
  Iterable<RdfObject>? remoteMerge({
    required PropertyValueContext? localPropertyValue,
    required PropertyValueContext? remotePropertyValue,
    required RdfGraph? localFrameworkGraph,
    required RdfGraph? remoteFrameworkGraph,
    required CurrentCrdtClock localClock,
    required CurrentCrdtClock remoteClock,
    required CrdtMergeContext mergeContext,
  }) {
    // Immutable: Value cannot change once set
    // If both have values, they must be identical or there's a conflict
    // Use whichever exists, preferring local if both exist

    final localValues = localPropertyValue?.values;
    final remoteValues = remotePropertyValue?.values;

    // If both have values, they must be identical
    if (localValues != null && remoteValues != null) {
      if (!valuesEqual(localValues, remoteValues)) {
        throw StateError(
          'Immutable value conflict: Local and remote have different values. '
          'Local: $localValues, Remote: $remoteValues. '
          'Immutable properties cannot change once set.',
        );
      }
    }

    // Return whichever exists, preferring local if both exist
    return localValues ?? remoteValues;
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

  @override
  Iterable<RdfObject>? remoteMerge({
    required PropertyValueContext? localPropertyValue,
    required PropertyValueContext? remotePropertyValue,
    required RdfGraph? localFrameworkGraph,
    required RdfGraph? remoteFrameworkGraph,
    required CurrentCrdtClock localClock,
    required CurrentCrdtClock remoteClock,
    required CrdtMergeContext mergeContext,
  }) {
    // FWW-Register: First writer wins
    // Compare clocks - the one with earlier (smaller) logical time wins
    // For concurrent operations, earlier physical time wins

    final comparison = _compareClocks(localClock, remoteClock);

    return switch (comparison) {
      ClockComparison.localDominates =>
        remotePropertyValue?.values, // Remote was first (has smaller clock)
      ClockComparison.remoteDominates =>
        localPropertyValue?.values, // Local was first
      ClockComparison.concurrent => _firstPhysicalTimeTieBreak(
          localPropertyValue?.values,
          remotePropertyValue?.values,
          localClock.physicalTime,
          remoteClock.physicalTime,
        ),
      ClockComparison.identical => handleIdenticalClocks(
          localPropertyValue,
          remotePropertyValue,
        ),
      ClockComparison.bothEmpty => handleBothEmptyClocks(
          localPropertyValue,
          remotePropertyValue,
        ),
    };
  }
}

/// Observed-Remove Set for multi-value properties.
class OrSet implements CrdtType {
  @override
  IriTerm get iri => AlgoOR_Set.classIri;

  bool get isSingleValueSupported => false;

  @override
  Iterable<RdfObject>? remoteMerge({
    required PropertyValueContext? localPropertyValue,
    required PropertyValueContext? remotePropertyValue,
    required RdfGraph? localFrameworkGraph,
    required RdfGraph? remoteFrameworkGraph,
    required CurrentCrdtClock localClock,
    required CurrentCrdtClock remoteClock,
    required CrdtMergeContext mergeContext,
  }) {
    // OR-Set with Add-Wins semantics
    // Per CRDT spec section 3.3: Merge all elements, then filter by tombstones

    // Collect all elements from both sides
    final allElements = <Object>{};

    if (localPropertyValue != null) {
      for (final value in localPropertyValue.values) {
        allElements.add(_identify(value, localPropertyValue.blankNodes));
      }
    }

    if (remotePropertyValue != null) {
      for (final value in remotePropertyValue.values) {
        allElements.add(_identify(value, remotePropertyValue.blankNodes));
      }
    }

    // Filter elements by checking tombstones
    final result = <RdfObject>[];

    for (final identifiedElement in allElements) {
      final elementValues = _expandIdentifiedValues(identifiedElement);

      // Check if element is tombstoned in either local or remote
      var isDeleted = false;

      // Check local tombstones against element presence in remote
      if (remotePropertyValue != null && localFrameworkGraph != null) {
        final remoteCanonicalSubject =
            _getCanonicalSubject(remotePropertyValue);
        final tombstones = _findTombstonesForValue(
          localFrameworkGraph,
          remotePropertyValue.documentIri,
          remoteCanonicalSubject,
          remotePropertyValue.predicate,
          elementValues,
        );

        if (tombstones.isNotEmpty) {
          // Element exists in remote, tombstoned in local
          // Compare remote's add clock vs local's delete clock
          if (_tombstoneWins(remoteClock, localClock)) {
            isDeleted = true;
          }
        }
      }

      // Check remote tombstones against element presence in local
      if (!isDeleted &&
          localPropertyValue != null &&
          remoteFrameworkGraph != null) {
        final localCanonicalSubject = _getCanonicalSubject(localPropertyValue);
        final tombstones = _findTombstonesForValue(
          remoteFrameworkGraph,
          localPropertyValue.documentIri,
          localCanonicalSubject,
          localPropertyValue.predicate,
          elementValues,
        );

        if (tombstones.isNotEmpty) {
          // Element exists in local, tombstoned in remote
          // Compare local's add clock vs remote's delete clock
          if (_tombstoneWins(localClock, remoteClock)) {
            isDeleted = true;
          }
        }
      }

      if (!isDeleted) {
        // Keep this element - add first canonical value
        result.add(elementValues.first);
      }
    }

    return result.isEmpty ? null : result;
  }

  /// Gets canonical subject(s) for tombstone lookup - handles identified blank nodes
  Iterable<RdfSubject> _getCanonicalSubject(PropertyValueContext context) {
    if (context.subject is BlankNodeTerm) {
      final ibn = IdentifiedBlankNodeSubject(
        context.subject as BlankNodeTerm,
        context.blankNodes.getIdentifiedNodes(context.subject as BlankNodeTerm),
      );
      return ibn.identifiers.cast<RdfSubject>();
    }
    return [context.subject];
  }

  /// Finds tombstones in framework graph for a specific value
  Iterable<RdfSubject> _findTombstonesForValue(
    RdfGraph frameworkGraph,
    IriTerm documentIri,
    Iterable<RdfSubject> subjects,
    RdfPredicate predicate,
    Iterable<RdfObject> objects,
  ) {
    if (objects.isEmpty) {
      return [];
    }

    // Find statements that match this triple pattern
    final statementSubjectsForSubject = frameworkGraph
        .findTriples(predicate: RdfStatement.subject, objectIn: subjects)
        .map((t) => t.subject)
        .toSet();

    final statementSubjectsForPredicate = frameworkGraph
        .findTriples(
          predicate: RdfStatement.predicate,
          object: predicate as RdfObject,
        )
        .map((t) => t.subject)
        .toSet();

    final statementSubjects = frameworkGraph
        .findTriples(
          predicate: RdfStatement.object,
          objectIn: objects,
        )
        .map((t) => t.subject)
        .toSet();

    // Intersect to find statements matching full triple
    final matchingStatements = statementSubjectsForSubject
        .intersection(statementSubjectsForPredicate)
        .intersection(statementSubjects);

    // Filter to only tombstones (have crdt:deletedAt)
    return matchingStatements
        .where((stmt) => frameworkGraph
            .findTriples(
              subject: stmt,
              predicate: RdfStatement.crdtDeletedAt,
            )
            .isNotEmpty)
        .toList();
  }

  /// Determines if tombstone wins over element using clock comparison.
  ///
  /// Per spec: Tombstone wins if delete clock dominates add clock,
  /// or if concurrent and delete physical time is greater.
  /// Add-Wins policy: element wins on equal physical times.
  bool _tombstoneWins(
    CurrentCrdtClock addClock,
    CurrentCrdtClock deleteClock,
  ) {
    final comparison = _compareClocks(deleteClock, addClock);

    return switch (comparison) {
      ClockComparison.localDominates => true, // Delete dominates add
      ClockComparison.remoteDominates => false, // Add dominates delete
      ClockComparison.concurrent => deleteClock.physicalTime >
          addClock.physicalTime, // Physical time tie-break
      ClockComparison.identical => false, // Add-Wins on identical
      ClockComparison.bothEmpty => false, // Add-Wins on both empty
    };
  }

  @override
  Metadata localValueChange({
    required PropertyValueContext? oldPropertyValue,
    required PropertyValueContext newPropertyValue,
    required RdfGraph? oldFrameworkGraph,
    required CrdtMergeContext mergeContext,
    required int physicalClock,
  }) {
    _validateBlankNodeValues(
        newPropertyValue.values, newPropertyValue.blankNodes, "Or Set values");
    if (oldPropertyValue == null || oldFrameworkGraph == null) {
      // Initial value - no deletions
      return noMetadata;
    }
    assert(oldPropertyValue.documentIri == newPropertyValue.documentIri);
    assert(oldPropertyValue.predicate == newPropertyValue.predicate);
    _validateBlankNodeValues(oldPropertyValue.values,
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

Object _identify(RdfObject v, IdentifiedBlankNodes<IriTerm> newBlankNodes) {
  if (v is BlankNodeTerm) {
    return IdentifiedBlankNodeSubject(v, newBlankNodes.getIdentifiedNodes(v));
  } else {
    return v;
  }
}

void _validateBlankNodeValues(Iterable<RdfObject> values,
    IdentifiedBlankNodes<IriTerm> blankNodes, String lbl) {
  for (final value in values) {
    if (value is BlankNodeTerm) {
      if (!blankNodes.hasIdentifiedNodes(value)) {
        throw UnidentifiedBlankNodeException(value, lbl);
      }
    }
  }
}

Iterable<RdfObject> _toExpandedIdentifiedValues(
    PropertyValueContext? propertyValue, String lbl) {
  if (propertyValue == null) {
    return [];
  }
  _validateBlankNodeValues(propertyValue.values, propertyValue.blankNodes, lbl);
  final identifiedNewValues = propertyValue.values
      .map((v) => _identify(v, propertyValue.blankNodes))
      .toSet();

  return identifiedNewValues.expand(_expandIdentifiedValues);
}

List<RdfObject> _expandIdentifiedValues(identifiedValue) =>
    switch (identifiedValue) {
      IdentifiedBlankNodeSubject ibn => ibn.identifiers,
      _ => [identifiedValue as RdfObject],
    };

/// Result of comparing two Hybrid Logical Clocks for causality determination.
enum ClockComparison {
  /// Local clock dominates (local is causally after remote)
  localDominates,

  /// Remote clock dominates (remote is causally after local)
  remoteDominates,

  /// Clocks are concurrent (no causal relationship)
  concurrent,

  /// Clocks are identical (no merge needed)
  identical,

  /// Both clocks are empty/missing
  bothEmpty,
}

/// Compares two Hybrid Logical Clocks to determine causality relationship.
///
/// Per CRDT spec section 2.2: Causality Determination
/// - Clock A dominates B if A.logical[i] ≥ B.logical[i] for all i, and A.logical[j] > B.logical[j] for at least one j
/// - If neither dominates based on logical time, they are concurrent
/// - Empty/missing clocks are treated as all zeros
ClockComparison _compareClocks(
  CurrentCrdtClock local,
  CurrentCrdtClock remote,
) {
  // Handle empty clocks (treated as all zeros per spec)
  final localIsEmpty = local.logicalTime == 0 && local.fullClock.isEmpty;
  final remoteIsEmpty = remote.logicalTime == 0 && remote.fullClock.isEmpty;

  if (localIsEmpty && remoteIsEmpty) {
    return ClockComparison.bothEmpty;
  }

  if (localIsEmpty) {
    return ClockComparison.remoteDominates;
  }

  if (remoteIsEmpty) {
    return ClockComparison.localDominates;
  }

  // Build maps of installation -> (logical, physical) for comparison
  final localEntries = <IriTerm, (int logical, int physical)>{};
  final remoteEntries = <IriTerm, (int logical, int physical)>{};

  for (final (subject, graph) in local.fullClock) {
    final logical = graph
            .findSingleObject<LiteralTerm>(subject, CrdtClockEntry.logicalTime)
            ?.integerValue ??
        0;
    final physical = graph
            .findSingleObject<LiteralTerm>(subject, CrdtClockEntry.physicalTime)
            ?.integerValue ??
        0;
    localEntries[subject as IriTerm] = (logical, physical);
  }

  for (final (subject, graph) in remote.fullClock) {
    final logical = graph
            .findSingleObject<LiteralTerm>(subject, CrdtClockEntry.logicalTime)
            ?.integerValue ??
        0;
    final physical = graph
            .findSingleObject<LiteralTerm>(subject, CrdtClockEntry.physicalTime)
            ?.integerValue ??
        0;
    remoteEntries[subject as IriTerm] = (logical, physical);
  }

  // Get all installation IDs from both clocks
  final allInstallations = {...localEntries.keys, ...remoteEntries.keys};

  var localGreater = false;
  var remoteGreater = false;

  for (final installation in allInstallations) {
    final localLogical = localEntries[installation]?.$1 ?? 0;
    final remoteLogical = remoteEntries[installation]?.$1 ?? 0;

    if (localLogical > remoteLogical) {
      localGreater = true;
    } else if (remoteLogical > localLogical) {
      remoteGreater = true;
    }

    // If both have been greater at some point, they're concurrent
    if (localGreater && remoteGreater) {
      return ClockComparison.concurrent;
    }
  }

  if (localGreater) {
    return ClockComparison.localDominates;
  } else if (remoteGreater) {
    return ClockComparison.remoteDominates;
  } else {
    // All logical times are equal - clocks are identical
    return ClockComparison.identical;
  }
}

/// Performs physical time tie-breaking for concurrent operations.
///
/// Per CRDT spec section 2.3: When operations are concurrent (no causal
/// relationship), use physical time for "most recent wins" semantics.
Iterable<RdfObject>? _physicalTimeTieBreak(
  Iterable<RdfObject>? localValues,
  Iterable<RdfObject>? remoteValues,
  int localPhysicalTime,
  int remotePhysicalTime,
) {
  if (localPhysicalTime > remotePhysicalTime) {
    return localValues;
  } else if (remotePhysicalTime > localPhysicalTime) {
    return remoteValues;
  } else {
    // Equal physical times - use local as deterministic tie-breaker
    return localValues;
  }
}

/// Performs physical time tie-breaking for FWW (First-Writer-Wins).
///
/// For FWW, earlier physical time wins (opposite of LWW).
Iterable<RdfObject>? _firstPhysicalTimeTieBreak(
  Iterable<RdfObject>? localValues,
  Iterable<RdfObject>? remoteValues,
  int localPhysicalTime,
  int remotePhysicalTime,
) {
  if (localPhysicalTime < remotePhysicalTime) {
    return localValues; // Local was first
  } else if (remotePhysicalTime < localPhysicalTime) {
    return remoteValues; // Remote was first
  } else {
    // Equal physical times - use local as deterministic tie-breaker
    return localValues;
  }
}

// ============================================================================
// Shared helper functions for CRDT merge operations
// ============================================================================

const _iterableEquality = UnorderedIterableEquality<RdfObject>();

/// Handles the case where local and remote clocks are identical.
/// According to CRDT semantics, identical clocks should only occur with identical values.
/// If values differ, this indicates a system bug or race condition.
///
/// Throws [StateError] if values differ with identical clocks.
Iterable<RdfObject>? handleIdenticalClocks(
  PropertyValueContext? localPropertyValue,
  PropertyValueContext? remotePropertyValue,
) {
  final localValues = localPropertyValue?.values;
  final remoteValues = remotePropertyValue?.values;

  // Check if values actually differ
  if (!valuesEqual(localValues, remoteValues)) {
    throw StateError(
      'Clock conflict detected: Identical clocks with different values. '
      'Local: $localValues, Remote: $remoteValues. '
      'This indicates a system bug or clock synchronization issue.',
    );
  }

  // Values are identical, return either (they're the same)
  return localValues;
}

/// Handles the case where both local and remote clocks are empty.
/// This typically occurs with template resources or uninitialized data.
/// Local value wins by default (spec-compliant), but we log for visibility.
///
/// Logs at info level if values differ.
Iterable<RdfObject>? handleBothEmptyClocks(
  PropertyValueContext? localPropertyValue,
  PropertyValueContext? remotePropertyValue,
) {
  final localValues = localPropertyValue?.values;
  final remoteValues = remotePropertyValue?.values;

  // Log if values differ - this is informational, not an error
  if (!valuesEqual(localValues, remoteValues)) {
    _log.info(
      'Both clocks empty with different values. '
      'Local: $localValues, Remote: $remoteValues. '
      'This may occur with template resources. Local value wins.',
    );
  }

  // Local wins on both empty (spec-compliant)
  return localValues;
}

/// Compares two value iterables for equality using deep comparison.
/// Handles null, empty, and set comparison using [IterableEquality].
///
/// Returns true if both are null, both are empty, or both contain the same elements
/// (order-independent, since we treat them as sets).
bool valuesEqual(Iterable<RdfObject>? a, Iterable<RdfObject>? b) {
  if (a == null && b == null) return true;
  if (a == null || b == null) return false;

  return _iterableEquality.equals(a, b);
}
