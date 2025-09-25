/// Main facade for the CRDT sync system.
library;

import 'dart:async';

import 'package:locorda_core/locorda_core.dart';

import 'package:locorda_core/src/generated/_index.dart';
import 'package:locorda_core/src/hlc_service.dart';
import 'package:locorda_core/src/index/group_index_subscription_manager.dart';
import 'package:locorda_core/src/rdf/rdf.dart';
import 'package:logging/logging.dart';
import 'package:rdf_core/rdf_core.dart';

import 'hydration/hydration_emitter.dart';
import 'hydration/hydration_stream_manager.dart';

final _log = Logger('LocordaGraphSync');

typedef IdentifiedGraph = (IriTerm id, RdfGraph graph);

/// Extracts document IRI from a resource IRI by removing the fragment identifier.
///
/// Validates that the resource IRI has a proper fragment identifier (e.g., #it)
/// and returns the document IRI (the part before the fragment).
///
/// Example:
/// - Input: `https://example.org/data/recipe#it`
/// - Output: `https://example.org/data/recipe`
///
/// Throws [ArgumentError] if the resource IRI doesn't have a fragment identifier.
/// TODO: Add support for blank node handling - currently only handles IriTerm resources
IriTerm _extractDocumentIri(IriTerm resourceIri) {
  final iriValue = resourceIri.value;
  final fragmentIndex = iriValue.indexOf('#');

  if (fragmentIndex == -1) {
    throw ArgumentError(
        'Resource IRI must have a fragment identifier (e.g., #it). '
        'Got: $iriValue');
  }

  if (fragmentIndex == iriValue.length - 1) {
    throw ArgumentError('Resource IRI fragment identifier cannot be empty. '
        'Got: $iriValue');
  }

  final documentIriValue = iriValue.substring(0, fragmentIndex);
  return IriTerm(documentIriValue);
}

/// Detects property-level changes between old and new RDF graphs.
///
/// Compares the triples for each resource IRI and generates PropertyChange objects
/// for any properties that have different values between the graphs.
///
/// Returns a list of PropertyChange objects representing the detected changes.
/// Each change includes the resource IRI, property IRI, and timing information.
///
/// Only handles IriTerm resources currently.
/// TODO: Add support for blank node resources using context-based identification
List<PropertyChange> _detectPropertyChanges(
  RdfGraph? oldGraph,
  RdfGraph newGraph,
  int physicalTimestamp,
  int logicalClock,
) {
  final changes = <PropertyChange>[];

  // Get all resource IRIs from the new graph
  final newResourceIris = newGraph.subjects.whereType<IriTerm>().toSet();

  // Check each resource for property changes
  for (final resourceIri in newResourceIris) {
    final oldTriples =
        oldGraph?.findTriples(subject: resourceIri) ?? <Triple>[];
    final newTriples = newGraph.findTriples(subject: resourceIri);

    // Create maps of property -> values for comparison
    final oldProperties = _groupTriplesByPredicate(oldTriples);
    final newProperties = _groupTriplesByPredicate(newTriples);

    // Check for added or modified properties
    for (final propertyIri in newProperties.keys) {
      final oldValues = oldProperties[propertyIri]?.toSet() ?? <RdfTerm>{};
      final newValues = newProperties[propertyIri]!.toSet();

      // If the sets of values are different, this property has changed
      if (!_setEquals(oldValues, newValues)) {
        changes.add(PropertyChange(
          resourceIri: resourceIri,
          propertyIri: propertyIri,
          changedAtMs: physicalTimestamp,
          changeLogicalClock: logicalClock,
        ));
      }
    }

    // Check for removed properties (exist in old but not in new)
    for (final propertyIri in oldProperties.keys) {
      if (!newProperties.containsKey(propertyIri)) {
        changes.add(PropertyChange(
          resourceIri: resourceIri,
          propertyIri: propertyIri,
          changedAtMs: physicalTimestamp,
          changeLogicalClock: logicalClock,
        ));
      }
    }
  }

  return changes;
}

/// Groups triples by their predicate, returning a map of property IRI -> list of values
Map<IriTerm, List<RdfTerm>> _groupTriplesByPredicate(Iterable<Triple> triples) {
  final result = <IriTerm, List<RdfTerm>>{};

  for (final triple in triples) {
    final predicate = triple.predicate as IriTerm;
    result.putIfAbsent(predicate, () => <RdfTerm>[]).add(triple.object);
  }

  return result;
}

/// Compares two sets for equality (since Set.equals is not available in all versions)
bool _setEquals<T>(Set<T> set1, Set<T> set2) {
  if (set1.length != set2.length) return false;
  return set1.every(set2.contains);
}

void _validateResourceGraph(
  IriTerm documentIri,
  IriTerm primaryResourceIri,
  IriTerm resourceType,
  RdfGraph resourceGraph,
) {
  // Validate that resourceGraph doesn't contain triples with documentIri as subject
  final hasDocumentTriples = resourceGraph.hasTriples(subject: documentIri);
  if (hasDocumentTriples) {
    throw ArgumentError('Resource graph contains triple(s) with document IRI '
        '$documentIri as subject. The document IRI is reserved for CRDT framework '
        'metadata and must not be used in resource data. Resource data should use '
        'fragment identifiers (e.g., ${documentIri.value}#it).');
  }

  // Validate that the primary resource actually exists in the resource graph with the correct type
  final hasPrimaryResourceTriples = resourceGraph.hasTriples(
      subject: primaryResourceIri, predicate: Rdf.type, object: resourceType);
  if (!hasPrimaryResourceTriples) {
    throw ArgumentError(
        'Primary resource IRI ($primaryResourceIri) not found in resource graph '
        'or does not have the expected type ($resourceType)');
  }

  final documentIriValue = documentIri.value;

  // Validate all resource IRIs are a proper fragment of the document IRI
  final iriSubjects = resourceGraph.subjects.whereType<IriTerm>().toSet();
  for (final iriSubject in iriSubjects) {
    final iriSubjectValue = iriSubject.value;
    if (!iriSubjectValue.startsWith('$documentIriValue#')) {
      throw ArgumentError(
          'Primary resource IRI ($iriSubjectValue) must be a fragment of the '
          'document IRI ($documentIriValue). Expected format: ${documentIriValue}#fragmentId');
    }
  }
}

/// Constructs a complete CRDT-managed document with framework metadata.
///
/// Takes the resource graph and wraps it with all required CRDT framework metadata:
/// - sync:ManagedDocument type declaration
/// - sync:managedResourceType pointing to the resource type
/// - sync:isGovernedBy linking to merge contract
/// - CRDT clock entries with logical and physical times
/// - Clock hash for efficient change detection
///
/// The resulting document contains both the original resource triples and
/// all the framework metadata needed for CRDT synchronization.
RdfGraph _constructCrdtDocument(
  IriTerm documentIri,
  IriTerm primaryResourceIri,
  IriTerm resourceType,
  RdfGraph resourceGraph,
  CurrentCrdtClock clock,
  SyncGraphConfig config,
) {
  final allTriples = <Triple>[];

  // 1. Add all original resource triples
  allTriples.addAll(resourceGraph.triples);

  // 2. Add sync:ManagedDocument type declaration
  allTriples.add(Triple(
    documentIri,
    Rdf.type,
    SyncManagedDocument.classIri,
  ));

  // 3. Add managed resource type
  allTriples.add(Triple(
    documentIri,
    SyncManagedDocument.managedResourceType,
    resourceType,
  ));

  // 4. Add primary topic reference (the main resource this document describes)
  allTriples.add(Triple(
    documentIri,
    SyncManagedDocument.foafPrimaryTopic,
    primaryResourceIri,
  ));

  // 5. Add merge contract reference from config
  // TODO: Add merge contract property to ResourceGraphConfig or get from another source
  // Skip merge contract for now until property is available

  // 6. Add HLC clock entry
  _addNodes(allTriples, documentIri, SyncManagedDocument.crdtHasClockEntry,
      clock.fullClock);

  // 7. Generate and add clock hash
  allTriples.add(Triple(
      documentIri, SyncManagedDocument.crdtClockHash, LiteralTerm(clock.hash)));

  // 8. Add creation timestamp (OR-Set semantics for document lifecycle)
  final creationTime =
      DateTime.fromMillisecondsSinceEpoch(clock.physicalTime).toIso8601String();
  allTriples.add(Triple(
    documentIri,
    SyncManagedDocument.crdtCreatedAt,
    LiteralTerm(creationTime),
  ));

  return RdfGraph.fromTriples(allTriples);
}

void _addNodes(List<Triple> triples, RdfSubject subject, RdfPredicate predicate,
    List<Node> nodes) {
  for (final node in nodes) {
    {
      final (objectTerm, graph) = node;
      triples.add(Triple(
        subject,
        predicate,
        objectTerm,
      ));
      triples.addAll(graph.triples);
    }
  }
}

Iterable<Triple> _getSubgraphTriples(RdfGraph subgraph, RdfSubject subject,
    [Set<RdfSubject>? visited]) sync* {
  visited ??= <RdfSubject>{};
  if (visited.contains(subject)) {
    return;
  }
  visited.add(subject);
  for (final triple in subgraph.findTriples(subject: subject)) {
    yield triple;
    final obj = triple.object;
    if (obj is RdfSubject) {
      yield* _getSubgraphTriples(subgraph, obj, visited);
    }
  }
}

({RdfGraph appGraph, List<Triple> documentTriples}) _splitDocument(
    RdfGraph document, IriTerm documentIri) {
  // We have to split the document into application data and framework metadata.
  // FIXME: use graph.subgraph() when available
  // FIXME: we have to exclude the primary topic!
  // hmm, it is difficult to define what is application data and what is
  // (potentially foreign) framework metadata.
  final allDocumentTriples =
      _getSubgraphTriples(document, documentIri).toList();

  return (
    appGraph: document.withoutTriples(allDocumentTriples),
    documentTriples: allDocumentTriples
  );
}

class DataMergeConfig {
  // TODO: is this flag useful? Should we implement standard CRDT merge semantics instead?
  bool get preserveUnmanagedDocumentTriples => true;
}

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
  final DataMergeConfig _dataMergeConfig = DataMergeConfig();

  late final HydrationStreamManager _streamManager;
  late final HydrationEmitter _emitter;
  late final GroupIndexGraphSubscriptionManager _groupIndexManager;

  // Factory functions for configurable time and clock generation
  final HlcService _hlcService;

  LocordaGraphSync._({
    required Storage storage,
    required Backend backend,
    required SyncGraphConfig config,
    PhysicalTimestampFactory? physicalTimestampFactory,
    HlcService? hlcService,
  })  : _storage = storage,
        _backend = backend,
        _config = config,
        _hlcService = hlcService ??
            HlcService(
              physicalTimestampFactory:
                  physicalTimestampFactory ?? defaultPhysicalTimestampFactory,
            ) {
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
    PhysicalTimestampFactory? physicalTimestampFactory,
    HlcService? hlcService,
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
        physicalTimestampFactory: physicalTimestampFactory,
        hlcService: hlcService);
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
    try {
      // Validate input parameters
      if (graph.isEmpty) {
        throw ArgumentError('Cannot save empty graph');
      }

      final resourceConfig = _config.getResourceConfig(type);

      // 1. Extract resource and document IRIs (with validation)
      late final IriTerm resourceIri;
      late final IriTerm documentIri;

      try {
        resourceIri = Rdf.getIdentifier(graph, type);
        documentIri = _extractDocumentIri(resourceIri);
      } on ArgumentError catch (e) {
        _log.severe('Invalid resource configuration for type $type: $e');
        rethrow;
      } on StateError catch (e) {
        _log.severe(
            'Multiple or no resources of type $type found in graph: $e');
        throw ArgumentError(
            'Graph must contain exactly one resource of type $type');
      }

      // Validate resource graph structure
      _validateResourceGraph(documentIri, resourceIri, type, graph);

      _log.fine('Saving resource $resourceIri to document $documentIri');

      // 2. Load existing document from storage (if any)
      StoredDocument? existingStoredDocument;
      try {
        existingStoredDocument = await _storage.getDocument(documentIri);
      } catch (e) {
        _log.warning('Failed to load existing document $documentIri: $e');
        // Continue with save - treat as new document
      }
      final oldDocument = existingStoredDocument?.document;
      final oldClock = oldDocument == null
          ? null
          : _extractCrdtClock(oldDocument, documentIri);
      final (appGraph: oldGraph, documentTriples: oldDocumentTriples) =
          oldDocument == null
              ? (appGraph: null, documentTriples: const <Triple>[])
              : _splitDocument(oldDocument, documentIri);

      // 3. Generate latest clock
      final clock = oldClock == null
          ? _hlcService.newClock()
          : _hlcService.incrementClock(oldClock);
      final physicalTimestamp = clock.physicalTime;

      // 4. Detect property changes between old and new graphs
      // FIXME: this is not only about property changes - we also need to
      // detect added/removed resources or property values so we can add tombstones.
      final propertyChanges = _detectPropertyChanges(
        oldGraph,
        graph,
        clock.physicalTime,
        clock.logicalTime,
      );
      if (propertyChanges.isEmpty) {
        _log.info(
            'No property changes detected for $resourceIri, skipping save');
        return;
      }

      // 5. Construct complete CRDT document with framework metadata
      final pureCrdtDocument = _constructCrdtDocument(
        documentIri,
        resourceIri,
        type,
        graph,
        clock,
        _config,
      );
      RdfGraph crdtDocument = _addUnmanagedDocumentTriples(
          oldDocumentTriples, pureCrdtDocument, documentIri);

      final updatedAtTimestamp = physicalTimestamp;
      // 6. Create document metadata for storage
      final documentMetadata = DocumentMetadata(
        ourPhysicalClock: physicalTimestamp,
        updatedAt: updatedAtTimestamp, // Storage will update this
      );

      // 7. Save to storage atomically (document + metadata + property changes)
      late final SaveDocumentResult saveResult;
      try {
        saveResult = await _storage.saveDocument(
          documentIri,
          type,
          crdtDocument,
          documentMetadata,
          propertyChanges,
        );
      } catch (e) {
        _log.severe('Failed to save document $documentIri to storage: $e');
        rethrow; // Don't emit hydration event if storage failed
      }

      // 8. Emit hydration event to update application state
      try {
        // FIXME: The emitter currently does the deriving of index items,
        // but this must be done here and each index has its own cursor
        _emitter.emit(
          HydrationResult<IdentifiedGraph>(
            items: [(resourceIri, graph)],
            deletedItems: [],
            originalCursor: saveResult.previousCursor,
            nextCursor: saveResult.currentCursor,
            hasMore: false,
          ),
          resourceConfig,
        );
      } catch (e) {
        _log.warning('Failed to emit hydration event for $resourceIri: $e');
        // Don't fail the entire save operation for hydration emission failures
      }

      _log.info(
          'Successfully saved document $documentIri with ${propertyChanges.length} property changes');
    } catch (e, stackTrace) {
      _log.severe('Save operation failed for type $type', e, stackTrace);
      rethrow;
    }
  }

  RdfGraph _addUnmanagedDocumentTriples(List<Triple> oldDocumentTriples,
      RdfGraph pureCrdtDocument, IriTerm documentIri) {
    if (_dataMergeConfig.preserveUnmanagedDocumentTriples &&
        oldDocumentTriples.isNotEmpty) {
      final managedPredicates = pureCrdtDocument
          .findTriples(subject: documentIri)
          .map((t) => t.predicate)
          .toSet();
      final oldDocumentGraph = RdfGraph.fromTriples(oldDocumentTriples);
      final oldManagedTriples = oldDocumentTriples
          .where((t) => managedPredicates.contains(t.predicate))
          .toSet();
      final oldManagedSubjectObjects = oldManagedTriples
          .map((t) => t.object)
          .whereType<RdfSubject>()
          .toList();
      final oldManagedTriplesSubgraph = oldManagedSubjectObjects
          .expand((subj) => _getSubgraphTriples(oldDocumentGraph, subj));
      final triplesToDelete = {
        ...oldManagedTriples,
        ...oldManagedTriplesSubgraph
      };
      final toKeep = oldDocumentGraph.withoutTriples(triplesToDelete);
      return pureCrdtDocument.merge(toKeep);
    }
    return pureCrdtDocument;
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

  CrdtClock _extractCrdtClock(RdfGraph oldGraph, IriTerm documentIri) {
    final clockEntries = oldGraph
        .findTriples(
            subject: documentIri,
            predicate: SyncManagedDocument.crdtHasClockEntry)
        .map((t) => t.object as RdfSubject);
    return clockEntries.map((clockEntrySubject) {
      final graph = oldGraph.matching(subject: clockEntrySubject);
      return (clockEntrySubject, graph);
    }).toList();
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
