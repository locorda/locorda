/// Discovers indices from storage for a given indexed class.
///
/// This class queries the index-of-indices (fullIndices and groupIndexTemplates)
/// to find which indices exist for a resource type, then loads and parses those
/// index documents to provide complete configuration objects.
///
/// This enables dynamic index discovery during sync, allowing the system to
/// work with both own and foreign application indices without compile-time
/// configuration.
///
/// Performance: Uses watch-based caching for IRI mapping to enable fast lookups
/// during frequent ShardDeterminer calls (every sync, every user update).
library;

import 'dart:async';

import 'package:locorda_core/locorda_core.dart';
import 'package:locorda_core/src/generated/_index.dart';
import 'package:locorda_core/src/index/index_parser.dart';
import 'package:locorda_core/src/index/index_rdf_generator.dart';
import 'package:locorda_core/src/index/shard_determiner.dart'
    show ShardDeterminationMode;
import 'package:locorda_core/src/rdf/rdf_extensions.dart';
import 'package:locorda_core/src/storage/storage_interface.dart'
    show IndexEntryWithIri;
import 'package:locorda_core/src/util/build_effective_config.dart';
import 'package:logging/logging.dart';
import 'package:rdf_core/rdf_core.dart';

final _log = Logger('IndexDiscovery');

/// Discovers indices from storage for resource types.
///
/// Queries the index-of-indices meta-indices to find existing indices,
/// then loads and parses the index documents to provide configuration objects.
///
/// Uses watch-based caching for fast indexed class → index IRI lookups,
/// critical for performance as this is called for every document during sync.
class IndexDiscovery {
  final Storage _storage;
  final IndexParser _parser;
  final IndexRdfGenerator _rdfGenerator;
  final SyncGraphConfig _config;

  /// Watch-based cache: indexed class → set of FullIndex IRIs
  ///
  /// Updated automatically via storage watches on the fullIndices index-of-indices.
  /// Only contains entries for resource types configured in effectiveConfig.
  final Map<IriTerm, Set<IriTerm>> _indexedClassToFullIndexIris = {};

  /// Watch-based cache: indexed class → set of GroupIndexTemplate IRIs
  ///
  /// Updated automatically via storage watches on the groupIndexTemplates index-of-indices.
  /// Only contains entries for resource types configured in effectiveConfig.
  final Map<IriTerm, Set<IriTerm>> _indexedClassToTemplateIris = {};

  /// Subscriptions to storage watches for automatic cache updates
  late final List<StreamSubscription> _watchSubscriptions;

  IndexDiscovery({
    required Storage storage,
    required IndexParser parser,
    required IndexRdfGenerator rdfGenerator,
    required SyncGraphConfig config,
  })  : _storage = storage,
        _parser = parser,
        _rdfGenerator = rdfGenerator,
        _config = config {
    _watchSubscriptions = _initializeWatches();
  }

  /// Dispose of watch subscriptions
  Future<void> dispose() async {
    for (final subscription in _watchSubscriptions) {
      await subscription.cancel();
    }
    _watchSubscriptions.clear();
  }

  /// Initializes storage watches for index-of-indices.
  ///
  /// Sets up reactive watches on:
  /// 1. fullIndices index-of-indices → updates _indexedClassToFullIndexIris
  /// 2. groupIndexTemplates index-of-indices → updates _indexedClassToTemplateIris
  ///
  /// Only tracks resource types configured in effectiveConfig to minimize memory.
  ///
  /// Throws [StateError] if index-of-indices IRIs cannot be found in config.
  List<StreamSubscription> _initializeWatches() {
    // Get the IRIs of the index-of-indices themselves
    final fullIndicesIndexIri = _getIndexIriByLocalName(IndexNames.fullIndices);
    final groupIndexTemplatesIndexIri =
        _getIndexIriByLocalName(IndexNames.groupIndexTemplates);

    if (fullIndicesIndexIri == null || groupIndexTemplatesIndexIri == null) {
      throw StateError('Index-of-indices not found in config. '
          'Missing: ${fullIndicesIndexIri == null ? IndexNames.fullIndices : ''} '
          '${groupIndexTemplatesIndexIri == null ? IndexNames.groupIndexTemplates : ''}. '
          'Ensure buildEffectiveConfig() is used to add framework-owned resources.');
    }
    final watchSubscriptions = <StreamSubscription>[];

    // Watch fullIndices index-of-indices
    final fullIndicesSubscription = _storage.watchIndexEntries(
      indexIris: [fullIndicesIndexIri],
      cursorTimestamp: null, // Start from beginning
    ).listen(
      (entries) => _updateIndexIriCache(
        entries,
        _indexedClassToFullIndexIris,
        'FullIndex',
      ),
      onError: (error, stackTrace) {
        _log.severe(
            'Error watching fullIndices index-of-indices', error, stackTrace);
      },
    );
    watchSubscriptions.add(fullIndicesSubscription);

    // Watch groupIndexTemplates index-of-indices
    final templatesSubscription = _storage.watchIndexEntries(
      indexIris: [groupIndexTemplatesIndexIri],
      cursorTimestamp: null, // Start from beginning
    ).listen(
      (entries) => _updateIndexIriCache(
        entries,
        _indexedClassToTemplateIris,
        'GroupIndexTemplate',
      ),
      onError: (error, stackTrace) {
        _log.severe('Error watching groupIndexTemplates index-of-indices',
            error, stackTrace);
      },
    );
    watchSubscriptions.add(templatesSubscription);

    _log.fine('Initialized index-of-indices watches');
    return watchSubscriptions;
  }

  /// Updates the cache map based on index entries from storage watches.
  ///
  /// Process:
  /// 1. For each entry, extract idx:indexesClass from headerProperties
  /// 2. Update cache: indexedClass → set of index IRIs
  /// 3. Handle deletions (isDeleted flag)
  /// 4. Filter to only configured resource types
  ///
  /// Error handling: Always strict - watches run continuously in background,
  /// so data consistency is critical. Any issues indicate corrupted state.
  Future<void> _updateIndexIriCache(
    List<IndexEntryWithIri> entries,
    Map<IriTerm, Set<IriTerm>> cache,
    String indexTypeName,
  ) async {
    for (final entry in entries) {
      final indexIri = entry.resourceIri;

      if (entry.isDeleted) {
        // Remove from cache
        _removeIndexFromCache(cache, indexIri);
        _log.fine('Removed $indexTypeName from cache: $indexIri');
        continue;
      }

      // Strict: headerProperties must be present (it's a tracked property)
      if (entry.headerProperties == null) {
        throw StateError(
            'Index entry missing headerProperties (idx:indexesClass is tracked): $indexIri');
      }

      final headerProperties = turtle.decode(entry.headerProperties!);
      final indexedClassTriples =
          headerProperties.findTriples(predicate: Idx.indexesClass);

      // Strict: indexesClass must be present and unique
      if (indexedClassTriples.isEmpty) {
        throw StateError(
            '$indexTypeName missing idx:indexesClass property: $indexIri');
      }
      if (indexedClassTriples.length > 1) {
        throw StateError(
            '$indexTypeName has multiple idx:indexesClass values: $indexIri');
      }

      final indexedClass = indexedClassTriples.single.object;
      if (indexedClass is! IriTerm) {
        throw StateError(
            '$indexTypeName idx:indexesClass is not an IRI: $indexIri → $indexedClass');
      }

      // Only track if this resource type is in our config
      if (!_isConfiguredResourceType(indexedClass)) {
        _log.fine(
            'Skipping $indexTypeName for unconfigured resource type: $indexedClass');
        continue;
      }

      // Update cache
      cache.putIfAbsent(indexedClass, () => {}).add(indexIri);
      _log.fine('Added $indexTypeName to cache: $indexedClass → $indexIri');
    }
  }

  /// Removes an index IRI from the cache.
  void _removeIndexFromCache(
      Map<IriTerm, Set<IriTerm>> cache, IriTerm indexIri) {
    // Find and remove the IRI from all sets
    for (final set in cache.values) {
      set.remove(indexIri);
    }
    // Remove empty sets
    cache.removeWhere((key, value) => value.isEmpty);
  }

  /// Checks if a resource type is configured in effectiveConfig.
  bool _isConfiguredResourceType(IriTerm typeIri) {
    return _config.resources.any((r) => r.typeIri == typeIri);
  }

  /// Gets an index IRI by its local name from the config.
  ///
  /// Uses IndexRdfGenerator to compute the canonical IRI for the index.
  IriTerm? _getIndexIriByLocalName(String localName) {
    for (final resourceConfig in _config.resources) {
      for (final indexConfig in resourceConfig.indices) {
        if (indexConfig.localName == localName) {
          // Generate the IRI using the same logic as when creating the index
          return _rdfGenerator.generateIndexOrTemplateIri(
            indexConfig,
            resourceConfig.typeIri,
          );
        }
      }
    }
    return null;
  }

  /// Discovers all indices for the given indexed class.
  ///
  /// Process:
  /// 1. Look up FullIndex IRIs from watch-based cache (fast, synchronous)
  /// 2. Look up GroupIndexTemplate IRIs from watch-based cache (fast, synchronous)
  /// 3. Load and parse each index/template document
  /// 4. Return complete configuration objects
  ///
  /// Returns an iterable of CrdtIndexGraphConfig (FullIndexGraphConfig or GroupIndexGraphConfig).
  /// Returns empty iterable if no indices are found.
  ///
  /// Performance: Fast synchronous cache lookups for IRI resolution,
  /// then async document loading and parsing on-demand.
  ///
  /// Error handling depends on [mode]:
  /// - Strict: Throws on missing documents or parse errors (sync context)
  /// - Lenient: Logs warnings and skips problematic indices (user-save context)
  Future<Iterable<CrdtIndexGraphConfig>> discoverIndices(
    IriTerm indexedClass, {
    ShardDeterminationMode mode = ShardDeterminationMode.lenient,
  }) async {
    final configs = <CrdtIndexGraphConfig>[];

    // Fast synchronous lookups from watch-based caches
    final fullIndexIris = _indexedClassToFullIndexIris[indexedClass] ?? {};
    final templateIris = _indexedClassToTemplateIris[indexedClass] ?? {};

    _log.fine('Discovered ${fullIndexIris.length} FullIndex + '
        '${templateIris.length} GroupIndexTemplate for $indexedClass');

    // Load and parse FullIndex documents
    for (final indexIri in fullIndexIris) {
      final config = await _loadAndParseFullIndex(indexIri, mode: mode);
      if (config != null) {
        configs.add(config);
      }
    }

    // Load and parse GroupIndexTemplate documents
    for (final templateIri in templateIris) {
      final config = await _loadAndParseTemplate(templateIri, mode: mode);
      if (config != null) {
        configs.add(config);
      }
    }

    return configs;
  }

  /// Loads and parses a FullIndex document.
  ///
  /// Error handling depends on [mode]:
  /// - Strict: Throws if document missing or parse fails
  /// - Lenient: Returns null and logs warning
  Future<FullIndexGraphConfig?> _loadAndParseFullIndex(
    IriTerm indexIri, {
    required ShardDeterminationMode mode,
  }) async {
    final documentIri = indexIri.getDocumentIri();
    final doc = await _storage.getDocument(documentIri);

    if (doc == null) {
      final message = 'FullIndex document not found: $documentIri';
      if (mode == ShardDeterminationMode.strict) {
        throw StateError('$message (strict mode)');
      }
      _log.warning('$message (lenient mode)');
      return null;
    }

    try {
      final parsed = _parser.parseFullIndex(doc.document, indexIri);
      if (parsed == null) {
        final message = 'Failed to parse FullIndex: $indexIri';
        if (mode == ShardDeterminationMode.strict) {
          throw StateError('$message (strict mode)');
        }
        _log.warning('$message (lenient mode)');
        return null;
      }
      return parsed.config;
    } catch (e, st) {
      final message = 'Error parsing FullIndex: $indexIri';
      if (mode == ShardDeterminationMode.strict) {
        _log.severe('$message (strict mode)', e, st);
        rethrow;
      }
      _log.warning('$message (lenient mode)', e, st);
      return null;
    }
  }

  /// Loads and parses a GroupIndexTemplate document.
  ///
  /// Error handling depends on [mode]:
  /// - Strict: Throws if document missing or parse fails
  /// - Lenient: Returns null and logs warning
  Future<GroupIndexGraphConfig?> _loadAndParseTemplate(
    IriTerm templateIri, {
    required ShardDeterminationMode mode,
  }) async {
    final documentIri = templateIri.getDocumentIri();
    final doc = await _storage.getDocument(documentIri);

    if (doc == null) {
      final message = 'GroupIndexTemplate document not found: $documentIri';
      if (mode == ShardDeterminationMode.strict) {
        throw StateError('$message (strict mode)');
      }
      _log.warning('$message (lenient mode)');
      return null;
    }

    try {
      final parsed = _parser.parseGroupIndexTemplate(doc.document, templateIri);
      if (parsed == null) {
        final message = 'Failed to parse GroupIndexTemplate: $templateIri';
        if (mode == ShardDeterminationMode.strict) {
          throw StateError('$message (strict mode)');
        }
        _log.warning('$message (lenient mode)');
        return null;
      }
      return parsed.config;
    } catch (e, st) {
      final message = 'Error parsing GroupIndexTemplate: $templateIri';
      if (mode == ShardDeterminationMode.strict) {
        _log.severe('$message (strict mode)', e, st);
        rethrow;
      }
      _log.warning('$message (lenient mode)', e, st);
      return null;
    }
  }
}
