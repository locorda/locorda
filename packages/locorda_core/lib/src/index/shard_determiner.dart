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

  Future<
      (
        Set<IriTerm> all,
        Set<IriTerm> removed,
        List<MissingGroupIndex> missing
      )> calculateShards(
    IriTerm type,
    IriTerm resourceIri,
    IriTerm documentIri,
    RdfGraph appData,
    RdfGraph? oldAppData,
    RdfGraph? oldFrameworkGraph,
  ) async {
/*
FIXME: The config based implementation is wrong

I think we have a difference to the concept here: We are using only the 
configured indices of the current app for determining the shards, keeping
"foreign app shards" as they are. But AFAIR in the spec we say, that we need 
to consider all indices that are relevant for the resource type. 

The problem now is, that since going away from only considering solid pods
as backends, we have lost the solid type index. We did not need it until now,
but if we do not use the solid type index, how do we know about all potentially
relevant indices for a resource type?

So I think we do need an index of indices - or maybe an index of shards? Or both?
And index of shards could be nice to speed up the sync even further, but it would 
not contain the managed resource type of the index, so it does not help here.

For this problem here, we probably want an index of GroupIndexTemplates and an index of FullIndices.

If we do have such indices, we can quickly find all relevant full indices and group index templates
for all resource types we handle, ensuring that  they are fully synced so that determine shards
can compute the correct result.

Consequences:
- We need to create and maintain these indices of indices
- When syncing, we need to ensure that these indices are fully synced before we start
  syncing normal resources. 
- The sync process currently is organized in stages like all_indices, all_shards, all_documents.
  Maybe we have to do those stages independently per type? So first we do the full sync for
  GroupIndexTemplates and FullIndices, then for other (configured) resource types one by one, maybe even in a predictable order?
- We currently have only eager and onDemand sync, and for being able to selectively
  sync some items of a type eagerly and others onDemand (or not at all), we
  are using group indices, which seems great and correct for larger data sets. 
  But the index of indices would not be so extremely large and creating a new
  group per indexed resource type seems a bit over the top. So maybe we need
  a third sync mode "eager_filtered", and use this for the index of indices?
  We would provide the values for a  certain property that should be eagerly fetched.
*/

    // Calculate new shards based on current appData
    final newShardResult = await _determineShards(
      type,
      resourceIri,
      appData,
    );
    final newShards = newShardResult.shards;

    // Calculate old shards based on previous appData (if exists)
    // This is needed to determine which shards should be removed
    final oldShardResult = oldAppData != null
        ? await _determineShards(
            type,
            resourceIri,
            oldAppData,
          )
        : const ShardDeterminationResult(
            shards: const <IriTerm>{},
            missingGroupIndices: const <MissingGroupIndex>[],
          );
    final oldCalculatedShards = oldShardResult.shards;
    final removed = oldCalculatedShards.difference(newShards);

    // Get shards from old framework graph for other installations
    final oldStoredShards = oldFrameworkGraph?.getMultiValueObjects<IriTerm>(
            documentIri, SyncManagedDocument.idxBelongsToIndexShard) ??
        const <IriTerm>[];

    // Only keep shards that are either:
    // 1. In newShards (currently valid for this installation)
    // 2. In oldStoredShards but NOT in removed (from other installations)
    final shardsFromOtherInstallations = removed.isEmpty
        ? oldStoredShards
        : oldStoredShards.where((shard) => !removed.contains(shard));
    final allShards = {...newShards, ...shardsFromOtherInstallations};
    return (allShards, removed, newShardResult.missingGroupIndices);
  }

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
  Future<ShardDeterminationResult> _determineShards(
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
