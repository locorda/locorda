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

  MergeContract(this._classMappings, this._predicateRules);

  PredicateRule? getPredicateRule(IriTerm? typeIri, RdfPredicate propertyIri) {
    if (typeIri != null) {
      final classMapping = getClassMapping(typeIri);
      final rule = classMapping?.getPropertyRule(propertyIri);
      if (rule != null) {
        return rule;
      }
    }
    return _predicateRules[propertyIri];
  }

  late final Set<RdfPredicate> globalIdentifyingPredicates =
      _computeIdentifyingPredicates();

  Set<RdfPredicate> _computeIdentifyingPredicates() => _predicateRules.values
      .where((r) => r.isIdentifying ?? false)
      .map((r) => r.predicateIri)
      .toSet();

  late final Set<RdfPredicate> globalStopTraversalPredicates =
      _computeStopTraversalPredicates();

  Set<RdfPredicate> _computeStopTraversalPredicates() => _predicateRules.values
      .where((r) => r.stopTraversal ?? false)
      .map((r) => r.predicateIri)
      .toSet();

  Set<RdfPredicate> getIdentifyingPredicates(
      RdfGraph graph, BlankNodeTerm blankNode) {
    final predicates = graph.matching(subject: blankNode).predicates;
    final type = graph.findSingleObject(blankNode, Rdf.type);
    // global identifying predicates are "opportunistic", they only apply if
    // they are actually present on the blank node (and not disabled by the class - see below)
    final global = globalIdentifyingPredicates.intersection(predicates);
    if (type != null && _classMappings.containsKey(type)) {
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
    // Lets check if we can identify the blank node via global identifying predicates
    return global;
  }

  ClassMapping? getClassMapping(IriTerm classIri) => _classMappings[classIri];

  PredicateRule? getPredicateMapping(RdfPredicate predicateIri) =>
      _predicateRules[predicateIri];

  static MergeContract fromDocumentMappings(List<DocumentMapping> documents) {
    return createMergeContractFrom(documents);
  }
}
