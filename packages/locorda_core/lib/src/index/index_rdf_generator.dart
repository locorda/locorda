/// Generates RDF graphs for index and shard documents from Dart configurations.
///
/// This class translates Dart index configuration objects (FullIndexConfigBase,
/// GroupIndexConfigBase) into RDF graphs that can be saved as ManagedDocuments
/// using LocordaGraphSync.save().
library;

import 'package:locorda_core/src/config/sync_graph_config.dart';
import 'package:locorda_core/src/generated/_index.dart';
import 'package:locorda_core/src/index/index_config_base.dart';
import 'package:locorda_core/src/index/shard_manager.dart';
import 'package:locorda_core/src/mapping/resource_locator.dart';
import 'package:locorda_core/src/rdf/rdf_extensions.dart';
import 'package:locorda_core/src/rdf/xsd.dart';
import 'package:rdf_core/rdf_core.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

/// Generates RDF graphs for index resources.
///
/// Translates Dart index configurations into RDF triples suitable for
/// saving as idx:FullIndex, idx:GroupIndexTemplate, idx:GroupIndex, and idx:Shard resources.
class IndexRdfGenerator {
  /// Mapping file IRI for index merge contracts
  static final IriTerm _indexMappingIri =
      IriTerm('https://w3id.org/solid-crdt-sync/mappings/index-v1');

  /// Mapping file IRI for shard merge contracts
  static final IriTerm _shardMappingIri =
      IriTerm('https://w3id.org/solid-crdt-sync/mappings/shard-v1');

  final ResourceLocator _resourceLocator;
  final ShardManager _shardManager;
  const IndexRdfGenerator(
      {required ResourceLocator resourceLocator,
      required ShardManager shardManager})
      : _resourceLocator = resourceLocator,
        _shardManager = shardManager;

  /// Generates RDF graph for a FullIndex resource.
  ///
  /// The resource will use fragment identifier #it per the ManagedDocument pattern.
  /// Uses LocalResourceLocator to generate internal IRIs.
  ///
  /// Example local ID: `indices/recipe/index-full-abc123/index`
  /// Example IRI: `tag:locorda.org,2025:l:{base64(idx:FullIndex)}:{base64(localId)}#it`
  ///
  /// Example:
  /// ```
  /// final config = FullIndexGraphConfig(
  ///   localName: 'notes',
  ///   itemFetchPolicy: ItemFetchPolicy.prefetch,
  /// );
  /// final resourceType = SchemaNote.classIri;
  /// final installationIri = IriTerm('...');
  ///
  /// final (resourceIri, graph) = generator.generateFullIndex(
  ///   config: config,
  ///   resourceType: resourceType,
  ///   installationIri: installationIri,
  /// );
  /// ```
  RdfGraph generateFullIndex(
      {required FullIndexGraphConfig config,
      required IriTerm resourceIri,
      required IriTerm resourceType,
      required IriTerm installationIri,
      required Iterable<IriTerm> shards}) {
    final triples = <Triple>[];

    // 1. Type declaration
    triples.add(Triple(resourceIri, Rdf.type, IdxFullIndex.classIri));

    // 2. Indexed class
    triples.add(Triple(resourceIri, IdxFullIndex.indexesClass, resourceType));

    // 3. Sharding algorithm with initial single shard
    final shardingAlgorithm = BlankNodeTerm();
    triples.add(
        Triple(resourceIri, IdxFullIndex.shardingAlgorithm, shardingAlgorithm));
    triples.addAll(_generateShardingAlgorithm(
      shardingAlgorithm,
      numberOfShards: 1,
      configVersion: '1_0_0',
    ));

    // 4. Initial empty shard list (will be populated by IndexManager)
    // hasShard triples will be added when first shard is created

    // 5. Population state - set to 'active' for FullIndex (no initial population needed)
    triples.add(Triple(resourceIri, IdxFullIndex.populationState,
        LiteralTerm('active', datatype: Xsd.string)));

    // 6. Reader tracking - this installation reads the index
    triples.add(Triple(resourceIri, IdxFullIndex.readBy, installationIri));

    // 7. Indexed properties (if any)
    if (config.item != null) {
      triples.addNodes(
          resourceIri,
          IdxFullIndex.indexedProperty,
          _generateIndexedProperties(
            config.item!,
            installationIri,
          ));
    }

    // 8. Shards
    triples.addMultiple(resourceIri, IdxFullIndex.hasShard, shards);

    return triples.toRdfGraph();
  }

  IriTerm generateFullIndexIri(FullIndexGraphConfig config) {
    final hash = generateHash(config.localName);

    final localId = 'index-full-$hash/index';

    // Generate internal IRI using ResourceLocator
    return _resourceLocator
        .toIri(ResourceIdentifier(IdxFullIndex.classIri, localId, 'it'));
  }

  /// Generates RDF graph for a GroupIndexTemplate resource.
  ///
  /// The resource will use fragment identifier #it per the ManagedDocument pattern.
  /// Uses LocalResourceLocator to generate internal IRIs.
  RdfGraph generateGroupIndexTemplate({
    required GroupIndexGraphConfig config,
    required IriTerm resourceType,
    required IriTerm resourceIri,
    required IriTerm installationIri,
  }) {
    final triples = <Triple>[];

    // 1. Type declaration
    triples.add(Triple(resourceIri, IdxGroupIndexTemplate.rdfType,
        IdxGroupIndexTemplate.classIri));

    // 2. Indexed class
    triples.add(
        Triple(resourceIri, IdxGroupIndexTemplate.indexesClass, resourceType));

    // 3. Sharding algorithm
    final shardingAlgorithm = BlankNodeTerm();
    triples.add(Triple(resourceIri, IdxGroupIndexTemplate.shardingAlgorithm,
        shardingAlgorithm));
    triples.addAll(_generateShardingAlgorithm(
      shardingAlgorithm,
      numberOfShards: 1,
      configVersion: '1_0_0',
    ));

    // 4. Grouping rule
    final groupingRule = BlankNodeTerm();
    triples.add(
        Triple(resourceIri, IdxGroupIndexTemplate.groupedBy, groupingRule));
    triples.add(Triple(
        groupingRule, IdxGroupingRule.rdfType, IdxGroupingRule.classIri));

    // Add grouping properties
    for (final prop in config.groupingProperties) {
      final groupingRuleProp = BlankNodeTerm();
      triples.add(
          Triple(groupingRule, IdxGroupingRule.property, groupingRuleProp));
      triples.add(Triple(groupingRuleProp, IdxGroupingRuleProperty.rdfType,
          IdxGroupingRuleProperty.classIri));
      triples.add(Triple(groupingRuleProp,
          IdxGroupingRuleProperty.sourceProperty, prop.predicate));
      triples.add(Triple(
          groupingRuleProp,
          IdxGroupingRuleProperty.hierarchyLevel,
          LiteralTerm(prop.hierarchyLevel.toString(), datatype: Xsd.integer)));

      if (prop.missingValue != null) {
        triples.add(Triple(
            groupingRuleProp,
            IdxGroupingRuleProperty.missingValue,
            LiteralTerm(prop.missingValue!, datatype: Xsd.string)));
      }

      if (prop.transforms != null && prop.transforms!.isNotEmpty) {
        // Create RDF list of transform objects
        final transformNodes = prop.transforms!.map((t) {
          final transformNode = BlankNodeTerm();
          triples.add(Triple(transformNode, IdxRegexTransform.rdfType,
              IdxRegexTransform.classIri));
          triples.add(Triple(transformNode, IdxRegexTransform.pattern,
              LiteralTerm(t.pattern, datatype: Xsd.string)));
          triples.add(Triple(transformNode, IdxRegexTransform.replacement,
              LiteralTerm(t.replacement, datatype: Xsd.string)));
          return transformNode as RdfObject;
        }).toList();

        triples.addRdfList(groupingRuleProp, IdxGroupingRuleProperty.transform,
            transformNodes);
      }
    }

    // 5. Reader tracking
    triples.add(
        Triple(resourceIri, IdxGroupIndexTemplate.readBy, installationIri));

    // 6. Indexed properties (if any)
    if (config.item != null) {
      triples.addNodes(
          resourceIri,
          IdxGroupIndexTemplate.indexedProperty,
          _generateIndexedProperties(
            config.item!,
            installationIri,
          ));
    }

    return triples.toRdfGraph();
  }

  IriTerm generateGroupIndexTemplateIri(GroupIndexGraphConfig config) {
    // Generate local ID from config
    final hash = generateHash(config.localName);

    final localId = 'group-template-$hash/template';

    // Generate internal IRI using ResourceLocator
    return _resourceLocator.toIri(
        ResourceIdentifier(IdxGroupIndexTemplate.classIri, localId, 'it'));
  }

  /// Generates RDF graph for an empty Shard resource.
  ///
  /// The resource will use fragment identifier #it per the ManagedDocument pattern.
  /// Uses LocalResourceLocator with local ID: {indexLocalId}/shard-mod-md5-{totalShards}-{shardNumber}-v{version}
  ///
  /// Example shard name: shard-mod-md5-4-0-v1_2_0 means:
  /// - modulo hash sharding
  /// - md5 algorithm
  /// - 4 total shards
  /// - shard number 0
  /// - version 1_2_0
  (IriTerm resourceIri, RdfGraph graph) generateShard({
    required String indexLocalId,
    required int totalShards,
    required int shardNumber,
    required String configVersion,
    required IriTerm indexResourceIri,
  }) {
    IriTerm resourceIri =
        generateShardIri(totalShards, shardNumber, configVersion, indexLocalId);

    return (
      resourceIri,
      RdfGraph.fromTriples([
        // 1. Type declaration
        Triple(resourceIri, IdxShard.rdfType, IdxShard.classIri),
        // 2. Back-link to index
        Triple(resourceIri, IdxShard.isShardOf, indexResourceIri)
        // 3. Empty shard - no containsEntry triples yet
      ])
    );
  }

  IriTerm generateShardIri(int totalShards, int shardNumber,
      String configVersion, String indexLocalId) {
    final shardName = _shardManager.generateShardName(
        totalShards: totalShards,
        shardNumber: shardNumber,
        configVersion: configVersion);
    final shardLocalId = '$indexLocalId/$shardName';

    // Generate internal IRI using ResourceLocator
    final resourceIri = _resourceLocator
        .toIri(ResourceIdentifier(IdxShard.classIri, shardLocalId, 'it'));
    return resourceIri;
  }

  /// Generates sharding algorithm blank node triples.
  List<Triple> _generateShardingAlgorithm(
    BlankNodeTerm algorithmNode, {
    required int numberOfShards,
    required String configVersion,
    int autoScaleThreshold = 1000,
  }) {
    return [
      Triple(algorithmNode, Rdf.type, IdxModuloHashSharding.classIri),
      Triple(algorithmNode, IdxModuloHashSharding.hashAlgorithm,
          LiteralTerm('md5', datatype: Xsd.string)),
      Triple(algorithmNode, IdxModuloHashSharding.numberOfShards,
          LiteralTerm(numberOfShards.toString(), datatype: Xsd.integer)),
      Triple(algorithmNode, IdxModuloHashSharding.configVersion,
          LiteralTerm(configVersion, datatype: Xsd.string)),
      Triple(algorithmNode, IdxModuloHashSharding.autoScaleThreshold,
          LiteralTerm(autoScaleThreshold.toString(), datatype: Xsd.integer)),
    ];
  }

  /// Generates indexed property blank nodes for an index.
  Iterable<Node> _generateIndexedProperties(
    IndexItemConfigBase itemConfig,
    IriTerm installationIri,
  ) {
    return itemConfig.properties.map((property) {
      final indexedProp = BlankNodeTerm();
      return (
        indexedProp,
        RdfGraph.fromTriples([
          Triple(indexedProp, IdxIndexedProperty.rdfType,
              IdxIndexedProperty.classIri),
          Triple(indexedProp, IdxIndexedProperty.trackedProperty, property),
          Triple(indexedProp, IdxIndexedProperty.readBy, installationIri),
        ])
      );
    });
  }

  /// Generates a short hash from a string for use in IRIs.
  ///
  /// Uses first 8 characters of MD5 hash (32-bit hex).
  String generateHash(String input) {
    final bytes = utf8.encode(input);
    final digest = md5.convert(bytes);
    return digest.toString().substring(0, 8);
  }

  /// Returns the merge contract IRI for index resources.
  IriTerm get indexMappingIri => _indexMappingIri;

  /// Returns the merge contract IRI for shard resources.
  IriTerm get shardMappingIri => _shardMappingIri;
}
