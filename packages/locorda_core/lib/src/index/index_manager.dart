/// Manages index lifecycle including creation, shard management, and entry operations.
///
/// The IndexManager coordinates index and shard operations using IndexRdfGenerator
/// and ShardManager to create and maintain indices according to the specification.
library;

import 'package:locorda_core/locorda_core.dart';
import 'package:locorda_core/src/crdt_document_manager.dart';
import 'package:locorda_core/src/generated/_index.dart';
import 'package:locorda_core/src/index/index_property_resolver.dart';
import 'package:locorda_core/src/index/index_rdf_generator.dart';
import 'package:locorda_core/src/index/shard_determiner.dart';
import 'package:locorda_core/src/rdf/rdf_extensions.dart';
import 'package:locorda_core/src/util/retry.dart';
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
  final SyncGraphConfig _config;
  final IriTerm _installationIri;

  IndexManager({
    required CrdtDocumentManager crdtDocumentManager,
    required IndexRdfGenerator rdfGenerator,
    required Storage storage,
    required IriTerm installationIri,
    required SyncGraphConfig config,
  })  : _documentManager = crdtDocumentManager,
        _rdfGenerator = rdfGenerator,
        _storage = storage,
        _config = config,
        _propertyResolver = IndexPropertyResolver(storage: storage),
        _installationIri = installationIri;

  /// Initializes all indices defined in the configuration.
  ///
  /// Creates FullIndex or GroupIndexTemplate documents for each resource type
  /// and their initial shards. Should be called once during setup after
  /// installation document creation.
  ///
  /// Returns the number of indices created (useful for testing).
  Future<int> initializeIndices() async {
    var createdCount = 0;

    // Make sure to create indices in the correct, deterministic order
    for (final (indexConfig, resourceTypeIri) in _config.allIndicesInOrder) {
      // Create index based on type
      switch (indexConfig) {
        case FullIndexGraphConfig _:
          await _createFullIndex(indexConfig, resourceTypeIri);
        case GroupIndexGraphConfig _:
          await _createGroupIndexTemplate(indexConfig, resourceTypeIri);
      }

      createdCount++;
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
      indexTypeIri: IdxFullIndex.classIri,
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
      await _saveWithRetry(
        IdxShard.classIri,
        shardGraph,
        context: 'shard for FullIndex $indexResourceIri',
      );
    }

    // Save index document
    await _saveWithRetry(
      IdxFullIndex.classIri,
      indexGraph,
      context: 'FullIndex $indexResourceIri',
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

    await _saveWithRetry(
      IdxGroupIndexTemplate.classIri,
      templateGraph,
      context: 'GroupIndexTemplate $templateResourceIri',
    );
  }

  /// Creates a missing GroupIndex that was detected during shard determination.
  ///
  /// This is a public wrapper around _createGroupIndex() that can be called
  /// by LocordaGraphSync to create GroupIndices that were reported as missing
  /// during document save.
  ///
  /// Retrieves the GroupIndexGraphConfig from the resource configuration
  /// based on the template IRI and group key.
  Future<void> _createMissingGroupIndex(MissingGroupIndex missing) async {
    // Get resource config for this type
    final resourceConfig = _config.getResourceConfig(missing.typeIri);

    // Find the matching GroupIndexGraphConfig
    // We need to identify which GroupIndexGraphConfig this missing GroupIndex belongs to
    // by matching the template IRI structure
    GroupIndexGraphConfig? matchingConfig;
    for (final indexConfig in resourceConfig.indices) {
      if (indexConfig is GroupIndexGraphConfig) {
        final templateIri = _rdfGenerator.generateGroupIndexTemplateIri(
            indexConfig, missing.typeIri);
        if (templateIri == missing.templateIri) {
          matchingConfig = indexConfig;
          break;
        }
      }
    }

    if (matchingConfig == null) {
      throw StateError(
          'Could not find GroupIndexGraphConfig for template ${missing.templateIri}');
    }

    await _createGroupIndex(
      matchingConfig,
      missing.typeIri,
      missing.templateIri,
      missing.groupKey,
      missing.groupIndexIri,
    );
  }

  /// Creates a new GroupIndex instance for a specific group.
  ///
  /// Creates the GroupIndex document and its initial shard(s) based on the
  /// template's sharding configuration.
  Future<void> _createGroupIndex(
    GroupIndexGraphConfig config,
    IriTerm typeIri,
    IriTerm templateIri,
    String groupKey,
    IriTerm groupIndexIri,
  ) async {
    // Generate initial shard
    final (shardResourceIri, shardGraph) = _rdfGenerator.generateShard(
      totalShards: 1, // Start with single shard per group
      shardNumber: 0,
      configVersion: '1_0_0',
      indexResourceIri: groupIndexIri,
      indexTypeIri: IdxGroupIndex.classIri,
    );

    // Generate GroupIndex RDF
    final groupIndexGraph = _generateGroupIndex(
      config: config,
      resourceType: typeIri,
      resourceIri: groupIndexIri,
      templateIri: templateIri,
      shards: [shardResourceIri],
    );

    // Save shard document first (same pattern as FullIndex)
    if (!(await _documentManager
        .hasDocument(shardResourceIri.getDocumentIri()))) {
      await _saveWithRetry(
        IdxShard.classIri,
        shardGraph,
        context: 'shard for GroupIndex $groupIndexIri',
      );
    }

    // Save GroupIndex document
    await _saveWithRetry(
      IdxGroupIndex.classIri,
      groupIndexGraph,
      context: 'GroupIndex $groupIndexIri',
    );
  }

  /// Saves a document and updates indices with retry logic for concurrent updates.
  ///
  /// Retries up to 3 times on [ConcurrentUpdateException].
  /// Throws [StateError] if all retries fail.
  Future<DocumentSaveResult?> _saveWithRetry(
    IriTerm type,
    RdfGraph appData, {
    required String context,
  }) async {
    return retryOnConflict(() => _save(type, appData),
        debugOperationName: 'save $context', log: _log);
  }

  /// Internal save method that throws [ConcurrentUpdateException] on optimistic lock failure.
  Future<DocumentSaveResult?> _save(IriTerm type, RdfGraph appData) async {
    final saved = await _documentManager.save(type, appData);
    if (saved != null) {
      await updateIndices(
          document: saved.crdtDocument,
          documentIri: saved.documentIri,
          physicalTime: saved.physicalTime,
          missingGroupIndices: saved.missingGroupIndices);
    }
    return saved;
  }

  Future<void> updateIndices(
      {required RdfGraph document,
      required IriTerm documentIri,
      required int physicalTime,
      required Iterable<MissingGroupIndex> missingGroupIndices}) async {
    //  Create any missing GroupIndex documents that were detected during save
    // This must happen before updateIndices so the shards exist
    for (final missing in missingGroupIndices) {
      _log.info(
          'Creating missing GroupIndex for group "${missing.groupKey}" at ${missing.groupIndexIri}');
      await _createMissingGroupIndex(missing);
    }

    // Update the Index Shards
    final allShards = document.getMultiValueObjectList<IriTerm>(
        documentIri, SyncManagedDocument.idxBelongsToIndexShard);

    // Extract clock hash from the saved document
    final clockHashLiteral = document.findSingleObject<LiteralTerm>(
        documentIri, SyncManagedDocument.crdtClockHash);
    final clockHash = clockHashLiteral?.value;
    if (clockHash == null) {
      throw StateError(
          'Saved document $documentIri is missing crdt:clockHash, cannot update indices.');
    }
    final resourceIri = document.expectSingleObject<IriTerm>(
        documentIri, SyncManagedDocument.foafPrimaryTopic)!;
    final type = document.expectSingleObject<IriTerm>(resourceIri, Rdf.type)!;

    // Remove entries from shards where belongsToIndexShard was removed
    // This must happen BEFORE updateShardIndexEntries to ensure tombstones are created first
    await _removeTombstonedShardEntries(
        resourceIri, document, documentIri, physicalTime);

    // Update the indices
    await _updateShardIndexEntries(
        type, resourceIri, clockHash, document, allShards, physicalTime);
  }

  /// Generates RDF graph for a GroupIndex resource.
  ///
  /// Similar to FullIndex but links back to GroupIndexTemplate via idx:basedOn
  RdfGraph _generateGroupIndex({
    required GroupIndexGraphConfig config,
    required IriTerm resourceType,
    required IriTerm resourceIri,
    required IriTerm templateIri,
    required Iterable<IriTerm> shards,
  }) {
    final triples = <Triple>[
      // Type declaration
      Triple(resourceIri, Rdf.type, IdxGroupIndex.classIri),

      // Link back to template
      Triple(resourceIri, IdxGroupIndex.basedOn, templateIri),

      // Shards
      ...shards
          .map((shard) => Triple(resourceIri, IdxGroupIndex.hasShard, shard)),
    ];

    return triples.toRdfGraph();
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
  /// - [document]: The full document (for extracting header properties)
  /// - [allShards]: All shard IRIs the resource currently belongs to (from idx:belongsToIndexShard)
  Future<void> _updateShardIndexEntries(
    IriTerm type,
    IriTerm resourceIri,
    String clockHash,
    RdfGraph document,
    Iterable<IriTerm> allShards,
    int physicalClock,
  ) async {
    // Process each shard the resource belongs to
    for (final shardIri in allShards) {
      final shardDocumentIri = shardIri.getDocumentIri();
      // Resolve which properties should be indexed for this shard
      final (indexIri, indexedProperties) =
          await _propertyResolver.resolveIndexedProperties(shardDocumentIri);
      if (indexIri == null) {
        // FIXME: this can happen for foreign app shards which are referenced - we need to handle this case
        // somehow. Downloading the shard and index is not an option here, because
        // we are offline-first. So maybe make an index entry without header properties,
        // without index IRI and with a marker that this needs to be resolved later?
        _log.warning(
            'Shard $shardDocumentIri has no associated index or template, skipping.');
        continue;
      }
      // Extract property values from resource data
      final headerProperties = _extractHeaderProperties(
        resourceIri: resourceIri,
        document: document,
        propertiesToExtract: indexedProperties,
      );

      // Serialize header properties to Turtle if present
      String? headerPropertiesTurtle;
      if (headerProperties != null) {
        final headerGraph = RdfGraph.fromTriples(headerProperties.entries
            .expand((e) => e.value.map((v) => Triple(resourceIri, e.key, v))));
        headerPropertiesTurtle = turtle.encode(headerGraph);
      }

      // Save index entry to database
      await _storage.saveIndexEntry(
        shardIri: shardIri,
        indexIri: indexIri,
        resourceIri: resourceIri,
        clockHash: clockHash,
        headerProperties: headerPropertiesTurtle,
        updatedAt: physicalClock,
        ourPhysicalClock: physicalClock,
      );
    }
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
  /// - [document]: The resource's semantic RDF data
  /// - [propertiesToExtract]: Set of property IRIs to extract (from index config)
  ///
  /// Returns: Map of property IRI to RdfObject, or null if no properties found
  Map<IriTerm, List<RdfObject>>? _extractHeaderProperties({
    required IriTerm resourceIri,
    required RdfGraph document,
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
      final values = document.getMultiValueObjectList<RdfObject>(
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

  /// Removes entries from shards based on tombstones in idx:belongsToIndexShard.
  ///
  /// When a resource's group membership changes (e.g., recipe category changes from
  /// 'Dessert' to 'Main Course'), the OR-Set semantics automatically create tombstones
  /// for the removed shard references. This method:
  ///
  /// 1. Detects tombstoned idx:belongsToIndexShard values in the CRDT document
  /// 2. For each tombstoned shard, removes the corresponding entry using patch()
  /// 3. Uses empty graph to signal removal (OR-Set tombstone will be created automatically)
  ///
  /// This ensures indices remain consistent with current group membership while preserving
  /// tombstones for conflict resolution during synchronization.
  ///
  /// Parameters:
  /// - [resourceIri]: The resource whose shard entries should be cleaned up
  /// - [crdtDocument]: The saved CRDT document containing potential tombstones
  /// - [documentIri]: The document IRI to search for tombstones
  Future<void> _removeTombstonedShardEntries(IriTerm resourceIri,
      RdfGraph crdtDocument, IriTerm documentIri, int ourPhysicalClock) async {
    // Find all reified statements with crdt:deletedAt for idx:belongsToIndexShard
    final reifiedStmts =
        crdtDocument.findTriples(predicate: Rdf.subject, object: documentIri);

    if (reifiedStmts.isEmpty) {
      return; // No reified statements, nothing to clean up
    }

    final tombstones = <Triple>[];
    for (final reifiedStmt in reifiedStmts) {
      if (reifiedStmt.subject is! IriTerm) continue;
      final stmtIri = reifiedStmt.subject as IriTerm;

      // Check if it has crdt:deletedAt (tombstone marker)
      final deletedAt = crdtDocument.findSingleObject<LiteralTerm>(
        stmtIri,
        Crdt.deletedAt,
      );
      if (deletedAt == null) continue;

      // Check if the reified statement is about belongsToIndexShard
      final reifiedPredicate = crdtDocument.findSingleObject<IriTerm>(
        stmtIri,
        Rdf.predicate,
      );

      if (reifiedPredicate == SyncManagedDocument.idxBelongsToIndexShard) {
        tombstones.add(reifiedStmt);
      }
    }

    if (tombstones.isEmpty) {
      return; // No tombstones found, nothing to clean up
    }

    _log.info(
        'Found ${tombstones.length} tombstoned shard references for $resourceIri');

    // For each tombstoned shard reference, remove the entry
    for (final tombstone in tombstones) {
      final reifiedStmtIri = tombstone.subject as IriTerm;

      // Get the shard IRI from the reified statement's object
      final shardIri = crdtDocument.findSingleObject<IriTerm>(
        reifiedStmtIri,
        Rdf.object,
      );

      if (shardIri == null) {
        _log.warning(
            'Tombstone $reifiedStmtIri has no rdf:object, skipping cleanup');
        continue;
      }

      _log.info('Marking entry for $resourceIri as deleted in shard $shardIri');

      // Resolve index IRI for this shard
      final shardDocumentIri = shardIri.getDocumentIri();
      final (indexIri, _) =
          await _propertyResolver.resolveIndexedProperties(shardDocumentIri);

      if (indexIri == null) {
        _log.warning(
            'Cannot resolve index for shard $shardDocumentIri, skipping tombstone');
        continue;
      }

      // Mark entry as deleted in database
      // We use empty clockHash and no headerProperties for deleted entries
      await _storage.saveIndexEntry(
        shardIri: shardIri,
        indexIri: indexIri,
        resourceIri: resourceIri,
        // TODO: is it correct to use empty clockHash here?
        clockHash: '', // Empty hash for deleted entries
        headerProperties: null,
        isDeleted: true,
        ourPhysicalClock: ourPhysicalClock,
        updatedAt: ourPhysicalClock,
      );
    }
  }
}

/// Extension to expose internal helper methods for testing.
extension IndexManagerTestHelpers on IndexManager {
  IndexRdfGenerator get rdfGenerator => _rdfGenerator;
}
