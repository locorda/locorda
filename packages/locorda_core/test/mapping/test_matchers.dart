import 'package:locorda_core/src/mapping/merge_contract.dart';
import 'package:test/test.dart';

/// Custom matcher to compare PredicateMergeRule with PredicateRule properties.
///
/// Used for testing merge contract results where PredicateRule instances
/// are converted to PredicateMergeRule with additional metadata.
///
/// Example:
/// ```dart
/// expect(
///   contract.getClassMapping(classIri)!.getPropertyRule(predicateIri),
///   hasRuleProperties(expectedRule, expectedIsPathIdentifying: false),
/// );
/// ```
Matcher hasRuleProperties(PredicateRule expected,
    {bool? expectedIsPathIdentifying}) {
  return isA<PredicateMergeRule>()
      .having(
          (r) => r.predicateIri, 'predicateIri', equals(expected.predicateIri))
      .having((r) => r.mergeWith, 'mergeWith', equals(expected.mergeWith))
      .having((r) => r.stopTraversal, 'stopTraversal',
          equals(expected.stopTraversal))
      .having((r) => r.isIdentifying, 'isIdentifying',
          equals(expected.isIdentifying))
      .having(
          (r) => r.isPathIdentifying,
          'isPathIdentifying',
          equals(expectedIsPathIdentifying ??
              false)); // Default to false (no algorithm specified in test rules)
}

/// Custom matcher to compare PredicateRule with PredicateRule properties.
///
/// Used for testing intermediate results from helper functions that return
/// PredicateRule instances (e.g., collectClassMappings, mergePredicateRuleGroups).
///
/// Example:
/// ```dart
/// final result = collectClassMappings([document]);
/// expect(
///   result[classIri]!.getPropertyRule(predicateIri),
///   matchesRule(expectedRule),
/// );
/// ```
Matcher matchesRule(PredicateRule expected) {
  return isA<PredicateRule>()
      .having(
          (r) => r.predicateIri, 'predicateIri', equals(expected.predicateIri))
      .having((r) => r.mergeWith, 'mergeWith', equals(expected.mergeWith))
      .having((r) => r.stopTraversal, 'stopTraversal',
          equals(expected.stopTraversal))
      .having((r) => r.isIdentifying, 'isIdentifying',
          equals(expected.isIdentifying));
}
