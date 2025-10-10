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
import 'package:locorda_core/src/index/shard_determiner.dart';
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

    for (final resource in _config.resources) {
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
      await _documentManager.save(
        IdxShard.classIri,
        shardGraph,
      );
    }

    // Save index document
    await _documentManager.save(
      IdxFullIndex.classIri,
      indexGraph,
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
    );
  }

  /// Creates a missing GroupIndex that was detected during shard determination.
  ///
  /// This is a public wrapper around _createGroupIndex() that can be called
  /// by LocordaGraphSync to create GroupIndices that were reported as missing
  /// during document save.
  Future<void> createMissingGroupIndex(MissingGroupIndex missing) async {
    await _createGroupIndex(
      missing.config,
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
      await _documentManager.save(IdxShard.classIri, shardGraph);
    }

    // Save GroupIndex document
    await _documentManager.save(IdxGroupIndex.classIri, groupIndexGraph);
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
  Future<void> removeTombstonedShardEntries(
    IriTerm resourceIri,
    RdfGraph crdtDocument,
    IriTerm documentIri,
  ) async {
    // Find all reified statements with crdt:deletedAt for idx:belongsToIndexShard
    final reifiedStmts =
        crdtDocument.findTriples(predicate: Rdf.subject, object: documentIri);

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

      _log.info(
          'Removing entry for $resourceIri from tombstoned shard $shardIri');

      // Generate the entry IRI that should be removed
      final shardDocumentIri = shardIri.getDocumentIri();
      final entryFragment = _generateEntryFragment(resourceIri);
      final entryIri = IriTerm('${shardDocumentIri.value}#$entryFragment');

      // Use patch() with empty graph to remove the entry
      // This signals removal, and patch() will create appropriate tombstones
      await _documentManager.patch(
        IdxShard.classIri,
        shardIri,
        IdxShard.containsEntry,
        (entryIri, RdfGraphExtensions.empty),
      );
    }
  }
}

/// Extension to expose internal helper methods for testing.
extension IndexManagerTestHelpers on IndexManager {
  IndexRdfGenerator get rdfGenerator => _rdfGenerator;
}
