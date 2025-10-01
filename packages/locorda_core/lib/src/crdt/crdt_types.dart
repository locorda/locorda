import 'package:locorda_core/src/generated/_index.dart';
import 'package:locorda_core/src/hlc_service.dart';
import 'package:locorda_core/src/mapping/framework_iri_generator.dart';
import 'package:locorda_core/src/mapping/identified_blank_node_builder.dart';
import 'package:locorda_core/src/mapping/metadata_generator.dart';
import 'package:locorda_core/src/rdf/rdf_extensions.dart';
import 'package:rdf_core/rdf_core.dart';

/// CRDT type definitions from the architecture specification.
///
/// Defines the state-based CRDT algorithms used for property-level
/// merge strategies as outlined in the crdt-algorithms vocabulary.

/// Base interface for all CRDT types.
abstract interface class CrdtType {
  const CrdtType();

  IriTerm get iri;

  /// Creates the initial metadata triples for a property value addition.
  /// The returned graph may be empty if no metadata is needed.
  ///
  /// Note that you should not simply duplicate the property triples here,
  /// as they are added separately by the merge logic.
  /// Only add true metadata triples needed for the CRDT algorithm like tombstones, counter increments etc.
  RdfGraph initialValue(
      {required IriTerm documentIri,
      required RdfGraph appData,
      required IdentifiedBlankNodes<IriTerm> blankNodes,
      required RdfSubject subject,
      required RdfPredicate predicate,
      required List<RdfObject> values,
      required CrdtMergeContext mergeContext});

  /// Creates the metadata triples for a local property value change.
  /// The returned graph may be empty if no metadata is needed.
  RdfGraph localValueChange({
    required IriTerm documentIri,
    required RdfGraph oldAppData,
    required IdentifiedBlankNodes<IriTerm> oldBlankNodes,
    required RdfSubject oldSubject,
    required RdfGraph newAppData,
    required IdentifiedBlankNodes<IriTerm> newBlankNodes,
    required RdfSubject newSubject,
    required RdfPredicate predicate,
    required List<RdfObject> oldValues,
    required List<RdfObject> newValues,
    required CrdtMergeContext mergeContext,
  });
}

/// Last-Writer-Wins Register for single-value properties.
/// Uses Hybrid Logical Clock for conflict resolution.
class LwwRegister implements CrdtType {
  const LwwRegister();

  @override
  IriTerm get iri => AlgoLWW_Register.classIri;

  @override
  RdfGraph initialValue(
      {required IriTerm documentIri,
      required RdfGraph appData,
      required IdentifiedBlankNodes<IriTerm> blankNodes,
      required RdfSubject subject,
      required RdfPredicate predicate,
      required List<RdfObject> values,
      required CrdtMergeContext mergeContext}) {
    // No metadata needed for adding a LWW Register value
    return RdfGraphExtensions.empty;
  }

  @override
  RdfGraph localValueChange(
      {required IriTerm documentIri,
      required RdfGraph oldAppData,
      required IdentifiedBlankNodes<IriTerm> oldBlankNodes,
      required RdfSubject oldSubject,
      required RdfGraph newAppData,
      required IdentifiedBlankNodes<IriTerm> newBlankNodes,
      required RdfSubject newSubject,
      required RdfPredicate predicate,
      required List<RdfObject> oldValues,
      required List<RdfObject> newValues,
      required CrdtMergeContext mergeContext}) {
    // FIXME: what about the case when newValues is empty and oldValues is not? Do we need metadata for that?
    // No metadata needed for changing a LWW Register value - one will win based on the clock during merge, that is all
    return RdfGraphExtensions.empty;
  }
}

/// First-Writer-Wins Register for immutable properties.
class FwwRegister implements CrdtType {
  const FwwRegister();

  @override
  IriTerm get iri => AlgoFWW_Register.classIri;

  @override
  RdfGraph initialValue(
      {required IriTerm documentIri,
      required RdfGraph appData,
      required IdentifiedBlankNodes<IriTerm> blankNodes,
      required RdfSubject subject,
      required RdfPredicate predicate,
      required List<RdfObject> values,
      required CrdtMergeContext mergeContext}) {
    // No metadata needed for adding a FWW Register value
    return RdfGraphExtensions.empty;
  }

  @override
  RdfGraph localValueChange(
      {required IriTerm documentIri,
      required RdfGraph oldAppData,
      required IdentifiedBlankNodes<IriTerm> oldBlankNodes,
      required RdfSubject oldSubject,
      required RdfGraph newAppData,
      required IdentifiedBlankNodes<IriTerm> newBlankNodes,
      required RdfSubject newSubject,
      required RdfPredicate predicate,
      required List<RdfObject> oldValues,
      required List<RdfObject> newValues,
      required CrdtMergeContext mergeContext}) {
    // FIXME: what about the case when newValues is empty and oldValues is not? Do we need metadata for that?
    // No metadata needed for changing a FWW Register value - one will win based on the clock during merge, that is all
    return RdfGraphExtensions.empty;
  }
}

/// Observed-Remove Set for multi-value properties.
class OrSet implements CrdtType {
  final PhysicalTimestampFactory timestampFactory;

  const OrSet(this.timestampFactory);

  @override
  IriTerm get iri => AlgoOR_Set.classIri;

  @override
  RdfGraph initialValue(
      {required IriTerm documentIri,
      required RdfGraph appData,
      required IdentifiedBlankNodes<IriTerm> blankNodes,
      required RdfSubject subject,
      required RdfPredicate predicate,
      required List<RdfObject> values,
      required CrdtMergeContext mergeContext}) {
    validateBlankNodeValues(values, blankNodes, "Or Set values");
    // No metadata needed for adding a OR Set value
    return RdfGraphExtensions.empty;
  }

  void validateBlankNodeValues(List<RdfObject> values,
      IdentifiedBlankNodes<IriTerm> blankNodes, String lbl) {
    for (final value in values) {
      if (value is BlankNodeTerm) {
        if (blankNodes.getIdentifiedNodes(value) == null) {
          throw ArgumentError('$lbl cannot be unidentifed blank nodes: $value');
        }
      }
    }
  }

  @override
  RdfGraph localValueChange(
      {required IriTerm documentIri,
      required RdfGraph oldAppData,
      required IdentifiedBlankNodes<IriTerm> oldBlankNodes,
      required RdfSubject oldSubject,
      required RdfGraph newAppData,
      required IdentifiedBlankNodes<IriTerm> newBlankNodes,
      required RdfSubject newSubject,
      required RdfPredicate predicate,
      required List<RdfObject> oldValues,
      required List<RdfObject> newValues,
      required CrdtMergeContext mergeContext}) {
    validateBlankNodeValues(newValues, newBlankNodes, "Or Set values");
    validateBlankNodeValues(oldValues, oldBlankNodes, "Old Or Set values");
    // for an OR set, we need to add tombstones for removed values
    final removedValues = oldValues.toSet();
    removedValues.removeAll(newValues);
    if (removedValues.isEmpty) {
      return RdfGraphExtensions.empty;
    }
    final deletionDate = timestampFactory();
    final deletionDateTerm = LiteralTermExtensions.dateTime(deletionDate);
    return removedValues
        .map((value) => mergeContext.metadataGenerator
            .createPropertyValueMetadata(
                documentIri,
                oldBlankNodes,
                newSubject,
                predicate,
                value,
                (metadataSubject) => removedValues
                    .map((rv) => Triple(metadataSubject,
                        RdfStatement.crdtDeletedAt, deletionDateTerm))
                    .toList()))
        .mergeGraphs();
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

  CrdtTypeRegistry.forStandardTypes(
      {required PhysicalTimestampFactory physicalTimestampFactory})
      : this._([
          LwwRegister(),
          FwwRegister(),
          OrSet(physicalTimestampFactory),
        ]);

  /// Get the CRDT type instance for the given IRI - fallbacks to LWW Register.
  CrdtType getType(IriTerm? typeIri,
          {CrdtType fallback = CrdtTypeRegistry.fallback}) =>
      typeIri == null ? fallback : _typesByIri[typeIri] ?? fallback;
}
