/// Main facade for the CRDT sync system.
library;

import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:locorda_core/locorda_core.dart';
import 'package:locorda_core/src/crdt/crdt_types.dart';
import 'package:locorda_core/src/generated/_index.dart';
import 'package:locorda_core/src/hlc_service.dart';
import 'package:locorda_core/src/index/group_index_subscription_manager.dart';
import 'package:locorda_core/src/installation_service.dart'
    show InstallationService, InstallationIdFactory;
import 'package:locorda_core/src/mapping/framework_iri_generator.dart';
import 'package:locorda_core/src/mapping/identified_blank_node_builder.dart';
import 'package:locorda_core/src/mapping/iri_translator.dart';
import 'package:locorda_core/src/mapping/merge_contract.dart';
import 'package:locorda_core/src/mapping/merge_contract_loader.dart';
import 'package:locorda_core/src/mapping/metadata_generator.dart';
import 'package:locorda_core/src/mapping/recursive_rdf_loader.dart';
import 'package:locorda_core/src/rdf/rdf_extensions.dart';
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
          'Resource IRI ($iriSubjectValue) must be a fragment of the '
          'document IRI ($documentIriValue). Expected format: ${documentIriValue}#fragmentId');
    }
    if (iriSubjectValue.startsWith(
        '$documentIriValue#${FrameworkIriGenerator.fragmentPrefix}')) {
      throw ArgumentError(
          'Resource IRI ($iriSubjectValue) must not start with reserved prefix #lcrd- in fragment identifier. '
          'This prefix is reserved for CRDT framework metadata.');
    }
  }
}

final _defaultManagedDocumentLevelPredicates = <IriTerm>{
  Rdf.type,
  SyncManagedDocument.managedResourceType,
  SyncManagedDocument.foafPrimaryTopic,
  SyncManagedDocument.isGovernedBy,
  SyncManagedDocument.crdtHasClockEntry,
  SyncManagedDocument.crdtClockHash,
  SyncManagedDocument.crdtCreatedAt,
  SyncManagedDocument.crdtDeletedAt,
  SyncManagedDocument.hasBlankNodeMapping,
  SyncManagedDocument.hasStatement
};

/// Constructs a complete CRDT-managed document with framework metadata.
///
/// Takes the resource graph and wraps it with all required CRDT framework metadata:
/// - sync:ManagedDocument type declaration
/// - sync:managedResourceType pointing to the resource type
/// - sync:isGovernedBy linking to merge contract
/// - CRDT clock entries with logical and physical times
/// - Clock hash for efficient change detection
/// - CRDT metadata (tombstones, etc.) from change detection
///
/// The resulting document contains both the original resource triples and
/// all the framework metadata needed for CRDT synchronization.
RdfGraph _constructCrdtDocument(
  IriTerm documentIri,
  RdfGraph? oldFrameworkGraph,
  List<Node> crdtMetadata,
  List<RdfObject> governedByFiles,
  IriTerm primaryResourceIri,
  IriTerm resourceType,
  RdfGraph resourceGraph,
  RdfObject createdAt,
  CurrentCrdtClock clock,
  IdentifiedBlankNodes<IriTerm> blankNodeMappings,
) {
  final allTriples = <Triple>[];

  // 1. Add sync:ManagedDocument type declaration
  allTriples.add(Triple(
    documentIri,
    Rdf.type,
    SyncManagedDocument.classIri,
  ));

  // 2. Add managed resource type
  allTriples.add(Triple(
    documentIri,
    SyncManagedDocument.managedResourceType,
    resourceType,
  ));

  // 3. Add primary topic reference (the main resource this document describes)
  allTriples.add(Triple(
    documentIri,
    SyncManagedDocument.foafPrimaryTopic,
    primaryResourceIri,
  ));

  // 4. make sure the merge contracts are included
  allTriples.addRdfList(
      documentIri, SyncManagedDocument.isGovernedBy, governedByFiles);

  // 5. Add HLC clock entry
  allTriples.addNodes(
      documentIri, SyncManagedDocument.crdtHasClockEntry, clock.fullClock);

  // 6. Generate and add clock hash
  allTriples.add(Triple(
      documentIri, SyncManagedDocument.crdtClockHash, LiteralTerm(clock.hash)));

  // 7. Add creation timestamp (OR-Set semantics for document lifecycle)

  allTriples.add(Triple(
    documentIri,
    SyncManagedDocument.crdtCreatedAt,
    createdAt,
  ));

  // 8. Add blank node mappings for identified blank nodes
  // Create framework-reserved fragment identifiers and map them to blank nodes
  allTriples.addAll(toBlankNodeMappingTriples(blankNodeMappings, documentIri));

  // 9. add old/foreign framework triples
  final allManagedDocumentLevelPredicates = {
    ..._defaultManagedDocumentLevelPredicates,
    ...allTriples.where((t) => t.subject == documentIri).map((t) => t.predicate)
  };
  final additionalGraph =
      oldFrameworkGraph?.subgraph(documentIri, filter: (t, depth) {
    if (t.subject != documentIri) {
      // We only filter triples with the document as subject, everything else is included
      // once we reached it via the non-skipped triples
      return TraversalDecision.include;
    }
    // Really important: do not skip any existing statements from the old framework graph, we need to copy them over!
    return t.predicate != SyncManagedDocument.hasStatement &&
            allManagedDocumentLevelPredicates.contains(t.predicate)
        ? TraversalDecision.skip
        : TraversalDecision.include;
  });
  if (additionalGraph != null) {
    allTriples.addAll(additionalGraph.triples);
  }

// FIXME: test cases for non-identified blank nodes
// FIXME: are identified blank nodes correctly preserved if they were referenced from two places and removed from one?

  // 10. Add CRDT metadata (tombstones, counters, etc.)
  for (final node in crdtMetadata) {
    final (iri, graph) = node;
    allTriples.add(Triple(documentIri, SyncManagedDocument.hasStatement, iri));
    allTriples.addAll(graph.triples);
  }

  // 11. Add all original resource triples
  allTriples.addAll(resourceGraph.triples);

  return allTriples.toRdfGraph();
}

Iterable<Triple> toBlankNodeMappingTriples(
    IdentifiedBlankNodes<IriTerm> blankNodeMappings,
    IriTerm documentIri) sync* {
  for (final entry in blankNodeMappings.identifiedMap.entries) {
    final blankNode = entry.key;
    final canonicalIris = entry.value;

    for (final canonicalIri in canonicalIris) {
      // Add sync:hasBlankNodeMapping link from document to mapping
      yield Triple(
        documentIri,
        SyncManagedDocument.hasBlankNodeMapping,
        canonicalIri,
      );

      // Add the mapping itself: canonicalIri sync:blankNode _:blankNode
      yield Triple(
        canonicalIri,
        Sync.blankNode,
        blankNode,
      );
      // Optimization: do not add the type for the mapping - it is not strictly necessary
      /*
      // Add type for the mapping
      yield Triple(
        canonicalIri,
        Rdf.type,
        SyncBlankNodeMapping.classIri,
      );
      */
    }
  }
}

List<IriTerm> _computeIsGovernedBy(RdfGraph? oldFrameworkGraph,
    IriTerm documentIri, SyncGraphConfig config, IriTerm resourceType) {
  final oldIsGovernedByFiles = oldFrameworkGraph?.getListObjects<IriTerm>(
          documentIri, SyncManagedDocument.isGovernedBy) ??
      const <IriTerm>[];
  final ourGovernedByFile = IriTerm.validated(
      config.getResourceConfig(resourceType).crdtMapping.toString());
  return oldIsGovernedByFiles.contains(ourGovernedByFile)
      ? oldIsGovernedByFiles
      : ([...oldIsGovernedByFiles, ourGovernedByFile]);
}

({RdfGraph appGraph, RdfGraph frameworkGraph}) _splitDocument(
    RdfGraph document, IriTerm documentIri, MergeContract mergeContract) {
  // We have to split the document into application data and framework metadata.

  final types = <RdfSubject, IriTerm?>{};
  final frameworkGraph =
      document.subgraph(documentIri, filter: (triple, depth) {
    final type = types.putIfAbsent(triple.subject,
        () => document.findSingleObject<IriTerm>(triple.subject, Rdf.type));

    final isStopTraversal =
        mergeContract.isStopTraversalPredicate(type, triple.predicate);
    return isStopTraversal
        ? TraversalDecision.includeButDontDescend
        : TraversalDecision.include;
  });

  return (
    appGraph: document.without(frameworkGraph),
    frameworkGraph: frameworkGraph
  );
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
  final MergeContractLoader _mergeContractLoader;
  final CrdtTypeRegistry _crdtTypeRegistry;
  final FrameworkIriGenerator _iriGenerator;
  final IriTranslator _iriTranslator;
  final HydrationStreamManager _streamManager;
  final GroupIndexGraphSubscriptionManager _groupIndexManager;
  late final IdentifiedBlankNodeBuilder _identifiedBlankNodeBuilder =
      IdentifiedBlankNodeBuilder(iriGenerator: _iriGenerator);
  late final MetadataGenerator _metadataGenerator =
      MetadataGenerator(frameworkIriGenerator: _iriGenerator);
  late final HydrationEmitter _emitter = HydrationEmitter(
    streamManager: _streamManager,
  );

  // Factory functions for configurable time and clock generation
  final HlcService _hlcService;

  LocordaGraphSync._({
    required Storage storage,
    required Backend backend,
    required SyncGraphConfig config,
    required MergeContractLoader mergeContractLoader,
    required HlcService hlcService,
    required ResourceLocator resourceLocator,
    required PhysicalTimestampFactory physicalTimestampFactory,
    required IriTermFactory iriTermFactory,
  })  : _storage = storage,
        _backend = backend,
        _config = config,
        _mergeContractLoader = mergeContractLoader,
        _crdtTypeRegistry = CrdtTypeRegistry.forStandardTypes(
            physicalTimestampFactory: physicalTimestampFactory),
        _hlcService = hlcService,
        _streamManager = HydrationStreamManager(),
        _groupIndexManager = GroupIndexGraphSubscriptionManager(
          config: config,
        ),
        _iriGenerator = FrameworkIriGenerator(iriTermFactory: iriTermFactory),
        _iriTranslator = IriTranslator(
          resourceLocator: resourceLocator,
          resourceConfigs: config.resources,
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
      )
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
    final installationService = await InstallationService.initialize(
      storage: storage,
      resourceLocator: localResourceLocator,
      installationIdFactory: installationIdFactory,
      iriTermFactory: iriFactory,
    );

    // Create HlcService with installation IRI and localId
    final hlcService = HlcService(
      installationLocalId: installationService.installationLocalId,
      physicalTimestampFactory: physicalTimestampFactory,
    );

    // TODO: the HttpRdfGraphFetcher should be db-cached (ideally with initialization from deployment and etag)
    final mergeContractLoader = StandardMergeContractLoader(RecursiveRdfLoader(
        fetcher: StandardRdfGraphFetcher(fetcher: fetcher, rdfCore: rdfCore),
        iriFactory: iriFactory));

    final sync = LocordaGraphSync._(
        storage: storage,
        backend: backend,
        config: effectiveConfig,
        mergeContractLoader: CachingMergeContractLoader(mergeContractLoader),
        physicalTimestampFactory: physicalTimestampFactory,
        hlcService: hlcService,
        iriTermFactory: iriFactory,
        resourceLocator: localResourceLocator);

    if (!installationService.installationDocumentSaved) {
      final iri = installationService.installationIri;
      final now = physicalTimestampFactory();
      final installationDocument = RdfGraph.fromTriples([
        Triple(iri, Rdf.type, CrdtClientInstallation.classIri),
        // Created timestamp
        Triple(
          iri,
          CrdtClientInstallation.createdAt,
          LiteralTermExtensions.dateTime(now),
        ),
        // Last active timestamp
        Triple(
          iri,
          CrdtClientInstallation.lastActiveAt,
          LiteralTermExtensions.dateTime(now),
        ),
        // Default max inactivity period (6 months)
        Triple(
          iri,
          CrdtClientInstallation.maxInactivityPeriod,
          LiteralTerm(
            'P6M',
            datatype: iriFactory('http://www.w3.org/2001/XMLSchema#duration'),
          ),
        ),
      ]);
      await sync.save(CrdtClientInstallation.classIri, installationDocument);
      await installationService.markInstallationDocumentSaved();
    }
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
  /// listen to hydrateStreaming() to receive updates.
  ///
  /// Process:
  /// 1. CRDT processing (merge with existing, clock increment)
  /// 2. Store locally in sync system
  /// 3. Hydration stream automatically emits update
  /// 4. Schedule async Pod sync
  Future<void> save(IriTerm type, RdfGraph appData) async {
    RdfGraph? oldDocument;
    RdfGraph? crdtDocument;
    // 0. Translate external IRIs to internal format if documentIriTemplate is configured
    final internalAppData = _iriTranslator.translateGraphToInternal(appData);

    try {
      // Validate input parameters
      if (internalAppData.isEmpty) {
        throw ArgumentError('Cannot save empty graph');
      }

      final resourceConfig = _config.getResourceConfig(type);

      // 1. Extract resource and document IRIs (with validation)
      late final IriTerm resourceIri;
      late final IriTerm documentIri;

      try {
        resourceIri = internalAppData.getIdentifier(type);
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
      _validateResourceGraph(documentIri, resourceIri, type, internalAppData);

      _log.fine('Saving resource $resourceIri to document $documentIri');

      // 2. Load existing document from storage (if any)
      StoredDocument? existingStoredDocument;
      try {
        existingStoredDocument = await _storage.getDocument(documentIri);
      } catch (e) {
        _log.warning('Failed to load existing document $documentIri: $e');
        // Continue with save - treat as new document
      }
      oldDocument = existingStoredDocument?.document;

      final governedByFiles =
          _computeIsGovernedBy(oldDocument, documentIri, _config, type);

      // load the governing documents / merge contracts for correct document splitting
      final mergeContract = await _mergeContractLoader.load(governedByFiles);

      final (appGraph: oldAppData, frameworkGraph: oldFrameworkGraph) =
          oldDocument == null
              ? (appGraph: null, frameworkGraph: null)
              : _splitDocument(oldDocument, documentIri, mergeContract);

      // 3. Generate latest clock
      final oldClock = oldDocument == null
          ? null
          : _extractCrdtClock(oldDocument, documentIri);
      final clock = oldClock == null
          ? _hlcService.newClock(documentIri)
          : _hlcService.incrementClock(documentIri, oldClock);
      final physicalTimestamp = clock.physicalTime;

      // 4. Detect property changes between old and new graphs and generate CRDT metadata
      final appBlankNodes =
          _identifiedBlankNodeBuilder.computeCanonicalBlankNodes(
              documentIri, internalAppData, mergeContract);
      final oldAppBlankNodes = oldAppData == null
          ? IdentifiedBlankNodes.empty<IriTerm>()
          : _identifiedBlankNodeBuilder.computeCanonicalBlankNodes(
              documentIri, oldAppData, mergeContract);
      final crdtMetadata = _generateCrdtMetadataForChanges(
        documentIri,
        internalAppData,
        appBlankNodes,
        oldAppData,
        oldAppBlankNodes,
        mergeContract,
        clock,
      );
      final propertyChanges = crdtMetadata.propertyChanges;
      if (propertyChanges.isEmpty) {
        _log.info(
            'No property changes detected for $resourceIri, skipping save');
        return;
      }
      final createdAt = oldFrameworkGraph?.findSingleObject<LiteralTerm>(
              documentIri, SyncManagedDocument.crdtCreatedAt) ??
          LiteralTermExtensions.dateTime(DateTime.fromMillisecondsSinceEpoch(
              physicalTimestamp,
              isUtc: true));
      // 5. Construct complete CRDT document with framework metadata
      crdtDocument = _constructCrdtDocument(
        documentIri,
        oldFrameworkGraph,
        crdtMetadata.metadataGraph,
        governedByFiles,
        resourceIri,
        type,
        internalAppData,
        createdAt,
        clock,
        appBlankNodes,
      );

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

        // FIXME: is this the correct place for translating to external IRIs,
        // should it be done in the emitter?
        // Translate back to external IRIs for application consumption
        final externalAppData =
            _iriTranslator.translateGraphToExternal(internalAppData);
        final externalResourceIri =
            _iriTranslator.internalToExternal(resourceIri);

        _emitter.emit(
          HydrationResult<IdentifiedGraph>(
            items: [(externalResourceIri, externalAppData)],
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
    } on UnidentifiedBlankNodeException catch (e, stackTrace) {
      _log.severe('Save operation failed for type $type', e, stackTrace);
      final blankNode = e.blankNode;
      throwIfUsedIn(stackTrace, "Old Doument", oldDocument, blankNode);
      throwIfUsedIn(stackTrace, "New App Data", internalAppData, blankNode);
      throwIfUsedIn(stackTrace, "New Doument", crdtDocument, blankNode);
      rethrow;
    } catch (e, stackTrace) {
      _log.severe('Save operation failed for type $type', e, stackTrace);
      rethrow;
    }
  }

  void throwIfUsedIn(StackTrace stackTrace, String context,
      RdfGraph? oldDocument, BlankNodeTerm blankNode) {
    if (oldDocument != null) {
      final subjectTriples = oldDocument.findTriples(subject: blankNode);
      final objectTriples = oldDocument.findTriples(object: blankNode);
      if (subjectTriples.isNotEmpty || objectTriples.isNotEmpty) {
        final ex = UnidentifiedBlankNodeWithContextException(blankNode, context,
            subjectTriples.toList(), objectTriples.toList());
        Error.throwWithStackTrace(ex, stackTrace);
      }
    }
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
  Future<void> deleteDocument(IriTerm typeIri, IriTerm externalIri) async {
    // Translate external IRI to internal format
    final internalIri = _iriTranslator.externalToInternal(externalIri);

    final resourceConfig = _config.getResourceConfig(typeIri);
    // Basic implementation to maintain hydration stream contract
    // TODO: Add proper CRDT deletion processing and storage persistence

    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();

    // Emit data change with external IRI for application consumption
    _emitter.emit(
        HydrationResult<IdentifiedGraph>(
          items: [],
          deletedItems: [
            (
              externalIri,
              RdfGraph.fromTriples([Triple(externalIri, Rdf.type, typeIri)])
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

  Iterable<IdentifiedRdfSubject> _getIdentifiedSubjects(
          RdfGraph graph, IdentifiedBlankNodes<IriTerm> blankNodes) =>
      graph.subjects.map((subject) {
        if (subject is IriTerm) {
          return IdentifiedIriSubject(subject);
        } else if (subject is BlankNodeTerm) {
          if (blankNodes.hasIdentifiedNodes(subject)) {
            return IdentifiedBlankNodeSubject(
                subject, blankNodes.getIdentifiedNodes(subject));
          }
        }
        return null; // Unidentified blank node
      }).whereType<IdentifiedRdfSubject>();

  _CrdtMetadataResult _generateCrdtMetadataForChanges(
      IriTerm documentIri,
      RdfGraph appData,
      IdentifiedBlankNodes<IriTerm> appBlankNodes,
      RdfGraph? oldAppGraph,
      IdentifiedBlankNodes<IriTerm> oldAppBlankNodes,
      MergeContract mergeContract,
      CurrentCrdtClock clock) {
    final metadataGraphs = <Node>[];
    final propertyChanges = <PropertyChange>[];

    // Get all identifiable subjects from both graphs
    final identifiedSubjects =
        _getIdentifiedSubjects(appData, appBlankNodes).toSet();
    final oldIdentifiedSubjects = oldAppGraph == null
        ? const <IdentifiedRdfSubject>{}
        : _getIdentifiedSubjects(oldAppGraph, oldAppBlankNodes).toSet();

    // Partition subjects into added, deleted, and common
    final addedSubjects = identifiedSubjects.difference(oldIdentifiedSubjects);
    final deletedSubjects =
        oldIdentifiedSubjects.difference(identifiedSubjects);
    final commonSubjects = {
      for (final subject in identifiedSubjects)
        if (oldIdentifiedSubjects.contains(subject))
          subject: oldIdentifiedSubjects.lookup(subject)!
    };
    final context = CrdtMergeContext(
        iriGenerator: _iriGenerator, metadataGenerator: _metadataGenerator);

    // Process deleted subjects - add resource tombstones
    for (final deletedSubject in deletedSubjects) {
      _log.fine('Deleted subject detected: ${deletedSubject.subject} ');
      metadataGraphs.addAll(_metadataGenerator.createResourceMetadata(
          documentIri,
          IdTerm.create(deletedSubject.subject, oldAppBlankNodes),
          (metadataSubject) => [
                Triple(
                    metadataSubject,
                    SyncManagedDocument.crdtDeletedAt,
                    LiteralTermExtensions.dateTimeFromMillisecondsSinceEpoch(
                        clock.physicalTime))
              ]));
    }

    // Process added subjects - generate initial value metadata
    for (final addedSubject in addedSubjects) {
      final subjectTerm = addedSubject.subject;
      var subjectTriples = appData.matching(subject: subjectTerm);
      final predicates = subjectTriples.predicates;
      final resourceType =
          appData.findSingleObject<IriTerm>(subjectTerm, Rdf.type);

      for (final predicate in predicates) {
        final values =
            subjectTriples.getMultiValueObjects(subjectTerm, predicate);

        // Get CRDT algorithm for this property
        final crdtType =
            _getCrdtAlgorithm(mergeContract, resourceType, predicate);

        // Generate initial value metadata
        final metadataGraph = crdtType.initialValue(
          documentIri: documentIri,
          appData: appData,
          blankNodes: appBlankNodes,
          subject: subjectTerm,
          predicate: predicate,
          values: values.cast<RdfObject>(),
          mergeContext: context,
        );

        metadataGraphs.addAll(metadataGraph);

        // Record property change using canonical IRI (for identified blank nodes) or IRI
        for (final propertyChangeIri in addedSubject.propertyChangeIris) {
          propertyChanges.add(PropertyChange(
            resourceIri: propertyChangeIri,
            propertyIri: predicate,
            changedAtMs: clock.physicalTime,
            changeLogicalClock: clock.logicalTime,
          ));
        }
      }
    }

    // Process common subjects - detect changes and generate change metadata
    for (final entry in commonSubjects.entries) {
      final subjectTerm = entry.key.subject;
      final oldSubjectTerm = entry.value.subject;

      final newTriples = appData.matching(subject: subjectTerm);
      final oldTriples = oldAppGraph!.matching(subject: oldSubjectTerm);

      final newPropertiesByPredicate = newTriples.predicates;
      final oldPropertiesByPredicate = oldTriples.predicates;

      final resourceType =
          appData.findSingleObject<IriTerm>(subjectTerm, Rdf.type);

      // Get all predicates from both old and new
      final allPredicates = {
        ...newPropertiesByPredicate,
        ...oldPropertiesByPredicate
      };

      for (final predicate in allPredicates) {
        final newValues =
            newTriples.getMultiValueObjects(subjectTerm, predicate);
        final oldValues =
            oldTriples.getMultiValueObjects(oldSubjectTerm, predicate);

        // Check if values changed (considering blank node deep equality)
        if (_valuesEqual(oldValues, newValues, oldAppGraph, appData,
            oldAppBlankNodes, appBlankNodes)) {
          continue; // No change
        }

        // Get CRDT algorithm for this property
        final crdtType =
            _getCrdtAlgorithm(mergeContract, resourceType, predicate);

        // Generate change metadata
        final metadataGraph = crdtType.localValueChange(
          documentIri: documentIri,
          oldAppData: oldAppGraph,
          oldBlankNodes: oldAppBlankNodes,
          oldSubject: oldSubjectTerm,
          newAppData: appData,
          newBlankNodes: appBlankNodes,
          newSubject: subjectTerm,
          predicate: predicate,
          oldValues: oldValues,
          newValues: newValues,
          mergeContext: context,
        );

        metadataGraphs.addAll(metadataGraph);

        // Record property change using canonical IRI (for identified blank nodes) or IRI
        for (final propertyChangeIri in entry.key.propertyChangeIris) {
          propertyChanges.add(PropertyChange(
            resourceIri: propertyChangeIri,
            propertyIri: predicate,
            changedAtMs: clock.physicalTime,
            changeLogicalClock: clock.logicalTime,
          ));
        }
        _log.fine('Property change detected on $subjectTerm for $predicate');
      }
    }

    return _CrdtMetadataResult(
      metadataGraph: metadataGraphs,
      propertyChanges: propertyChanges,
    );
  }

  CrdtType _getCrdtAlgorithm(MergeContract mergeContract, IriTerm? resourceType,
      RdfPredicate predicate) {
    // Get CRDT algorithm for this property
    final rule =
        mergeContract.getEffectivePredicateRule(resourceType, predicate);
    final algorithmIri = rule?.mergeWith;
    if (algorithmIri == null) {
      if (rule == null) {
        _log.warning(
            'No predicate rule found for $predicate on $resourceType, using ${CrdtTypeRegistry.fallback.iri.value}.');
      } else {
        _log.fine(
            'No merge algorithm found in rule for $predicate on $resourceType, using ${CrdtTypeRegistry.fallback.iri.value}.');
      }
    }
    return _crdtTypeRegistry.getType(algorithmIri);
  }

  /// Check if two value lists are equal, considering deep equality for blank nodes
  bool _valuesEqual(
      List<RdfTerm> oldValues,
      List<RdfTerm> newValues,
      RdfGraph oldGraph,
      RdfGraph newGraph,
      IdentifiedBlankNodes oldBlankNodes,
      IdentifiedBlankNodes newBlankNodes) {
    if (oldValues.length != newValues.length) {
      return false;
    }

    // For each old value, try to find a matching new value
    final matchedNewValues = <RdfTerm>{};

    for (final oldValue in oldValues) {
      bool found = false;

      for (final newValue in newValues) {
        if (matchedNewValues.contains(newValue)) {
          continue; // Already matched to another old value
        }

        if (_valueEquals(oldValue, newValue, oldGraph, newGraph, oldBlankNodes,
            newBlankNodes)) {
          matchedNewValues.add(newValue);
          found = true;
          break;
        }
      }

      if (!found) {
        return false; // Old value has no match in new values
      }
    }

    return true;
  }

  /// Check if two RDF values are equal, considering deep equality for blank nodes
  bool _valueEquals(
      RdfTerm oldValue,
      RdfTerm newValue,
      RdfGraph oldGraph,
      RdfGraph newGraph,
      IdentifiedBlankNodes oldBlankNodes,
      IdentifiedBlankNodes newBlankNodes) {
    // Simple case: same term
    if (oldValue == newValue) {
      return true;
    }

    // For blank nodes, check if they're identified and equal
    if (oldValue is BlankNodeTerm && newValue is BlankNodeTerm) {
      final oldIdentifiers = oldBlankNodes.hasIdentifiedNodes(oldValue)
          ? oldBlankNodes.getIdentifiedNodes(oldValue)
          : null;
      final newIdentifiers = newBlankNodes.hasIdentifiedNodes(newValue)
          ? newBlankNodes.getIdentifiedNodes(newValue)
          : null;

      // If both are identified, check if they share any identifier
      if (oldIdentifiers != null && newIdentifiers != null) {
        if (oldIdentifiers.any((oldId) => newIdentifiers.contains(oldId))) {
          return true; // Identified as the same blank node
        }
      }

      // For non-identified blank nodes, do deep structural comparison
      return _deepBlankNodeEquals(
          oldValue, newValue, oldGraph, newGraph, oldBlankNodes, newBlankNodes);
    }

    return false;
  }

  /// Perform deep structural comparison of blank nodes
  bool _deepBlankNodeEquals(
      BlankNodeTerm oldBlankNode,
      BlankNodeTerm newBlankNode,
      RdfGraph oldGraph,
      RdfGraph newGraph,
      IdentifiedBlankNodes oldBlankNodes,
      IdentifiedBlankNodes newBlankNodes,
      [Set<BlankNodeTerm>? visited]) {
    visited ??= {};

    // Prevent infinite recursion
    if (visited.contains(oldBlankNode)) {
      return true; // Assume equal if we're in a cycle
    }
    visited.add(oldBlankNode);

    final oldTriples = oldGraph.matching(subject: oldBlankNode);
    final newTriples = newGraph.matching(subject: newBlankNode);

    final oldProps = oldTriples.predicates;
    final newProps = newTriples.predicates;

    // Must have same predicates
    if (!_isEqualSet(oldProps, newProps)) {
      return false;
    }

    // Check each predicate's values
    for (final predicate in oldProps) {
      final oldValues = oldGraph.getMultiValueObjects(oldBlankNode, predicate);
      final newValues = newGraph.getMultiValueObjects(newBlankNode, predicate);

      if (!_valuesEqual(oldValues, newValues, oldGraph, newGraph, oldBlankNodes,
          newBlankNodes)) {
        return false;
      }
    }

    return true;
  }
}

bool _isEqualSet<T>(Set<T> set, Set<T> set2) {
  if (set.length != set2.length) {
    return false;
  }
  for (final item in set) {
    if (!set2.contains(item)) {
      return false;
    }
  }
  return true;
}

/// Result of CRDT metadata generation containing metadata triples and property changes
class _CrdtMetadataResult {
  final List<Node> metadataGraph;
  final List<PropertyChange> propertyChanges;

  _CrdtMetadataResult({
    required this.metadataGraph,
    required this.propertyChanges,
  });
}

class _HydrationStreamSubscription implements HydrationSubscription {
  final StreamSubscription _subscription;

  _HydrationStreamSubscription(this._subscription);

  @override
  Future<void> cancel() => _subscription.cancel();

  @override
  bool get isActive => _subscription.isPaused == false;
}
