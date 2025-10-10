/// Determines which index shards a resource belongs to (read-only operations).
///
/// This class is responsible for calculating shard membership based on resource
/// type and properties, without creating any documents. Shard/GroupIndex creation
/// is handled by IndexManager after this determination is made.
library;

import 'package:locorda_core/locorda_core.dart';
import 'package:locorda_core/src/generated/_index.dart';
import 'package:locorda_core/src/index/group_key_generator.dart';
import 'package:locorda_core/src/index/index_rdf_generator.dart';
import 'package:locorda_core/src/index/shard_manager.dart';
import 'package:locorda_core/src/rdf/rdf_extensions.dart';
import 'package:logging/logging.dart';
import 'package:rdf_core/rdf_core.dart';

final _log = Logger('ShardDeterminer');

/// Information about a missing GroupIndex that needs to be created.
class MissingGroupIndex {
  final GroupIndexGraphConfig config;
  final IriTerm typeIri;
  final IriTerm templateIri;
  final String groupKey;
  final IriTerm groupIndexIri;

  const MissingGroupIndex({
    required this.config,
    required this.typeIri,
    required this.templateIri,
    required this.groupKey,
    required this.groupIndexIri,
  });

  @override
  String toString() =>
      'MissingGroupIndex(groupKey: $groupKey, groupIndexIri: $groupIndexIri)';
}

/// Result of shard determination including shards and missing GroupIndices.
class ShardDeterminationResult {
  final Set<IriTerm> shards;
  final List<MissingGroupIndex> missingGroupIndices;

  const ShardDeterminationResult({
    required this.shards,
    required this.missingGroupIndices,
  });

  bool get hasMissingGroupIndices => missingGroupIndices.isNotEmpty;
}

/// Determines which index shards a resource belongs to (read-only).
///
/// This class extracts the read-only shard determination logic from IndexManager,
/// allowing both CrdtDocumentManager and IndexManager to use it without circular
/// dependencies. It does NOT create any documents - only calculates which shards
/// a resource should belong to and reports which GroupIndices are missing.
class ShardDeterminer {
  final Storage _storage;
  final IndexRdfGenerator _rdfGenerator;
  final ShardManager _shardManager;
  final SyncGraphConfig _config;

  const ShardDeterminer({
    required Storage storage,
    required IndexRdfGenerator rdfGenerator,
    required ShardManager shardManager,
    required SyncGraphConfig config,
  })  : _storage = storage,
        _rdfGenerator = rdfGenerator,
        _shardManager = shardManager,
        _config = config;

  /// Determines which shards a resource of the given type should belong to.
  ///
  /// According to LOCORDA-SPECIFICATION.md section 6.4 "Resource Creation Workflow":
  /// 1. Identify all matching index shards based on resource type
  /// 2. For FullIndex: Calculate shard based on resource IRI hash
  /// 3. For GroupIndexTemplate: Determine group membership using GroupKeyGenerator,
  ///    report missing GroupIndex instances, then calculate shard per group
  ///
  /// This method is READ-ONLY - it does not create any documents. Missing GroupIndices
  /// are reported via the result object so the caller can create them.
  ///
  /// Parameters:
  /// - [type]: The RDF type of the resource (e.g., schema:Recipe)
  /// - [resourceIri]: The IRI of the resource being indexed
  /// - [internalAppData]: The resource's semantic data (for group determination)
  ///
  /// Returns: ShardDeterminationResult with shards and missing GroupIndices
  Future<ShardDeterminationResult> determineShards(
    IriTerm type,
    IriTerm resourceIri,
    RdfGraph internalAppData,
  ) async {
    final shards = <IriTerm>{};
    final missingGroupIndices = <MissingGroupIndex>[];

    // Get all index configurations for this resource type from config
    final resourceConfig = _getResourceConfig(type);
    if (resourceConfig == null) {
      _log.warning('No resource config found for type $type');
      return ShardDeterminationResult(
        shards: shards,
        missingGroupIndices: missingGroupIndices,
      );
    }

    // Process each index configuration
    for (final indexConfig in resourceConfig.indices) {
      switch (indexConfig) {
        case FullIndexGraphConfig():
          final indexShards = await _determineShardsForFullIndex(
            indexConfig,
            resourceIri,
            type,
          );
          shards.addAll(indexShards);

        case GroupIndexGraphConfig():
          final result = await _determineShardsForGroupIndex(
            indexConfig,
            resourceIri,
            type,
            internalAppData,
          );
          shards.addAll(result.shards);
          missingGroupIndices.addAll(result.missingGroupIndices);
      }
    }

    return ShardDeterminationResult(
      shards: shards,
      missingGroupIndices: missingGroupIndices,
    );
  }

  /// Gets the resource configuration for a given type from the sync config.
  ResourceGraphConfig? _getResourceConfig(IriTerm type) {
    try {
      return _config.getResourceConfig(type);
    } on ArgumentError {
      return null;
    }
  }

  /// Determines which shard(s) a resource belongs to for a FullIndex.
  ///
  /// Process per SHARDING.md:
  /// 1. Load the FullIndex document from storage
  /// 2. Parse its sharding configuration (numberOfShards, configVersion)
  /// 3. Calculate shard number using MD5 hash modulo algorithm
  /// 4. Find the matching shard IRI from the index's hasShard list
  ///
  /// Returns: List of shard IRIs (should be exactly one for FullIndex)
  Future<List<IriTerm>> _determineShardsForFullIndex(
    FullIndexGraphConfig config,
    IriTerm resourceIri,
    IriTerm typeIri,
  ) async {
    // Generate the index IRI from config
    final indexResourceIri =
        _rdfGenerator.generateFullIndexIri(config, typeIri);
    final indexDocumentIri = indexResourceIri.getDocumentIri();

    // Load the index document from storage
    final storedDoc = await _storage.getDocument(indexDocumentIri);
    if (storedDoc == null) {
      _log.warning('Index document not found: $indexDocumentIri');
      return [];
    }

    // Parse sharding configuration from the index
    final shardingConfig =
        _shardManager.parseShardingConfig(storedDoc.document, indexResourceIri);
    if (shardingConfig == null) {
      _log.warning(
          'Could not parse sharding config from index: $indexResourceIri');
      return [];
    }

    // Calculate which shard number this resource belongs to
    final shardNumber = _shardManager.determineShardNumber(
      resourceIri,
      numberOfShards: shardingConfig.numberOfShards,
    );

    // Generate the expected shard name
    final shardIri = _rdfGenerator.generateShardIri(
      shardingConfig.numberOfShards,
      shardNumber,
      shardingConfig.configVersion,
      indexResourceIri,
      IdxFullIndex.classIri,
    );

    return [shardIri];
  }

  /// Determines which shard(s) a resource belongs to for a GroupIndexTemplate.
  ///
  /// Process per LOCORDA-SPECIFICATION.md section 5.3:
  /// 1. Generate group keys from resource properties using GroupKeyGenerator
  /// 2. For each group key:
  ///    a. Generate GroupIndex IRI from template IRI + group key
  ///    b. Check if GroupIndex exists - if not, report as missing
  ///    c. If exists: Load GroupIndex and parse sharding configuration
  ///    d. Calculate shard number using resource IRI hash
  ///    e. Generate shard IRI
  ///
  /// Returns: ShardDeterminationResult with shards and missing GroupIndices
  Future<ShardDeterminationResult> _determineShardsForGroupIndex(
    GroupIndexGraphConfig config,
    IriTerm resourceIri,
    IriTerm typeIri,
    RdfGraph internalAppData,
  ) async {
    final shards = <IriTerm>[];
    final missingGroupIndices = <MissingGroupIndex>[];

    // Generate the GroupIndexTemplate IRI
    final templateIri =
        _rdfGenerator.generateGroupIndexTemplateIri(config, typeIri);

    // Generate group keys from resource properties
    final groupKeyGenerator = GroupKeyGenerator(config);
    final triples = internalAppData.triples.toList();
    final groupKeys = groupKeyGenerator.generateGroupKeys(triples);

    // If no group keys, resource doesn't belong to any group (missing required properties)
    if (groupKeys.isEmpty) {
      _log.fine(
          'Resource $resourceIri has no group keys for template $templateIri');
      return ShardDeterminationResult(
        shards: shards.toSet(),
        missingGroupIndices: missingGroupIndices,
      );
    }

    // Load template document for sharding configuration (needed for all groups)
    final templateDocumentIri = templateIri.getDocumentIri();
    final templateDoc = await _storage.getDocument(templateDocumentIri);
    if (templateDoc == null) {
      _log.warning(
          'GroupIndexTemplate document not found: $templateDocumentIri');
      return ShardDeterminationResult(
        shards: shards.toSet(),
        missingGroupIndices: missingGroupIndices,
      );
    }

    final shardingConfig =
        _shardManager.parseShardingConfig(templateDoc.document, templateIri);
    if (shardingConfig == null) {
      _log.warning(
          'Could not parse sharding config from GroupIndexTemplate: $templateIri');
      return ShardDeterminationResult(
        shards: shards.toSet(),
        missingGroupIndices: missingGroupIndices,
      );
    }

    // Process each group key
    for (final groupKey in groupKeys) {
      // Generate GroupIndex IRI
      final groupIndexIri =
          _rdfGenerator.generateGroupIndexIri(templateIri, groupKey);
      final groupIndexDocumentIri = groupIndexIri.getDocumentIri();

      // Check if GroupIndex exists
      final groupIndexDoc = await _storage.getDocument(groupIndexDocumentIri);
      if (groupIndexDoc == null) {
        // GroupIndex doesn't exist - report as missing
        _log.fine(
            'GroupIndex for group "$groupKey" does not exist at $groupIndexDocumentIri');
        missingGroupIndices.add(MissingGroupIndex(
          config: config,
          typeIri: typeIri,
          templateIri: templateIri,
          groupKey: groupKey,
          groupIndexIri: groupIndexIri,
        ));
        // Still calculate the shard IRI so caller knows which shard to use
        // once the GroupIndex is created
      }

      // Calculate which shard number this resource belongs to
      final shardNumber = _shardManager.determineShardNumber(
        resourceIri,
        numberOfShards: shardingConfig.numberOfShards,
      );

      // Generate the shard IRI (relative to GroupIndex, not template)
      final shardIri = _rdfGenerator.generateShardIri(
        shardingConfig.numberOfShards,
        shardNumber,
        shardingConfig.configVersion,
        groupIndexIri,
        IdxGroupIndex.classIri,
      );

      shards.add(shardIri);
    }

    return ShardDeterminationResult(
      shards: shards.toSet(),
      missingGroupIndices: missingGroupIndices,
    );
  }
}
