import 'package:locorda_core/src/generated/rdf.dart';
import 'package:locorda_core/src/rdf/rdf_extensions.dart';
import 'package:logging/logging.dart';
import 'package:rdf_core/rdf_core.dart';

import 'create_merge_contract.dart';

final _log = Logger('merge_contract');

class PredicateRule {
  final RdfPredicate predicateIri;
  final IriTerm? mergeWith;
  final bool? stopTraversal;
  final bool? isIdentifying;
  PredicateRule(
      {required this.predicateIri,
      required this.mergeWith,
      required this.stopTraversal,
      required this.isIdentifying});

  PredicateRule withOptions({
    IriTerm? mergeWith,
    bool? stopTraversal,
    bool? isIdentifying,
  }) {
    var newMergeWith = mergeWith ?? this.mergeWith;
    var newStopTraversal = stopTraversal ?? this.stopTraversal;
    var newIsIdentifying = isIdentifying ?? this.isIdentifying;
    if (newStopTraversal == this.stopTraversal &&
        newIsIdentifying == this.isIdentifying &&
        newMergeWith == this.mergeWith) {
      return this;
    }
    return PredicateRule(
      predicateIri: predicateIri,
      mergeWith: newMergeWith,
      stopTraversal: newStopTraversal,
      isIdentifying: newIsIdentifying,
    );
  }

  PredicateRule withFallback(PredicateRule? fallbackRule) {
    final newStopTraversal = stopTraversal ?? fallbackRule?.stopTraversal;
    final newIsIdentifying = isIdentifying ?? fallbackRule?.isIdentifying;
    final newMergeWith = mergeWith ?? fallbackRule?.mergeWith;

    return withOptions(
        stopTraversal: newStopTraversal,
        isIdentifying: newIsIdentifying,
        mergeWith: newMergeWith);
  }
}

class DocumentMapping {
  final RdfSubject documentIri;
  final List<DocumentMapping> imports;
  final Map<IriTerm, ClassMapping> classMappings;
  final List<PredicateMapping> predicateMappings;

  DocumentMapping(
      {required this.documentIri,
      required this.imports,
      required this.classMappings,
      required this.predicateMappings});
}

class PredicateMapping {
  final Map<RdfPredicate, PredicateRule> _predicateRules;
  PredicateMapping(this._predicateRules);

  PredicateRule? getPredicateRule(RdfPredicate propertyIri) =>
      _predicateRules[propertyIri];

  /// Provides read-only access to all predicate rules for merging operations
  Map<RdfPredicate, PredicateRule> get predicateRules =>
      Map.unmodifiable(_predicateRules);
}

class ClassMapping {
  final IriTerm classIri;
  final Map<RdfPredicate, PredicateRule> _propertyRules;
  ClassMapping(this.classIri, this._propertyRules);

  PredicateRule? getPropertyRule(RdfPredicate propertyIri) =>
      _propertyRules[propertyIri];

  /// Provides read-only access to all property rules for merging operations
  Map<RdfPredicate, PredicateRule> get propertyRules =>
      Map.unmodifiable(_propertyRules);

  late final Set<RdfPredicate> identifyingPredicates =
      _computeIdentifyingPredicates();

  Set<RdfPredicate> _computeIdentifyingPredicates() => _propertyRules.values
      .where((r) => r.isIdentifying ?? false)
      .map((r) => r.predicateIri)
      .toSet();

  /// Predicates that are explicitly marked as non-identifying, this is useful to
  /// override global identifying predicates in certain class contexts.
  late final Set<RdfPredicate> nonIdentifyingPredicates =
      _computeNonIdentifyingPredicates();

  Set<RdfPredicate> _computeNonIdentifyingPredicates() => _propertyRules.values
      .where((r) => r.isIdentifying == false)
      .map((r) => r.predicateIri)
      .toSet();

  late final Set<RdfPredicate> stopTraversalPredicates =
      _computeStopTraversalPredicates();

  Set<RdfPredicate> _computeStopTraversalPredicates() => _propertyRules.values
      .where((r) => r.stopTraversal ?? false)
      .map((r) => r.predicateIri)
      .toSet();
}

class MergeContract {
  final Map<IriTerm, ClassMapping> _classMappings;
  final Map<RdfPredicate, PredicateRule> _predicateRules;
  late final Map<RdfPredicate, List<ClassMapping>> _classMappingsByPredicate =
      _classMappings.entries.fold({}, (r, e) {
    for (final p in e.value.propertyRules.keys) {
      r.putIfAbsent(p, () => []).add(e.value);
    }
    return r;
  });
  MergeContract(this._classMappings, this._predicateRules);

  PredicateRule? getEffectivePredicateRule(
      IriTerm? typeIri, RdfPredicate propertyIri) {
    final globalRule = _predicateRules[propertyIri];
    if (typeIri != null) {
      final classMapping = getClassMapping(typeIri);
      final rule = classMapping?.getPropertyRule(propertyIri);
      if (rule != null) {
        return rule.withFallback(globalRule);
      }
      return globalRule;
    }
    // ok, we do not have a type iri and no global rule.
    // This means we can infer the type from the property
    final inferredTypes = _classMappingsByPredicate[propertyIri] ?? [];
    if (inferredTypes.length == 1) {
      final classMapping = inferredTypes.single;
      final rule = classMapping.getPropertyRule(propertyIri);
      if (rule != null) {
        _log.fine(
            'Inferred type $inferredTypes for property $propertyIri to apply class-specific merge rule.');
        return rule.withFallback(globalRule);
      }
    } else if (inferredTypes.length > 1) {
      _log.warning(
          'Cannot infer unique type for property $propertyIri, found multiple candidate types: $inferredTypes. ${globalRule == null ? 'No merge rule available. ' : 'Using global merge rule of this predicate.'}');
    } else {
      _log.fine(
          'No class-specific merge rule found for property $propertyIri. ${globalRule == null ? 'No merge rule available. ' : 'Using global merge rule of this predicate.'}.');
    }
    return globalRule;
  }

  late final Set<RdfPredicate> _globalIdentifyingPredicates =
      _computeIdentifyingPredicates();

  Set<RdfPredicate> _computeIdentifyingPredicates() => _predicateRules.values
      .where((r) => r.isIdentifying ?? false)
      .map((r) => r.predicateIri)
      .toSet();

  Set<RdfPredicate> getIdentifyingPredicates(
      RdfGraph graph, BlankNodeTerm blankNode) {
    final predicates = graph.matching(subject: blankNode).predicates;
    final type = graph.findSingleObject(blankNode, Rdf.type);
    // global identifying predicates are "opportunistic", they only apply if
    // they are actually present on the blank node (and not disabled by the class - see below)
    final global = _globalIdentifyingPredicates.intersection(predicates);
    if (type == null) {
      return predicates
          .where((predicateIri) =>
              getEffectivePredicateRule(null, predicateIri)?.isIdentifying ??
              false)
          .toSet();
    }

    if (!_classMappings.containsKey(type)) {
      // class was specified, but has no mapping - fall back to global only
      return global;
    }

    final classMapping = _classMappings[type];
    final identifyingPredicates =
        classMapping?.identifyingPredicates ?? const <IriTerm>{};
    final nonIdentifyingPredicates =
        classMapping?.nonIdentifyingPredicates ?? const {};
    final effectiveIdentifyingPredicates = <RdfPredicate>{
      ...global,
      ...identifyingPredicates
    }..removeAll(nonIdentifyingPredicates);

    if (effectiveIdentifyingPredicates.isNotEmpty) {
      final missing = effectiveIdentifyingPredicates.difference(predicates);
      // The identifying predicates of the class are required
      if (missing.isEmpty) {
        // great - all identifying predicates are defined
        return effectiveIdentifyingPredicates;
      }

      _log.warning(
          "Found identifiable Blank node ${blankNode} of type ${type} that cannot be identified because it is missing properties ${missing.join(' | ')}.");
      return const {};
    }
    // A class was specified and it is configured, but it had no identifying properties
    // and no global ones are applicable either
    return const {};
  }

  ClassMapping? getClassMapping(IriTerm classIri) => _classMappings[classIri];

  PredicateRule? getPredicateMapping(RdfPredicate predicateIri) =>
      _predicateRules[predicateIri];

  static MergeContract fromDocumentMappings(List<DocumentMapping> documents) {
    return createMergeContractFrom(documents);
  }

  bool isStopTraversalPredicate(IriTerm? type, RdfPredicate predicate) {
    return getEffectivePredicateRule(type, predicate)?.stopTraversal ?? false;
  }
}
