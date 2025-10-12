/// Main facade for the CRDT sync system.
library;

import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:locorda_core/locorda_core.dart';
import 'package:locorda_core/src/crdt/crdt_types.dart';
import 'package:locorda_core/src/crdt_document_manager.dart';
import 'package:locorda_core/src/generated/_index.dart';
import 'package:locorda_core/src/hlc_service.dart';
import 'package:locorda_core/src/index/group_index_subscription_manager.dart';
import 'package:locorda_core/src/index/index_manager.dart';
import 'package:locorda_core/src/index/index_rdf_generator.dart';
import 'package:locorda_core/src/index/shard_manager.dart';
import 'package:locorda_core/src/installation_service.dart'
    show InstallationService, InstallationIdFactory;
import 'package:locorda_core/src/mapping/iri_translator.dart';
import 'package:locorda_core/src/mapping/merge_contract_loader.dart';
import 'package:locorda_core/src/mapping/recursive_rdf_loader.dart';
import 'package:locorda_core/src/rdf/rdf_extensions.dart';
import 'package:logging/logging.dart';
import 'package:rdf_core/rdf_core.dart';

final _log = Logger('LocordaGraphSync');

typedef IdentifiedGraph = (IriTerm id, RdfGraph graph);
typedef HydrationBatch = ({
  List<IdentifiedGraph> updates,
  List<IdentifiedGraph> deletions,
  String? cursor
});

/// Main facade for the locorda system.
///
/// Provides a simple, high-level API for offline-first applications with
/// optional Solid Pod synchronization. Handles RDF mapping, storage,
/// and sync operations transparently.
class LocordaGraphSync {
  // ignore: unused_field
  final Backend _backend; // TODO: Use for Remote synchronization
  final Storage _storage;
  final IndexManager _indexManager;
  final SyncGraphConfig _config;
  final CrdtDocumentManager _crdtDocumentManager;
  final IriTranslator _iriTranslator;
  final GroupIndexGraphSubscriptionManager _groupIndexManager;
  final SyncManager _syncManager;

  /// Access the sync manager for manual sync triggering and status monitoring.
  SyncManager get syncManager => _syncManager;

  LocordaGraphSync._({
    required Backend backend,
    required Storage storage,
    required IndexManager indexManager,
    required SyncGraphConfig config,
    required ResourceLocator resourceLocator,
    required CrdtDocumentManager crdtDocumentManager,
  })  : _backend = backend,
        _storage = storage,
        _indexManager = indexManager,
        _config = config,
        _groupIndexManager = GroupIndexGraphSubscriptionManager(
          config: config,
        ),
        _iriTranslator = IriTranslator(
          resourceLocator: resourceLocator,
          resourceConfigs: config.resources,
        ),
        _crdtDocumentManager = crdtDocumentManager,
        _syncManager = SyncManager(
          syncFunction: () async {
            // TODO: Implement actual sync logic here
            // For now, this is a placeholder that will be implemented in Priority 4
            _log.info('Sync triggered (not yet implemented)');
            await Future.delayed(Duration(milliseconds: 100));
          },
          autoSyncConfig: config.autoSyncConfig,
        );

  /// Set up the CRDT sync system with resource-focused configuration.
  ///
  /// This is the main entry point for applications. Creates a fully
  /// configured sync system that works locally by default.
  ///
  /// Configuration is organized around resources (Note, Category, etc.)
  /// with their paths, CRDT mappings, and indices all defined together.
  ///
  /// Throws [SyncConfigValidationException] if the configuration is invalid.
  static Future<LocordaGraphSync> setup({
    required Backend backend,
    required Storage storage,
    required SyncGraphConfig config,
    PhysicalTimestampFactory? physicalTimestampFactory,
    InstallationIdFactory? installationIdFactory,
    IriTermFactory? iriFactory,
    RdfCore? rdfCore,
    http.Client? httpClient,
    Fetcher? fetcher,
  }) async {
    rdfCore ??= RdfCore.withStandardCodecs();
    httpClient ??= http.Client();
    fetcher ??= HttpFetcher(httpClient: httpClient);
    iriFactory ??= IriTerm.validated;
    physicalTimestampFactory ??= defaultPhysicalTimestampFactory;

    // Automatically add configuration for Framework-Owned resources
    final effectiveConfig = config.withResourcesAdded([
      ResourceGraphConfig(
        typeIri: CrdtClientInstallation.classIri,
        crdtMapping: Uri.parse(
            'https://w3id.org/solid-crdt-sync/mappings/client-installation-v1'),
        indices: [
          FullIndexGraphConfig(
              localName: 'lcrd-installation-index',
              itemFetchPolicy: ItemFetchPolicy.onRequest)
        ],
      ),
      ResourceGraphConfig(
          typeIri: IdxShard.classIri,
          crdtMapping:
              Uri.parse('https://w3id.org/solid-crdt-sync/mappings/shard-v1'),
          // No indices for shards
          indices: []),
      ResourceGraphConfig(
          typeIri: IdxFullIndex.classIri,
          crdtMapping:
              Uri.parse('https://w3id.org/solid-crdt-sync/mappings/index-v1'),
          // No indices for indices
          indices: []),
      ResourceGraphConfig(
          typeIri: IdxGroupIndexTemplate.classIri,
          crdtMapping:
              Uri.parse('https://w3id.org/solid-crdt-sync/mappings/index-v1'),
          // No indices for indices
          indices: []),
      ResourceGraphConfig(
          typeIri: IdxGroupIndex.classIri,
          crdtMapping:
              Uri.parse('https://w3id.org/solid-crdt-sync/mappings/index-v1'),
          // No indices for indices
          indices: []),
    ]);

    // Validate configuration before proceeding
    final configValidationResult =
        SyncGraphConfigValidator().validate(effectiveConfig);

    // Throw if any validation failed
    configValidationResult.throwIfInvalid();

    // Initialize storage
    await storage.initialize();

    final localResourceLocator =
        LocalResourceLocator(iriTermFactory: iriFactory);
    // Initialize installation service
    final installationService = await InstallationService.create(
      storage: storage,
      resourceLocator: localResourceLocator,
      installationIdFactory: installationIdFactory,
      iriTermFactory: iriFactory,
      physicalTimestampFactory: physicalTimestampFactory,
    );

    // Create HlcService with installation IRI and localId
    final hlcService = HlcService(
      installationLocalId: installationService.installationLocalId,
      physicalTimestampFactory: physicalTimestampFactory,
    );
    final crdtTypeRegistry = CrdtTypeRegistry.forStandardTypes(
        physicalTimestampFactory: physicalTimestampFactory);

    // TODO: the HttpRdfGraphFetcher should be db-cached (ideally with initialization from deployment and etag)
    final mergeContractLoader = StandardMergeContractLoader(
        RecursiveRdfLoader(
            fetcher:
                StandardRdfGraphFetcher(fetcher: fetcher, rdfCore: rdfCore),
            iriFactory: iriFactory),
        crdtTypeRegistry);

    final shardManager = const ShardManager();
    final indexRdfGenerator = IndexRdfGenerator(
        resourceLocator: localResourceLocator, shardManager: shardManager);

    final crdtDocumentManager = CrdtDocumentManager(
      storage: storage,
      config: effectiveConfig,
      physicalTimestampFactory: physicalTimestampFactory,
      resourceLocator: localResourceLocator,
      mergeContractLoader: CachingMergeContractLoader(mergeContractLoader),
      crdtTypeRegistry: crdtTypeRegistry,
      hlcService: hlcService,
      iriTermFactory: iriFactory,
      indexRdfGenerator: indexRdfGenerator,
    );

    // Initialize indices after installation document is created
    final indexManager = IndexManager(
        crdtDocumentManager: crdtDocumentManager,
        rdfGenerator: indexRdfGenerator,
        storage: storage,
        installationIri: installationService.installationIri,
        config: effectiveConfig);

    await indexManager.initializeIndices();

    final sync = LocordaGraphSync._(
        backend: backend,
        storage: storage,
        indexManager: indexManager,
        config: effectiveConfig,
        resourceLocator: localResourceLocator,
        crdtDocumentManager: crdtDocumentManager);

    // installation documents might be organized in indices, so we need to use graph sync instead of crdtDocumentManager directly
    await installationService.ensureDocumentSaved(sync);

    return sync;
  }

  /// Configure subscription to a group index with the given group key.
  ///
  /// ## Group Index Subscription Overview
  ///
  /// Group subscriptions determine how items within a group are fetched and synced:
  ///
  /// **Default State**: Groups are not subscribed by default. Items can still be
  /// accessed on-demand, but no automatic sync or prefetching occurs.
  ///
  /// **Implicit Subscriptions**: When individual items are fetched, groups they
  /// belong to (via their `idx:belongsToIndexShard` properties) are automatically subscribed
  /// with `ItemFetchPolicy.onRequest`. This ensures basic sync functionality.
  ///
  /// **Explicit Configuration**: This method allows you to explicitly configure
  /// a group's subscription with a specific fetch policy:
  /// - `ItemFetchPolicy.onRequest`: Fetch items only when specifically requested
  /// - `ItemFetchPolicy.prefetch`: Eagerly fetch all items in the group
  ///
  /// ## Subscription Lifecycle
  ///
  /// - **Create**: First call creates subscription with specified policy
  /// - **Update**: Subsequent calls update the fetch policy
  /// - **Persistence**: Subscriptions persist across app restarts
  /// - **No Unsubscribe**: Once subscribed, groups cannot be unsubscribed as
  ///   the subscription is required for proper sync management of items
  ///
  /// ## Technical Details
  ///
  /// Validates that G is a valid group type for the specified localName,
  /// converts the group key to RDF triples, and generates group identifiers
  /// using the configured GroupKeyGenerator.
  ///
  /// ## Example
  /// ```dart
  /// // Configure current month for eager fetching
  /// await syncSystem.configureGroupIndexSubscription(
  ///   NoteGroupKey.currentMonth,
  ///   ItemFetchPolicy.prefetch
  /// );
  ///
  /// // Later, change to on-demand fetching
  /// await syncSystem.configureGroupIndexSubscription(
  ///   NoteGroupKey.currentMonth,
  ///   ItemFetchPolicy.onRequest
  /// );
  /// ```
  ///
  /// Throws [GroupIndexGraphSubscriptionException] if:
  /// - No GroupIndex is configured for type G with the given localName
  /// - The group key cannot be serialized to RDF
  /// - No group identifiers can be generated from the group key
  ///
  Future<void> configureGroupIndexSubscription(String indexName,
      RdfGraph groupKeyGraph, ItemFetchPolicy itemFetchPolicy) async {
    // Use the GroupIndexSubscriptionManager to handle validation and processing
    final groupIdentifiers =
        await _groupIndexManager.getGroupIdentifiers(indexName, groupKeyGraph);
    _log.info(
        'configure called for index: $indexName and group key: $groupKeyGraph, resolved to group identifiers: $groupIdentifiers');
    // TODO: Implement actual subscription logic with itemFetchPolicy
    // This should:
    // 1. Load existing items for the generated group identifiers
    // 2. Set up hydration streams for the group
    // 3. Apply the ItemFetchPolicy (OnDemand, Eager, etc.)
    // 4. Schedule sync operations if connected to Pod

    //return groupIdentifiers;
  }

  /// Save an object with CRDT processing.
  ///
  /// Stores the object locally and triggers sync if connected to Solid Pod.
  /// Application state is updated via the hydration stream - repositories should
  /// listen to hydrateStream() to receive updates.
  ///
  /// Process:
  /// 1. CRDT processing (merge with existing, clock increment)
  /// 2. Store locally in sync system
  /// 3. Hydration stream automatically emits update
  /// 4. Schedule async Pod sync
  Future<void> save(IriTerm type, RdfGraph appData) async {
    // 1. Translate external IRIs to internal format if documentIriTemplate is configured
    final internalAppData = _iriTranslator.translateGraphToInternal(appData);

    // 2. Extract resource IRI to determine shards
    final resourceIri = internalAppData.getIdentifier(type);
    if (!LocalResourceLocator.isLocalIri(resourceIri)) {
      throw ArgumentError('''
Cannot save resource with non-local IRI $resourceIri. Only local IRIs are supported for save(). 

Use the 'documentIriTemplate' property of the resource configuration to configure automatic IRI translation from your IRI to the internal format on save().
''');
    }

    // 4. save (with CRDT processing, diffing etc)
    final saved = await _crdtDocumentManager.save(type, internalAppData);
    if (saved == null) {
      // nothing changed, nothing to do
      return;
    }

    // 4a. Create any missing GroupIndex documents that were detected during save
    // This must happen before updateIndices so the shards exist
    for (final missing in saved.missingGroupIndices) {
      _log.info(
          'Creating missing GroupIndex for group "${missing.groupKey}" at ${missing.groupIndexIri}');
      await _indexManager.createMissingGroupIndex(missing);
    }

    final crdtDocument = saved.crdtDocument;
    final documentIri = saved.documentIri;

    // 4. Update the Index Shards
    final allShards = crdtDocument.getMultiValueObjects<IriTerm>(
        documentIri, SyncManagedDocument.idxBelongsToIndexShard);

    // Extract clock hash from the saved document
    final clockHashLiteral = crdtDocument.findSingleObject<LiteralTerm>(
        documentIri, SyncManagedDocument.crdtClockHash);
    final clockHash = clockHashLiteral?.value;
    if (clockHash == null) {
      throw StateError(
          'Saved document $documentIri is missing crdt:clockHash, cannot update indices.');
    }

    // 4a. Remove entries from shards where belongsToIndexShard was removed
    // This must happen BEFORE updateIndices to ensure tombstones are created first
    await _indexManager.removeTombstonedShardEntries(
        resourceIri, crdtDocument, documentIri);

    // 5. Update the indices
    await _indexManager.updateIndices(
        type, resourceIri, clockHash, internalAppData, allShards);

    // Note: No manual emission needed - Drift's watch() streams will automatically
    // detect the database changes and emit updates to any active hydration subscriptions
  }

  /// Ensures a resource is available locally, fetching it from the remote source if necessary.
  ///
  /// This method guarantees that after its successful completion, the requested
  /// resource will exist in the local database and be managed by the sync system.
  /// It follows a "offline-first" approach.
  ///
  /// The process is as follows:
  /// 1. It first attempts to retrieve the item from the local database using the
  ///    provided [loadFromLocal] function.
  /// 2. If the item is found locally, it is returned immediately.
  /// 3. If the item is not found locally, this method triggers a fetch from the
  ///    remote Solid Pod.
  /// 4. Once fetched, the item is processed and inserted into the local database
  ///    via the standard hydration stream, which in turn makes it available to the
  ///    rest of the application.
  /// 5. The method then returns the newly fetched and stored item.
  ///
  /// This is the primary method repositories should use for on-demand loading of
  /// individual resources that may not be part of an eagerly synced group. It
  /// abstracts away all the complexity of network requests, caching, and state
  /// management.
  ///
  /// Throws a [TimeoutException] if the remote fetch takes too long.
  ///
  ///
  /// #### Parameters:
  ///   - [id]: The unique identifier of the resource to ensure is available.
  ///   - [loadFromLocal]: A callback function that takes the resource `id` and
  ///     is responsible for loading it from the local application database.
  ///
  /// #### Returns:
  /// A `Future` that completes with the resource of type [T] once it is available
  /// locally. Returns `null` if the resource cannot be found either locally or
  /// remotely, or if the request times out.
  ///
  /// #### Example:
  ///
  /// ```dart
  /// // Inside a repository class
  ///
  /// Future<Note?> getNoteById(String noteId) async {
  ///   return await _syncSystem.ensure<Note>(
  ///     noteId,
  ///     loadFromLocal: (id) async {
  ///       final driftNote = await _noteDao.getNoteById(id);
  ///       return driftNote != null ? _noteFromDrift(driftNote) : null;
  ///     },
  ///   );
  /// }
  /// ```
  Future<RdfGraph?> ensure(IriTerm typeIri, IriTerm localIri,
      {required Future<RdfGraph?> Function(IriTerm localIri) loadFromLocal,
      Duration? timeout = const Duration(seconds: 15),
      bool skipInitialFetch = false}) async {
    // 1. First, try to load from the local database.
    final localItem = skipInitialFetch ? null : await loadFromLocal(localIri);
    if (localItem != null) {
      return localItem;
    }

    // TODO: properly implement remote fetch with pending fetch tracking
/*
Check with https://g.co/gemini/share/60e9b2d3036e for the details

    // 2. If not found, check if a fetch is already in progress.
    if (_pendingFetches.containsKey(id)) {
      return (await _pendingFetches[id]!.future) as T?;
    }

    // 3. If not, initiate a new fetch.
    final completer = Completer<T?>();
    _pendingFetches[id] = completer;

    // 4. Trigger the remote fetch in the background.
    // (This reuses the logic from the previous proposal)
    _fetchAndEmit<T>(id);

    // 5. Return the future, which completes when the item arrives.
    return completer.future.timeout(const Duration(seconds: 15), onTimeout: () {
      _pendingFetches.remove(id);
      // Return null or throw a custom exception on timeout.
      return null;
    });

    */
    return null;
  }

  /// Delete a document with CRDT processing.
  ///
  /// This performs document-level deletion, marking the entire document as deleted
  /// and affecting all resources contained within, following CRDT semantics.
  /// Application state is updated via the hydration stream - repositories should
  /// listen to hydrateStream() to receive deletion notifications.
  ///
  /// Process:
  /// 1. Add crdt:deletedAt timestamp to document
  /// 2. Perform universal emptying (remove semantic content, keep framework metadata)
  /// 3. Store updated document in sync system
  /// 4. Hydration stream automatically emits deletion (via Drift's reactive queries)
  /// 5. Schedule async Pod sync
  Future<void> deleteDocument(IriTerm typeIri, IriTerm externalIri) async {
    // Translate external IRI to internal format
    // ignore: unused_local_variable
    final internalIri = _iriTranslator.externalToInternal(externalIri);

    // ignore: unused_local_variable
    final resourceConfig = _config.getResourceConfig(typeIri);

    // TODO: Implement proper CRDT deletion processing:
    // 1. Load existing document
    // 2. Add crdt:deletedAt timestamp
    // 3. Perform universal emptying (remove semantic content, keep framework metadata)
    // 4. Save to storage (this will trigger Drift's watch() to emit updates automatically)
    // 5. Update indices accordingly

    throw UnimplementedError('deleteDocument not yet fully implemented');
  }

  /// Hydrates resources of the specified type using a reactive stream.
  ///
  /// Returns a stream of [HydrationBatch]es containing updates, deletions,
  /// and cursor information. The stream automatically:
  /// - Loads all existing documents in batches (bounded by [initialBatchSize])
  /// - Switches to reactive mode for ongoing changes (via Drift's watch())
  /// - Orders documents by updatedAt ascending for consistent processing
  ///
  /// The caller is responsible for:
  /// - Providing the current cursor position via [cursor]
  /// - Processing updates and deletions from the batch
  /// - Persisting cursor updates for resume capability
  ///
  /// If [indexName] is provided, hydration would be scoped to that index,
  /// but this feature is not yet fully implemented (TODO).
  ///
  /// Example:
  /// ```dart
  /// final subscription = syncSystem.hydrateStream(
  ///   typeIri: Note.classIri,
  ///   cursor: _lastCursor,
  /// ).listen((batch) async {
  ///   for (final (iri, graph) in batch.updates) {
  ///     await _processUpdate(iri, graph);
  ///   }
  ///   for (final (iri, graph) in batch.deletions) {
  ///     await _processDeletion(iri, graph);
  ///   }
  ///   if (batch.cursor != null) {
  ///     _lastCursor = batch.cursor;
  ///   }
  /// });
  /// ```
  Stream<HydrationBatch> hydrateStream({
    required IriTerm typeIri,
    String? indexName,
    String? cursor,
    int initialBatchSize = 100,
  }) async* {
    // Validate configuration
    final resourceConfig = _config.getResourceConfig(typeIri);
    if (indexName != null) {
      if (!resourceConfig.indices
          .any((index) => index.localName == indexName)) {
        throw ArgumentError(
            'No index with local name $indexName is configured for resource type $typeIri');
      }
      // TODO: Implement index-specific hydration by loading the corresponding index shards
      throw UnimplementedError('Index-specific hydration not yet implemented');
    }

    HydrationBatch convertResult(
        List<StoredDocument> documents, String? cursor) {
      final (deletions, updates) = documents
          .fold((<IdentifiedGraph>[], <IdentifiedGraph>[]), (acc, doc) {
        // Translate internal IRIs to external format for application consumption
        final externalIri = _iriTranslator.internalToExternal(doc.documentIri);
        final externalGraph =
            _iriTranslator.translateGraphToExternal(doc.document);

        final isDeletion = externalGraph.hasTriples(
            subject: externalIri, predicate: SyncManagedDocument.crdtDeletedAt);

        (isDeletion ? acc.$1 : acc.$2).add((externalIri, externalGraph));
        return acc;
      });
      return (updates: updates, deletions: deletions, cursor: cursor);
    }

    // Phase 1: Load all existing documents in batches using pagination
    // This ensures we don't load unbounded amounts of data into memory
    while (true) {
      final result = await _storage.getDocumentsModifiedSince(
        typeIri,
        cursor,
        limit: initialBatchSize,
      );

      // Process each document in the batch
      yield convertResult(result.documents, result.currentCursor);

      cursor = result.currentCursor;

      // If there are no more documents to fetch, we've loaded everything
      if (!result.hasNext) {
        break;
      }
    }

    // Phase 2: Switch to reactive watch for ongoing changes
    // This automatically emits updates whenever documents of this type change
    yield* _storage
        .watchDocumentsModifiedSince(typeIri, cursor)
        .map((result) => convertResult(result.documents, result.currentCursor));
  }

  /// Close the sync system and free resources.
  Future<void> close() async {
    await _syncManager.dispose();
    await _crdtDocumentManager.close();
  }
}
