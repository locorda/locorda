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

import 'package:locorda_core/locorda_core.dart';
import 'package:locorda_core/src/generated/_index.dart';
import 'package:locorda_core/src/rdf/rdf_extensions.dart';
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
  final ResourceLocator _resourceLocator;

  IndexPropertyResolver({
    required Storage storage,
    ResourceLocator? resourceLocator,
    int cacheSize = 100,
  })  : _storage = storage,
        _resourceLocator = resourceLocator ??
            LocalResourceLocator(iriTermFactory: IriTerm.validated),
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
    IriTerm? indexIri = await _getIndexIriForShardDocumentIri(shardDocumentIri);

    // 2. Check if we have an indexIri

    if (indexIri == null) {
      return (null, const <IriTerm>{});
    }

    // 3. Load parent index document
    final parentIndexDocumentIri = indexIri.getDocumentIri();
    final indexDoc = await _storage.getDocument(parentIndexDocumentIri);
    final indexOrTemplateIri =
        _getIndexOrTemplateIri(indexDoc, parentIndexDocumentIri, indexIri);

    final RdfGraph? indexOrTemplateGraph;
    if (indexIri == indexOrTemplateIri) {
      indexOrTemplateGraph = indexDoc?.document;
    } else {
      // Load template document
      final templateDocumentIri = indexOrTemplateIri.getDocumentIri();
      final templateDoc = await _storage.getDocument(templateDocumentIri);
      indexOrTemplateGraph = templateDoc?.document;
    }
    if (indexOrTemplateGraph == null) {
      return (null, const <IriTerm>{});
    }

    // 5. Extract idx:indexedProperty list
    final properties = _extractIndexedProperties(
      indexOrTemplateGraph,
      indexOrTemplateIri,
    );

    return (indexIri, properties);
  }

  IriTerm _getIndexOrTemplateIri(StoredDocument? indexDoc,
      IriTerm parentIndexDocumentIri, IriTerm indexIri) {
    if (indexDoc != null) {
      final indexGraph = indexDoc.document;

      // 4. Check if this is a GroupIndex that needs template resolution
      final indexTypes = indexGraph.getMultiValueObjectList<IriTerm>(
        indexIri,
        Rdf.type,
      );

      if (indexTypes.contains(IdxGroupIndex.classIri)) {
        // Follow idx:basedOn to get template
        return indexGraph.findSingleObject<IriTerm>(
              indexIri,
              IdxGroupIndex.basedOn,
            ) ??
            indexIri;
      }
      return indexIri;
    }
    if (!_resourceLocator.isIdentifiableIri(parentIndexDocumentIri)) {
      return indexIri;
    }
    // Index document not found - try to infer template IRI for GroupIndex
    final ri = _resourceLocator.fromIri(parentIndexDocumentIri);
    final parentType = ri.typeIri;
    final parentId = ri.id;
    if (parentType == IdxGroupIndex.classIri && parentId.contains('/')) {
      // ok, this is a group index - we try to infer the template IRI.
      // It probably is something like "index-grouped-e093655c/groups/20_ad221effd73057a647d96bab312c4886/index"
      // and the templateId then "index-grouped-e093655c/index"
      final templateId = '${parentId.split('/')[0]}/index';
      return _resourceLocator.toIri(ResourceIdentifier(
          IdxGroupIndexTemplate.classIri, templateId, 'groupIndexTemplate'));
    }
    return indexIri;
  }

  Future<IriTerm?> _getIndexIriForShardDocumentIri(
      IriTerm shardDocumentIri) async {
    // 1. Load shard document
    final shardDoc = await _storage.getDocument(shardDocumentIri);
    if (shardDoc != null) {
      final shardGraph = shardDoc.document;
      final shardResourceIri = shardGraph.expectSingleObject<IriTerm>(
          shardDocumentIri, SyncManagedDocument.foafPrimaryTopic)!;

      // 2. Get parent index IRI via idx:isShardOf
      return shardGraph.findSingleObject<IriTerm>(
        shardResourceIri,
        IdxShard.isShardOf,
      );
    }
    // Shard document not found - maybe it is a shard of a foreign index
    // which we did not download. In this case, we try to infer the index IRI
    // from the shard IRI structure
    // Id will be something like `index-full-5f68b5b7/shard-mod-md5-1-0-v1_0_0` for full index
    // or `index-grouped-e093655c/groups/20_ad221effd73057a647d96bab312c4886/shard-mod-md5-1-0-v1_0_0` for group index
    if (!_resourceLocator.isIdentifiableIri(shardDocumentIri)) {
      return null;
    }
    final iri = _resourceLocator.fromIri(shardDocumentIri,
        expectedTypeIri: IdxShard.classIri);
    final shardId = iri.id;
    final type = shardId.startsWith('index-full-')
        ? IdxFullIndex.classIri
        : shardId.startsWith('index-grouped-')
            ? IdxGroupIndex.classIri
            : null;

    if (type != null && shardId.contains('/')) {
      // ok - this looks good. Continue
      final indexId =
          shardId.substring(0, shardId.lastIndexOf('/') + 1) + 'index';

      return _resourceLocator.toIri(ResourceIdentifier(type, indexId, "index"));
    }
    return null;
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
    final indexedPropertyNodes = indexGraph.getMultiValueObjectList<RdfSubject>(
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
