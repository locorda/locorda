/// Manages index lifecycle including creation, shard management, and entry operations.
///
/// The IndexManager coordinates index and shard operations using IndexRdfGenerator
/// and ShardManager to create and maintain indices according to the specification.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:locorda_core/locorda_core.dart';
import 'package:locorda_core/src/crdt_document_manager.dart';
import 'package:locorda_core/src/generated/_index.dart';
import 'package:locorda_core/src/index/index_property_resolver.dart';
import 'package:locorda_core/src/index/index_rdf_generator.dart';
import 'package:locorda_core/src/index/shard_manager.dart';
import 'package:locorda_core/src/rdf/rdf_extensions.dart';
import 'package:logging/logging.dart';
import 'package:rdf_core/rdf_core.dart';

final _log = Logger('IndexManager');

/// Manages index and shard operations for the sync system.
///
/// Responsibilities:
/// - Creates indices during initialization based on configuration
/// - Creates initial shards for each index
/// - Adds entries to appropriate shards
/// - Handles shard scaling when thresholds are exceeded
class IndexManager {
  final CrdtDocumentManager _documentManager;
  final IndexRdfGenerator _rdfGenerator;
  final IndexPropertyResolver _propertyResolver;
  final Storage _storage;
  final ShardManager _shardManager;
  final SyncGraphConfig _config;

  final IriTerm _installationIri;
  final ResourceLocator _resourceLocator;

  IndexManager({
    required CrdtDocumentManager crdtDocumentManager,
    required IndexRdfGenerator rdfGenerator,
    required Storage storage,
    required IriTerm installationIri,
    required ResourceLocator resourceLocator,
    required SyncGraphConfig config,
  })  : _documentManager = crdtDocumentManager,
        _rdfGenerator = rdfGenerator,
        _propertyResolver = IndexPropertyResolver(storage: storage),
        _storage = storage,
        _shardManager = const ShardManager(),
        _config = config,
        _installationIri = installationIri,
        _resourceLocator = resourceLocator;

  /// Initializes all indices defined in the configuration.
  ///
  /// Creates FullIndex or GroupIndexTemplate documents for each resource type
  /// and their initial shards. Should be called once during setup after
  /// installation document creation.
  ///
  /// Returns the number of indices created (useful for testing).
  Future<int> initializeIndices(SyncGraphConfig config) async {
    var createdCount = 0;

    for (final resource in config.resources) {
      for (final indexConfig in resource.indices) {
        // Create index based on type
        switch (indexConfig) {
          case FullIndexGraphConfig _:
            await _createFullIndex(indexConfig, resource.typeIri);
          case GroupIndexGraphConfig _:
            await _createGroupIndexTemplate(indexConfig, resource.typeIri);
        }

        createdCount++;
      }
    }

    return createdCount;
  }

  /// Creates a FullIndex with its initial shard.
  Future<void> _createFullIndex(
    FullIndexGraphConfig config,
    IriTerm resourceType,
  ) async {
    // Generate local ID from config
    final indexResourceIri =
        _rdfGenerator.generateFullIndexIri(config, resourceType);
    final indexDocumentIri = indexResourceIri.getDocumentIri();

    if (await _documentManager.hasDocument(indexDocumentIri)) {
      // Index already exists, skip creation
      return;
    }

    // Create initial shard
    final (shardResourceIri, shardGraph) = _rdfGenerator.generateShard(
      totalShards: 1,
      shardNumber: 0,
      configVersion: '1_0_0',
      indexResourceIri: indexResourceIri,
    );

    // Generate index RDF
    final indexGraph = _rdfGenerator.generateFullIndex(
      config: config,
      resourceIri: indexResourceIri,
      resourceType: resourceType,
      installationIri: _installationIri,
      shards: [shardResourceIri],
    );

    // Important: first save shard document - because we will skip this entire
    // block if the index document already exists, so we must ensure the
    // index document is saved last.
    if (!(await _documentManager
        .hasDocument(shardResourceIri.getDocumentIri()))) {
      await _documentManager.save(
        IdxShard.classIri,
        shardGraph,
        // shards are not tracked in other indices
        const [],
      );
    }

    // Save index document
    await _documentManager.save(
      IdxFullIndex.classIri,
      indexGraph,
      // index documents are not tracked in other indices
      const [],
    );
  }

  /// Creates a GroupIndexTemplate.
  Future<void> _createGroupIndexTemplate(
    GroupIndexGraphConfig config,
    IriTerm resourceType,
  ) async {
    final templateResourceIri =
        _rdfGenerator.generateGroupIndexTemplateIri(config, resourceType);
    if (await _documentManager
        .hasDocument(templateResourceIri.getDocumentIri())) {
      // Template already exists, skip creation
      return;
    }
    // Generate template RDF
    final templateGraph = _rdfGenerator.generateGroupIndexTemplate(
      config: config,
      resourceIri: templateResourceIri,
      resourceType: resourceType,
      installationIri: _installationIri,
    );

    // Save template document
    // GroupIndexTemplate doesn't have shards - those are created per group

    await _documentManager.save(
      IdxGroupIndexTemplate.classIri,
      templateGraph,
      // group index templates are not tracked in other indices
      const [],
    );
  }

  /// Determines which shards a resource of the given type should belong to.
  ///
  /// According to LOCORDA-SPECIFICATION.md section 6.4 "Resource Creation Workflow":
  /// 1. Identify all matching index shards based on resource type
  /// 2. For FullIndex: Calculate shard based on resource IRI hash
  /// 3. For GroupIndexTemplate: Determine group membership (not implemented yet)
  ///
  /// This method currently handles FullIndex only.
  ///
  /// Parameters:
  /// - [type]: The RDF type of the resource (e.g., schema:Recipe)
  /// - [resourceIri]: The IRI of the resource being indexed
  /// - [internalAppData]: The resource's semantic data (for group determination in future)
  ///
  /// Returns: Iterable of shard IRIs the resource should be indexed in
  Future<Iterable<IriTerm>> determineShards(
    IriTerm type,
    IriTerm resourceIri,
    RdfGraph internalAppData,
  ) async {
    final shards = <IriTerm>[];

    // Get all index configurations for this resource type from config
    final resourceConfig = _getResourceConfig(type);
    if (resourceConfig == null) {
      _log.warning('No resource config found for type $type');
      return shards;
    }

    // Process each index configuration
    for (final indexConfig in resourceConfig.indices) {
      switch (indexConfig) {
        case FullIndexGraphConfig():
          final indexShards = await _determineShardsForFullIndex(
              indexConfig, resourceIri, type);
          shards.addAll(indexShards);

        case GroupIndexGraphConfig():
          throw UnimplementedError(
            'GroupIndexTemplate shard determination not yet implemented. '
            'This will be handled in the next step.',
          );
      }
    }

    return shards;
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
        indexResourceIri);

    return [shardIri];
  }

  /// Updates all index shards to reflect the current state of a resource.
  ///
  /// This method is called after a resource has been saved to ensure index entries
  /// are synchronized with the resource state. It processes all shards the resource
  /// belongs to and updates their entries accordingly.
  ///
  /// Process:
  /// 1. For each shard:
  ///    a. Resolve which properties should be indexed (from index document)
  ///    b. Extract those property values from the resource data
  ///    c. Generate entry graph with properties
  ///    d. Patch shard document with entry
  ///
  /// Parameters:
  /// - [type]: The RDF type of the resource (e.g., schema:Recipe)
  /// - [resourceIri]: The IRI of the resource being indexed
  /// - [clockHash]: The clock hash from the saved CRDT document
  /// - [internalAppData]: The resource's semantic data (for extracting header properties)
  /// - [allShards]: All shard IRIs the resource currently belongs to (from idx:belongsToIndexShard)
  Future<Map<IriTerm, DocumentSaveResult>> updateIndices(
    IriTerm type,
    IriTerm resourceIri,
    String clockHash,
    RdfGraph internalAppData,
    Iterable<IriTerm> allShards,
  ) async {
    final updatedIndices = <IriTerm, DocumentSaveResult>{};
    // Process each shard the resource belongs to
    for (final shardIri in allShards) {
      final shardDocumentIri = shardIri.getDocumentIri();
      // Resolve which properties should be indexed for this shard
      final (rootIri, indexedProperties) =
          await _propertyResolver.resolveIndexedProperties(shardDocumentIri);
      if (rootIri == null) {
        _log.warning(
            'Shard $shardDocumentIri has no associated index or template, skipping.');
        continue;
      }
      // Extract property values from resource data
      final headerProperties = _extractHeaderProperties(
        resourceIri: resourceIri,
        appData: internalAppData,
        propertiesToExtract: indexedProperties,
      );

      // Generate entry graph for this resource
      final (entryIri, entryGraph) = _generateIndexEntry(
        shardDocumentIri: shardDocumentIri,
        itemResourceIri: resourceIri,
        clockHash: clockHash,
        headerProperties: headerProperties,
      );

      // Save updated shard
      // CrdtDocumentManager.patch() will automatically:
      // 1. Load the existing shard document (if it exists)
      // 2. Merge the entry graph with plain local data exchange:
      //    - Add entry IRI to idx:containsEntry OR-Set if not exists
      //    - Remove existing IRI subgraph
      //    - Add new entry subgraph
      // 3. Save the merged result, creating proper CRDT structures
      final r = await _documentManager.patch(
        IdxShard.classIri,
        shardIri,
        IdxShard.containsEntry,
        (entryIri, entryGraph),
      );
      if (r != null) {
        updatedIndices[rootIri] = r;
      }
    }
    return updatedIndices;
  }

  /// Generates RDF graph for an index entry.
  ///
  /// Creates a graph containing:
  /// - Link from shard to entry (idx:containsEntry)
  /// - Entry properties (idx:resource, crdt:clockHash, optional headers)
  ///
  /// All installations must generate identical fragments for the same resource
  /// to ensure CRDT convergence. Uses MD5-based fragment generation as specified
  /// in proposal 010-index-entry-iri-identification.md
  Node _generateIndexEntry({
    required IriTerm shardDocumentIri,
    required IriTerm itemResourceIri,
    required String clockHash,
    Map<IriTerm, List<RdfObject>>? headerProperties,
  }) {
    // Generate deterministic fragment from resource IRI
    final entryFragment = _generateEntryFragment(itemResourceIri);
    final entryIri = IriTerm('${shardDocumentIri.value}#$entryFragment');

    final triples = <Triple>[
      // Entry properties
      Triple(entryIri, IdxShardEntry.resource, itemResourceIri), // Immutable
      Triple(
        entryIri,
        IdxShardEntry.crdtClockHash,
        LiteralTerm(clockHash),
      ), // LWW-Register
    ];

    // Optional header properties (all LWW-Register)
    if (headerProperties != null) {
      for (final entry in headerProperties.entries) {
        triples.addMultiple(entryIri, entry.key, entry.value);
      }
    }

    return (entryIri, triples.toRdfGraph());
  }

  /// Generates deterministic fragment identifier for index entry.
  ///
  /// Uses MD5 hash of resource IRI to ensure all installations
  /// generate identical fragment identifiers for the same resource.
  ///
  /// This is a specification requirement (proposal 010) - all implementations
  /// MUST use this exact algorithm for interoperability.
  ///
  /// Returns: `entry-{32-char-md5-hex}` (e.g., `entry-a1b2c3d4...`)
  String _generateEntryFragment(IriTerm resourceIri) {
    // Use full IRI value, not prefixed form
    final bytes = utf8.encode(resourceIri.value);
    final digest = md5.convert(bytes);
    return 'entry-${digest.toString()}'; // Full 32-character hex string
  }

  /// Extracts header properties from resource data for specified properties.
  ///
  /// Takes a set of property IRIs (resolved from the index configuration)
  /// and extracts their values from the resource's RDF graph.
  ///
  /// Process:
  /// 1. For each property IRI in the set
  /// 2. Get all values for that property from the resource
  /// 3. Use first value (index entries use LWW-Register for all properties)
  /// 4. Skip properties with no values
  ///
  /// Parameters:
  /// - [resourceIri]: The IRI of the resource to extract properties from
  /// - [appData]: The resource's semantic RDF data
  /// - [propertiesToExtract]: Set of property IRIs to extract (from index config)
  ///
  /// Returns: Map of property IRI to RdfObject, or null if no properties found
  Map<IriTerm, List<RdfObject>>? _extractHeaderProperties({
    required IriTerm resourceIri,
    required RdfGraph appData,
    required Set<IriTerm> propertiesToExtract,
  }) {
    // If no properties configured, return null
    if (propertiesToExtract.isEmpty) {
      return null;
    }

    // Extract property values from resource data
    final headerProperties = <IriTerm, List<RdfObject>>{};
    for (final propertyIri in propertiesToExtract) {
      // Get all values for this property
      final values = appData.getMultiValueObjects<RdfObject>(
        resourceIri,
        propertyIri,
      );

      // Use first value if available (index entries use LWW-Register)
      if (values.isNotEmpty) {
        headerProperties[propertyIri] = values;
        if (values.any((v) => v is BlankNodeTerm)) {
          throw ArgumentError(
              'Header property $propertyIri has blank node value, which is not supported in index entries.');
        }
      }
      // If property has no values, don't include it in the entry
    }

    // Return null if no properties were found, otherwise return the map
    return headerProperties.isEmpty ? null : headerProperties;
  }

  IriTerm getIndexOrTemplateIri(CrdtIndexGraphConfig index, IriTerm typeIri) =>
      _rdfGenerator.generateIndexOrTemplateIri(index, typeIri);
}

/// Extension to expose internal helper methods for testing.
extension IndexManagerTestHelpers on IndexManager {
  IndexRdfGenerator get rdfGenerator => _rdfGenerator;
}
