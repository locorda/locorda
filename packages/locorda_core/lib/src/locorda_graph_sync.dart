/// Main facade for the CRDT sync system.
library;

import 'dart:async';

import 'package:locorda_core/locorda_core.dart';
import 'package:locorda_core/src/index/group_index_subscription_manager.dart';
import 'package:locorda_core/src/rdf/rdf.dart';
import 'package:logging/logging.dart';
import 'package:rdf_core/rdf_core.dart';

import 'hydration/hydration_emitter.dart';
import 'hydration/hydration_stream_manager.dart';

final _log = Logger('LocordaGraphSync');

typedef IdentifiedGraph = (IriTerm id, RdfGraph graph);

/// Main facade for the locorda system.
///
/// Provides a simple, high-level API for offline-first applications with
/// optional Solid Pod synchronization. Handles RDF mapping, storage,
/// and sync operations transparently.
class LocordaGraphSync {
  final Storage _storage;
  // ignore: unused_field
  final Backend? _backend; // TODO: Use for Remote synchronization
  final SyncGraphConfig _config;
  late final HydrationStreamManager _streamManager;
  late final HydrationEmitter _emitter;
  late final GroupIndexGraphSubscriptionManager _groupIndexManager;

  LocordaGraphSync._({
    required Storage storage,
    required Backend backend,
    required SyncGraphConfig config,
  })  : _storage = storage,
        _backend = backend,
        _config = config {
    _streamManager = HydrationStreamManager();
    _groupIndexManager = GroupIndexGraphSubscriptionManager(
      config: _config,
    );
    _emitter = HydrationEmitter(
      streamManager: _streamManager,
    );
  }

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
  }) async {
    // Validate configuration before proceeding
    final configValidationResult = SyncGraphConfigValidator().validate(config);

    // Throw if any validation failed
    configValidationResult.throwIfInvalid();

    // Initialize storage
    await storage.initialize();
    return LocordaGraphSync._(
      storage: storage,
      backend: backend,
      config: config,
    );
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
  /// listen to hydrateStreaming() to receive updates.
  ///
  /// Process:
  /// 1. CRDT processing (merge with existing, clock increment)
  /// 2. Store locally in sync system
  /// 3. Hydration stream automatically emits update
  /// 4. Schedule async Pod sync
  Future<void> save(IriTerm type, RdfGraph graph) async {
    final resourceConfig = _config.getResourceConfig(type);
    // Basic implementation to maintain hydration stream contract
    // TODO: Add proper CRDT processing and storage persistence

    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final localId = Rdf.getIdentifier(graph, type);
    // Emit data change
    _emitter.emit(
        HydrationResult<IdentifiedGraph>(
          items: [(localId, graph)],
          deletedItems: [],
          originalCursor: null,
          nextCursor: timestamp,
          hasMore: false,
        ),
        resourceConfig);
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
  /// listen to hydrateStreaming() to receive deletion notifications.
  ///
  /// Process:
  /// 1. Add crdt:deletedAt timestamp to document
  /// 2. Perform universal emptying (remove semantic content, keep framework metadata)
  /// 3. Store updated document in sync system
  /// 4. Hydration stream automatically emits deletion
  /// 5. Schedule async Pod sync
  Future<void> deleteDocument(IriTerm typeIri, IriTerm localIri) async {
    final resourceConfig = _config.getResourceConfig(typeIri);
    // Basic implementation to maintain hydration stream contract
    // TODO: Add proper CRDT deletion processing and storage persistence

    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();

    // Emit data change
    _emitter.emit(
        HydrationResult<IdentifiedGraph>(
          items: [],
          deletedItems: [
            (
              localIri,
              RdfGraph.fromTriples([Triple(localIri, Rdf.type, typeIri)])
            )
          ],
          originalCursor: null,
          nextCursor: timestamp,
          hasMore: false,
        ),
        resourceConfig);
  }

  /// Load changes from sync storage since the given cursor.
  ///
  /// Returns items that have been updated or deleted since the cursor position.
  /// Use null cursor to load from the beginning.
  Future<HydrationResult<T>> _loadChangesSince<T>(
    String? cursor, {
    int limit = 100,
  }) async {
    // TODO: Implement loading changes from sync storage
    return HydrationResult<T>(
      items: [],
      deletedItems: [],
      originalCursor: cursor,
      nextCursor: null,
      hasMore: false,
    );
  }

  /// One-time hydration that handles pagination and cursor management.
  ///
  /// This method automatically handles:
  /// - Pagination through all changes since lastCursor
  /// - Cursor management and persistence
  /// - Separate handling of updates and deletions
  ///
  /// Use this for manual hydration or catch-up scenarios. For ongoing hydration
  /// with live updates, use [hydrateStreaming] instead.
  ///
  /// Callbacks:
  /// - [onUpdate]: Called for each new/updated item
  /// - [onDelete]: Called for each deleted item (with last known state)
  /// - [onCursorUpdate]: Called to persist cursor for next hydration
  Future<void> _hydrateOnce<T>({
    required String? lastCursor,
    required Future<void> Function(T item) onUpdate,
    required Future<void> Function(T item) onDelete,
    required Future<void> Function(String cursor) onCursorUpdate,
    int batchSize = 100,
  }) async {
    String? currentCursor = lastCursor;
    HydrationResult<T> result;

    do {
      result = await _loadChangesSince<T>(currentCursor, limit: batchSize);

      // Apply updates
      for (final item in result.items) {
        await onUpdate(item);
      }

      // Apply deletions
      for (final item in result.deletedItems) {
        await onDelete(item);
      }

      // Update cursor
      if (result.nextCursor != null) {
        await onCursorUpdate(result.nextCursor!);
        currentCursor = result.nextCursor;
      }
    } while (result.hasMore);
  }

  /// Streaming hydration that performs initial catch-up and then maintains live updates.
  ///
  /// This is the recommended method for repository integration:
  /// 1. Performs catch-up hydration from lastCursor
  /// 2. Sets up live hydration stream for ongoing updates
  /// 3. Handles cursor consistency checks automatically
  ///
  /// Returns a StreamSubscription that must be managed by the caller - store it
  /// and cancel when disposing to stop the live hydration.
  ///
  /// On cursor mismatch, this method automatically triggers a refresh using the
  /// existing callbacks, so repositories don't need to handle this manually.
  ///
  /// If indexName is provided, the hydration is scoped to that index, else it
  /// is scoped to the full resource type itself.
  ///
  /// Callbacks:
  /// - [getCurrentCursor]: Should return the repository's current cursor
  /// - [onUpdate]: Called for each new/updated item
  /// - [onDelete]: Called for each deleted item (with last known state)
  /// - [onCursorUpdate]: Called to persist cursor updates
  Future<HydrationSubscription> hydrateStreaming({
    required IriTerm typeIri,
    String? indexName,
    required Future<String?> Function() getCurrentCursor,
    required Future<void> Function(IdentifiedGraph item) onUpdate,
    required Future<void> Function(IdentifiedGraph item) onDelete,
    required Future<void> Function(String cursor) onCursorUpdate,
    int batchSize = 100,
  }) async {
    // Check if T is a registered resource type
    final resourceConfig = _config.getResourceConfig(typeIri);
    if (indexName != null) {
      if (!resourceConfig.indices
          .any((index) => index.localName == indexName)) {
        throw ArgumentError(
            'No index with local name $indexName is configured for resource type $typeIri');
      }
    }
    // 1. Set up live hydration updates
    final subscription = _streamManager
        .getOrCreateController(typeIri, indexName)
        .stream
        .listen((result) async {
      // TODO: Implement proper cursor consistency checking
      // The current originalCursor check is too strict and prevents local changes
      // from being applied immediately. Need to design a better approach that:
      // 1. Allows immediate application of local changes (save/delete operations)
      // 2. Provides proper consistency checking for remote sync updates
      // 3. Handles cursor mismatches gracefully without blocking updates

      // Apply changes directly without cursor consistency check for now
      for (final item in result.items) {
        await onUpdate(item);
      }
      for (final item in result.deletedItems) {
        await onDelete(item);
      }
      if (result.nextCursor != null) {
        await onCursorUpdate(result.nextCursor!);
      }
    });

    // 2. Initial catch-up hydration
    final initialCursor = await getCurrentCursor();
    await _hydrateOnce<IdentifiedGraph>(
      lastCursor: initialCursor,
      onUpdate: onUpdate,
      onDelete: onDelete,
      onCursorUpdate: onCursorUpdate,
      batchSize: batchSize,
    );
    return _HydrationStreamSubscription(subscription);
  }

  /// Close the sync system and free resources.
  Future<void> close() async {
    await _streamManager.close();
    await _storage.close();
  }
}

class _HydrationStreamSubscription implements HydrationSubscription {
  final StreamSubscription _subscription;

  _HydrationStreamSubscription(this._subscription);

  @override
  Future<void> cancel() => _subscription.cancel();

  @override
  bool get isActive => _subscription.isPaused == false;
}
