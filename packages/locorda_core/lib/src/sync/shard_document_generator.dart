import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:locorda_core/src/crdt_document_manager.dart';
import 'package:locorda_core/src/generated/_index.dart';
import 'package:locorda_core/src/index/index_manager.dart';
import 'package:locorda_core/src/rdf/rdf_extensions.dart';
import 'package:locorda_core/src/storage/storage_interface.dart';
import 'package:logging/logging.dart';
import 'package:rdf_core/rdf_core.dart';

final _log = Logger('ShardDocumentGenerator');

class ShardDocumentGenerator {
  final Storage _storage;
  final CrdtDocumentManager _documentManager;
  final IndexManager _indexManager;

  ShardDocumentGenerator({
    required Storage storage,
    required CrdtDocumentManager documentManager,
    required IndexManager indexManager,
  })  : _storage = storage,
        _documentManager = documentManager,
        _indexManager = indexManager;

  Future<void> call(DateTime syncTime, int lastSyncTimestamp) async {
    _log.info('Sync triggered - finding shards to update');

    // 1. Get timestamp of last sync
    _log.fine('Last sync timestamp: $lastSyncTimestamp');

    // 2. Find all shards with changes since last sync
    final shardsToUpdate = await _storage.getShardsToUpdate(lastSyncTimestamp);

    if (shardsToUpdate.isEmpty) {
      _log.info('No shards to update');
      return;
    }

    _log.info('Found ${shardsToUpdate.length} shard(s) to update');

    // 3. Sync each shard
    int syncedCount = 0;
    for (final shardIri in shardsToUpdate) {
      final result = await syncShard(shardIri.$1, shardIri.$2);
      if (result != null) {
        syncedCount++;
      }
    }

    _log.info('Synced $syncedCount shard(s)');
  }

  /// Synchronizes a single shard by generating its document from DB entries.
  ///
  /// Process:
  /// 1. Load all active (non-deleted) entries for the shard from DB
  /// 2. Generate RDF graph with all entry fragments
  /// 3. Save shard document (DocumentManager handles diffing/tombstones)
  /// 4. Create missing GroupIndices from save results
  ///
  /// This method can be called:
  /// - By the sync timer for shards with changes
  /// - Manually after save operations in tests (via save_and_sync step)
  ///
  /// Parameters:
  /// - [shardIri]: The IRI of the shard resource to sync
  ///
  /// Returns: SaveResult if changes were made, null if shard was up-to-date
  Future<DocumentSaveResult?> syncShard(
      IriTerm shardIri, int maxPhysicalClock) async {
    final shardDocumentIri = shardIri.getDocumentIri();

    // 1. Load all active entries for this shard from DB
    final entries = await _storage.getActiveIndexEntriesForShard(shardIri);

    if (entries.isEmpty) {
      // No active entries - generate empty shard (will remove any existing entries)
      _log.fine(
          'Shard $shardIri has no active entries, generating empty graph');
    } else {
      _log.fine(
          'Shard $shardIri has ${entries.length} active entries, generating document');
    }
    // 2. Generate RDF graph for shard document from entries
    final newTriples = _generateShardTriples(
      shardDocumentIri: shardDocumentIri,
      shardResourceIri: shardIri,
      entries: entries,
    );

    // 3. Modify shard document
    // DocumentManager will:
    // - load old data and call our callback to generate new graph from entries
    // - Compare with existing document
    // - Create tombstones for removed entries
    // - Return MissingGroupIndex instances if new groups detected
    final saveResult = await _documentManager.modify(
      IdxShard.classIri,
      shardIri,
      (oldAppData) => RdfGraph.fromTriples([
        ...oldAppData
            .subgraph(
              shardIri,
              filter: (triple, depth) =>
                  triple.predicate == IdxShard.containsEntry
                      ? TraversalDecision.skip
                      : TraversalDecision.include,
            )
            .triples,
        ...newTriples
      ]),
      physicalTime: maxPhysicalClock,
    );

    if (saveResult == null) {
      _log.fine('Shard $shardIri unchanged, skipping');
      return null;
    }

    // 4. Create any missing GroupIndex documents
    for (final missing in saveResult.missingGroupIndices) {
      _log.info(
          'Creating missing GroupIndex for group "${missing.groupKey}" at ${missing.groupIndexIri}');
      await _indexManager.createMissingGroupIndex(missing);
    }

    return saveResult;
  }

  /// Generates RDF graph for a complete shard document.
  ///
  /// Creates a graph containing idx:containsEntry links and entry fragments
  /// for all provided entries. Entries must be from the same shard.
  ///
  /// The generated graph contains:
  /// - idx:containsEntry links from shard to each entry
  /// - Entry fragments with idx:resource, cm:clockHash, and optional headers
  ///
  /// All installations must generate identical graphs for the same entries
  /// to ensure CRDT convergence.
  List<Triple> _generateShardTriples({
    required IriTerm shardDocumentIri,
    required IriTerm shardResourceIri,
    required List<IndexEntryWithIri> entries,
  }) {
    final triples = <Triple>[];
    for (final entry in entries) {
      if (entry.isDeleted) {
        // Skip deleted entries - they are handled by DocumentManager tombstones
        continue;
      }
      // Deserialize header properties if present
      Map<IriTerm, List<RdfObject>>? headerProperties;
      if (entry.headerProperties != null) {
        final headerGraph = turtle.decode(entry.headerProperties!);
        // Extract properties for the resource IRI
        headerProperties = {};
        for (final triple in headerGraph.triples) {
          if (triple.subject == entry.resourceIri) {
            headerProperties.putIfAbsent(triple.predicate as IriTerm, () => []);
            headerProperties[triple.predicate as IriTerm]!.add(triple.object);
          }
        }
        if (headerProperties.isEmpty) {
          headerProperties = null;
        }
      }

      // Generate entry IRI and fragment
      final (entryIri, entryGraph) = _generateIndexEntry(
        shardDocumentIri: shardDocumentIri,
        itemResourceIri: entry.resourceIri,
        clockHash: entry.clockHash,
        headerProperties: headerProperties,
      );

      // Add containsEntry link
      triples.add(Triple(shardResourceIri, IdxShard.containsEntry, entryIri));

      // Add entry fragment triples
      triples.addAll(entryGraph.triples);
    }

    return triples;
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
}
