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

/// Base interface for all CRDT types.
abstract interface class CrdtType {
  const CrdtType();

  bool get isSingleValueSupported;

  IriTerm get iri;

  /// Creates the metadata triples for a local property value change.
  /// The returned graph may be empty if no metadata is needed.
  Iterable<Node> localValueChange({
    required PropertyValueContext? oldPropertyValue,
    required PropertyValueContext newPropertyValue,
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
  Iterable<Node> localValueChange({
    required PropertyValueContext? oldPropertyValue,
    required PropertyValueContext newPropertyValue,
    required CrdtMergeContext mergeContext,
    required int physicalClock,
  }) {
    // FIXME: what about the case when newValues is empty and oldValues is not? Do we need metadata for that?
    // No metadata needed for changing a LWW Register value - one will win based on the clock during merge, that is all
    return const <Node>[];
  }
}

class Immutable implements CrdtType {
  const Immutable();

  @override
  IriTerm get iri => AlgoImmutable.classIri;

  bool get isSingleValueSupported => true;

  @override
  Iterable<Node> localValueChange({
    required PropertyValueContext? oldPropertyValue,
    required PropertyValueContext newPropertyValue,
    required CrdtMergeContext mergeContext,
    required int physicalClock,
  }) {
    // No metadata needed for changing a Immutable value - there are not changes allowed.
    return const <Node>[];
  }
}

/// First-Writer-Wins Register for immutable properties.
class FwwRegister implements CrdtType {
  const FwwRegister();

  @override
  IriTerm get iri => AlgoFWW_Register.classIri;

  bool get isSingleValueSupported => true;

  @override
  Iterable<Node> localValueChange({
    required PropertyValueContext? oldPropertyValue,
    required PropertyValueContext newPropertyValue,
    required CrdtMergeContext mergeContext,
    required int physicalClock,
  }) {
    // FIXME: what about the case when newValues is empty and oldValues is not? Do we need metadata for that?
    // No metadata needed for changing a FWW Register value - one will win based on the clock during merge, that is all
    return const <Node>[];
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
  Iterable<Node> localValueChange({
    required PropertyValueContext? oldPropertyValue,
    required PropertyValueContext newPropertyValue,
    required CrdtMergeContext mergeContext,
    required int physicalClock,
  }) {
    validateBlankNodeValues(
        newPropertyValue.values, newPropertyValue.blankNodes, "Or Set values");
    if (oldPropertyValue == null) {
      // Initial value - no deletions
      return const <Node>[];
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
    if (removedValues.isEmpty) {
      return const <Node>[];
    }
    final deletionDate = physicalClock;
    final deletionDateTerm =
        LiteralTermExtensions.dateTimeFromMillisecondsSinceEpoch(deletionDate);
    return removedValues
        .expand((identifiedValue) => switch (identifiedValue) {
              IdentifiedBlankNodeSubject ibn => ibn.identifiers,
              _ => [identifiedValue as RdfObject],
            })
        .expand((value) => mergeContext.metadataGenerator
            .createPropertyValueMetadata(
                newPropertyValue.documentIri,
                IdTerm.create(
                    newPropertyValue.subject, newPropertyValue.blankNodes),
                newPropertyValue.predicate,
                IdTerm.create(value, oldPropertyValue.blankNodes),
                (metadataSubject) => removedValues
                    .map((rv) => Triple(metadataSubject,
                        RdfStatement.crdtDeletedAt, deletionDateTerm))
                    .toList()));
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
