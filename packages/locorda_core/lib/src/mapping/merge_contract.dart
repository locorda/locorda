import 'package:rdf_core/rdf_core.dart';
import 'create_merge_contract.dart';

class PredicateRule {
  final IriTerm predicateIri;
  final IriTerm? mergeWith;
  final bool stopTraversal;
  final bool isIdentifying;
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
  final Map<IriTerm, PredicateRule> _predicateRules;
  PredicateMapping(this._predicateRules);

  PredicateRule? getPredicateRule(IriTerm propertyIri) =>
      _predicateRules[propertyIri];

  /// Provides read-only access to all predicate rules for merging operations
  Map<IriTerm, PredicateRule> get predicateRules =>
      Map.unmodifiable(_predicateRules);
}

class ClassMapping {
  final IriTerm classIri;
  final Map<IriTerm, PredicateRule> _propertyRules;
  ClassMapping(this.classIri, this._propertyRules);

  PredicateRule? getPropertyRule(IriTerm propertyIri) =>
      _propertyRules[propertyIri];

  /// Provides read-only access to all property rules for merging operations
  Map<IriTerm, PredicateRule> get propertyRules =>
      Map.unmodifiable(_propertyRules);
}

class MergeContract {
  final Map<IriTerm, ClassMapping> _classMappings;
  final Map<IriTerm, PredicateRule> _predicateRules;

  MergeContract(this._classMappings, this._predicateRules);

  PredicateRule? getPredicateRule(IriTerm? typeIri, IriTerm propertyIri) {
    if (typeIri != null) {
      final classMapping = getClassMapping(typeIri);
      final rule = classMapping?.getPropertyRule(propertyIri);
      if (rule != null) {
        return rule;
      }
    }
    return _predicateRules[propertyIri];
  }

  ClassMapping? getClassMapping(IriTerm classIri) => _classMappings[classIri];
  PredicateRule? getPredicateMapping(IriTerm predicateIri) =>
      _predicateRules[predicateIri];

  static MergeContract fromDocumentMappings(List<DocumentMapping> documents) {
    return createMergeContractFrom(documents);
  }
}
