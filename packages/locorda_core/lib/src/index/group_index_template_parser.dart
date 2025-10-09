/// Parses GroupIndexTemplate RDF documents back into configuration objects.
///
/// Enables reading existing GroupIndexTemplate documents from storage and
/// generating consistent names/IRIs across installations.
library;

import 'package:locorda_core/src/generated/_index.dart';
import 'package:locorda_core/src/index/index_config_base.dart';
import 'package:locorda_core/src/rdf/rdf_extensions.dart';
import 'package:rdf_core/rdf_core.dart';

/// Parses GroupIndexTemplate RDF to extract grouping configuration.
///
/// This enables consistent IRI generation across installations by
/// reading the canonical RDF representation and reconstructing the
/// configuration used to generate the template's IRI.
class GroupIndexTemplateParser {
  const GroupIndexTemplateParser();

  /// Extracts GroupingProperty list from a GroupIndexTemplate RDF graph.
  ///
  /// Returns null if the graph doesn't contain a valid GroupIndexTemplate.
  /// Throws ArgumentError if the structure is invalid.
  List<GroupingProperty>? parseGroupingProperties(
    RdfGraph graph,
    IriTerm templateResourceIri,
  ) {
    RdfGraphExtensions.empty;
    // Find the GroupingRule
    final groupingRule = graph.findSingleObject<RdfSubject>(
        templateResourceIri, IdxGroupIndexTemplate.groupedBy);

    if (groupingRule == null) {
      return null; // Not a GroupIndexTemplate
    }

    // Extract all GroupingRuleProperty nodes
    final propertyNodes = graph.getMultiValueObjects<RdfSubject>(
        groupingRule, IdxGroupingRule.property);

    if (propertyNodes.isEmpty) {
      throw ArgumentError(
        'GroupingRule has no properties (expected at least one)',
      );
    }

    // Parse each property
    final properties = propertyNodes
        .map((propNode) => _parseGroupingProperty(graph, propNode))
        .toList();

    // Sort by hierarchy level, then by predicate IRI (same as generation)
    properties.sort((a, b) {
      final levelCompare = a.hierarchyLevel.compareTo(b.hierarchyLevel);
      if (levelCompare != 0) return levelCompare;
      return a.predicate.value.compareTo(b.predicate.value);
    });

    return properties;
  }

  /// Parses a single GroupingRuleProperty node.
  GroupingProperty _parseGroupingProperty(RdfGraph graph, RdfSubject propNode) {
    // Extract sourceProperty (required)
    final sourceProperty = graph.singleObject<IriTerm>(
        propNode, IdxGroupingRuleProperty.sourceProperty);

    // Extract hierarchyLevel (defaults to 1 if not present in RDF, even though it's required in RDF)
    // Together with sourceProperty, forms the identification key for the blank node
    final hierarchyLevel = graph
            .findFirstObject<LiteralTerm>(
                propNode, IdxGroupingRuleProperty.hierarchyLevel)
            ?.integerValue ??
        1;

    // Extract missingValue (optional)
    final missingValue = graph
        .findFirstObject<LiteralTerm>(
            propNode, IdxGroupingRuleProperty.missingValue)
        ?.value;

    // Extract transforms (optional RDF list)
    final transformObjects = graph.getListObjects<RdfSubject>(
        propNode, IdxGroupingRuleProperty.transform);

    final transforms = transformObjects
        .map((node) => _parseRegexTransform(graph, node))
        .toList();

    return GroupingProperty(
      sourceProperty,
      hierarchyLevel: hierarchyLevel,
      missingValue: missingValue,
      transforms: transforms,
    );
  }

  /// Parses a RegexTransform node.
  RegexTransform _parseRegexTransform(
      RdfGraph graph, RdfSubject transformNode) {
    // Extract pattern (required)
    final pattern = graph
            .findSingleObject<LiteralTerm>(
                transformNode, IdxRegexTransform.pattern)
            ?.value ??
        (throw ArgumentError('RegexTransform missing required pattern'));

    // Extract replacement (required)
    final replacement = graph
            .findSingleObject<LiteralTerm>(
                transformNode, IdxRegexTransform.replacement)
            ?.value ??
        (throw ArgumentError('RegexTransform missing required replacement'));

    return RegexTransform(pattern, replacement);
  }

  /// Extracts the indexed class IRI from a GroupIndexTemplate.
  IriTerm? parseIndexedClass(RdfGraph graph, IriTerm templateResourceIri) =>
      graph.findSingleObject<IriTerm>(
          templateResourceIri, IdxGroupIndexTemplate.indexesClass);
}
