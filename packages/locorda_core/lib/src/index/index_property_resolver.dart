/// Resolves indexed properties for index shards with LRU caching.
///
/// This class is responsible for traversing the index hierarchy to determine
/// which properties should be included in index entries for a given shard.
///
/// Hierarchy traversal:
/// 1. Shard → idx:isShardOf → FullIndex or GroupIndex
/// 2. GroupIndex → idx:basedOn → GroupIndexTemplate (if applicable)
/// 3. Index/Template → idx:indexedProperty → List of property IRIs
library;

import 'package:locorda_core/src/generated/_index.dart';
import 'package:locorda_core/src/rdf/rdf_extensions.dart';
import 'package:locorda_core/src/storage/storage_interface.dart';
import 'package:locorda_core/src/util/lru_cache.dart';
import 'package:rdf_core/rdf_core.dart';

typedef IndexProperties = (IriTerm? indexIri, Set<IriTerm> properties);

/// Resolves which properties should be indexed for a given shard.
///
/// Uses LRU cache to avoid repeated backend lookups for the same shards.
class IndexPropertyResolver {
  final Storage _storage;

  /// LRU cache: shard document IRI → set of property IRIs to index
  /// Uses LinkedHashMap to maintain insertion order for LRU eviction
  final LRUCache<String, IndexProperties> _cache;

  IndexPropertyResolver({
    required Storage storage,
    int cacheSize = 100,
  })  : _storage = storage,
        _cache = LRUCache(maxCacheSize: cacheSize);

  /// Resolves which properties should be included in index entries for a shard.
  ///
  /// Process:
  /// 1. Check cache for cached result
  /// 2. Load shard document from storage
  /// 3. Follow idx:isShardOf to get parent index
  /// 4. If GroupIndex, follow idx:basedOn to get template
  /// 5. Extract idx:indexedProperty list from index/template
  /// 6. Cache result and return
  ///
  /// Returns empty set if shard not found or no properties configured.
  Future<IndexProperties> resolveIndexedProperties(
      IriTerm shardDocumentIri) async {
    final cacheKey = shardDocumentIri.value;

    // Check cache first
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    // Resolve from storage
    final properties = await _resolveFromStorage(shardDocumentIri);

    // Update cache with LRU eviction
    _cache[cacheKey] = properties;

    return properties;
  }

  /// Resolves indexed properties by loading documents from storage.
  Future<IndexProperties> _resolveFromStorage(IriTerm shardDocumentIri) async {
    // 1. Load shard document
    final shardDoc = await _storage.getDocument(shardDocumentIri);
    if (shardDoc == null) {
      return (null, const <IriTerm>{});
    }

    final shardGraph = shardDoc.document;
    final shardResourceIri = shardGraph.expectSingleObject<IriTerm>(
        shardDocumentIri, SyncManagedDocument.foafPrimaryTopic)!;

    // 2. Get parent index IRI via idx:isShardOf
    final indexIri = shardGraph.findSingleObject<IriTerm>(
      shardResourceIri,
      IdxShard.isShardOf,
    );

    if (indexIri == null) {
      return (null, const <IriTerm>{});
    }

    // 3. Load parent index document
    final parentIndexDocumentIri = indexIri.getDocumentIri();
    final indexDoc = await _storage.getDocument(parentIndexDocumentIri);
    if (indexDoc == null) {
      return (null, const <IriTerm>{});
    }

    final indexGraph = indexDoc.document;

    // 4. Check if this is a GroupIndex that needs template resolution
    final indexTypes = indexGraph.getMultiValueObjects<IriTerm>(
      indexIri,
      Rdf.type,
    );

    IriTerm indexOrTemplateIri = indexIri;
    RdfGraph indexOrTemplateGraph = indexGraph;

    if (indexTypes.contains(IdxGroupIndex.classIri)) {
      // Follow idx:basedOn to get template
      final templateIri = indexGraph.findSingleObject<IriTerm>(
        indexIri,
        IdxGroupIndex.basedOn,
      );

      if (templateIri != null) {
        final templateDocumentIri = templateIri.getDocumentIri();
        final templateDoc = await _storage.getDocument(templateDocumentIri);
        if (templateDoc != null) {
          indexOrTemplateIri = templateIri;
          indexOrTemplateGraph = templateDoc.document;
        }
      }
    }

    // 5. Extract idx:indexedProperty list
    final properties = _extractIndexedProperties(
      indexOrTemplateGraph,
      indexOrTemplateIri,
    );

    return (indexIri, properties);
  }

  /// Extracts property IRIs from idx:indexedProperty blank nodes.
  ///
  /// Structure in RDF:
  /// ```turtle
  /// <index> idx:indexedProperty [
  ///   idx:trackedProperty schema:name
  /// ], [
  ///   idx:trackedProperty schema:keywords
  /// ] .
  /// ```
  Set<IriTerm> _extractIndexedProperties(
    RdfGraph indexGraph,
    IriTerm indexResourceIri,
  ) {
    final properties = <IriTerm>{};

    // Get all idx:indexedProperty blank nodes
    final indexedPropertyNodes = indexGraph.getMultiValueObjects<RdfSubject>(
      indexResourceIri,
      IdxFullIndex.indexedProperty,
    );

    // For each blank node, extract idx:trackedProperty
    for (final propertyNode in indexedPropertyNodes) {
      final trackedProperty = indexGraph.findSingleObject<IriTerm>(
        propertyNode,
        Idx.trackedProperty,
      );

      if (trackedProperty != null) {
        properties.add(trackedProperty);
      }
    }

    return properties;
  }

  /// Clears the cache. Useful for testing or when indices are rebuilt.
  void clearCache() {
    _cache.clear();
  }
}
