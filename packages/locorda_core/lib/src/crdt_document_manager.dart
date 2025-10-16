/// Main facade for the CRDT sync system.
library;

import 'dart:async';

import 'package:locorda_core/locorda_core.dart';
import 'package:locorda_core/src/crdt/crdt_types.dart';
import 'package:locorda_core/src/generated/_index.dart';
import 'package:locorda_core/src/hlc_service.dart';
import 'package:locorda_core/src/index/index_rdf_generator.dart';
import 'package:locorda_core/src/index/shard_determiner.dart';
import 'package:locorda_core/src/index/shard_manager.dart';
import 'package:locorda_core/src/mapping/framework_iri_generator.dart';
import 'package:locorda_core/src/mapping/identified_blank_node_builder.dart';
import 'package:locorda_core/src/mapping/merge_contract.dart';
import 'package:locorda_core/src/mapping/merge_contract_loader.dart';
import 'package:locorda_core/src/mapping/metadata_generator.dart';
import 'package:locorda_core/src/rdf/rdf_extensions.dart';
import 'package:logging/logging.dart';
import 'package:rdf_core/rdf_core.dart';

final _log = Logger('LocordaGraphSync');

typedef IdentifiedGraph = (IriTerm id, RdfGraph graph);
typedef DocumentSaveResult = ({
  RdfSubject resourceIri,
  IriTerm documentIri,
  String? previousCursor, // The highest cursor for this type before this save (null if first)
  String currentCursor, // The cursor for this save operation
  RdfGraph crdtDocument,
  RdfGraph appData,
  int physicalTime,
  List<
      MissingGroupIndex> missingGroupIndices // GroupIndices that need to be created
});

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
List<Triple> _constructCrdtDocument(
  IriTerm documentIri,
  RdfGraph? oldFrameworkGraph,
  List<Node> crdtMetadata,
  List<RdfObject> governedByFiles,
  IriTerm primaryResourceIri,
  IriTerm resourceType,
  RdfObject createdAt,
  CurrentCrdtClock clock,
  IdentifiedBlankNodes<IriTerm> blankNodeMappings,
  Iterable<IriTerm> shards,
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

  // 9. add shard references
  allTriples.addMultiple(
      documentIri, SyncManagedDocument.idxBelongsToIndexShard, shards);

  // 10. add old/foreign framework triples
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

  // 11. Add CRDT metadata (tombstones, counters, etc.)
  allTriples.addNodes(
      documentIri, SyncManagedDocument.hasStatement, crdtMetadata);

  return allTriples;
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
class CrdtDocumentManager {
  final Storage _storage;
  final SyncGraphConfig _config;
  final MergeContractLoader _mergeContractLoader;
  final CrdtTypeRegistry _crdtTypeRegistry;
  final FrameworkIriGenerator _iriGenerator;
  final ShardDeterminer _shardDeterminer;

  late final IdentifiedBlankNodeBuilder _identifiedBlankNodeBuilder =
      IdentifiedBlankNodeBuilder(iriGenerator: _iriGenerator);
  late final MetadataGenerator _metadataGenerator =
      MetadataGenerator(frameworkIriGenerator: _iriGenerator);

  // Factory functions for configurable time and clock generation
  final HlcService _hlcService;

  CrdtDocumentManager({
    required Storage storage,
    required SyncGraphConfig config,
    required MergeContractLoader mergeContractLoader,
    required HlcService hlcService,
    required IriTermFactory iriTermFactory,
    required CrdtTypeRegistry crdtTypeRegistry,
    required ShardDeterminer shardDeterminer,
  })  : _storage = storage,
        _config = config,
        _mergeContractLoader = mergeContractLoader,
        _crdtTypeRegistry = crdtTypeRegistry,
        _hlcService = hlcService,
        _iriGenerator = FrameworkIriGenerator(iriTermFactory: iriTermFactory),
        _shardDeterminer = shardDeterminer;

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
  Future<DocumentSaveResult?> save(IriTerm type, RdfGraph appData) async {
    // Validate input parameters
    if (appData.isEmpty) {
      throw ArgumentError('Cannot save empty graph');
    }
    // 1. Extract resource and document IRIs (with validation)
    late final IriTerm resourceIri;
    late final IriTerm documentIri;

    try {
      resourceIri = appData.getIdentifier(type);
      documentIri = resourceIri.getDocumentIri();
    } on ArgumentError catch (e) {
      _log.severe('Invalid resource configuration for type $type: $e');
      rethrow;
    } on StateError catch (e) {
      _log.severe('Multiple or no resources of type $type found in graph: $e');
      throw ArgumentError(
          'Graph must contain exactly one resource of type $type');
    }

    // 2. Load existing document from storage (if any)
    final (
      oldAppData: oldAppData,
      oldFrameworkGraph: oldFrameworkGraph,
      mergeContract: mergeContract,
      governedByFiles: governedByFiles
    ) = await _prepare(type, documentIri);
    return _save(type, resourceIri, documentIri, appData, oldAppData,
        oldFrameworkGraph, mergeContract, governedByFiles);
  }

  Future<DocumentSaveResult?> patch(IriTerm type, IriTerm primaryResourceIri,
      IriTerm predicate, Node node) async {
    final r = await modify(type, primaryResourceIri, (oldAppData) {
      // TODO: the patch implementation is very naive and inefficient - we might want to optimize this in the future
      final hasEntry = oldAppData.hasTriples(
          subject: primaryResourceIri, predicate: predicate, object: node.$1);
      final triplesToRemove = oldAppData.subgraph(node.$1).triples.toSet();

      var entry = Triple(primaryResourceIri, predicate, node.$1);
      final removeEntry = node.$2.isEmpty;
      final addEntry = !hasEntry && !removeEntry;
      if (removeEntry) {
        triplesToRemove.add(entry);
      }
      final appData = RdfGraph.fromTriples([
        ...oldAppData.triples.where((t) => !triplesToRemove.contains(t)),
        if (addEntry) entry,
        ...node.$2.triples
      ]);
      return appData;
    });
    if (r == null) {
      return null;
    }
    return (
      appData: node.$2,
      crdtDocument: r.crdtDocument,
      currentCursor: r.currentCursor,
      documentIri: r.documentIri,
      previousCursor: r.previousCursor,
      resourceIri: node.$1,
      missingGroupIndices: r.missingGroupIndices,
      physicalTime: r.physicalTime,
    );
  }

  Future<DocumentSaveResult?> modify(IriTerm type, IriTerm primaryResourceIri,
      RdfGraph Function(RdfGraph oldAppData) modifier,
      {int? physicalTime, bool acceptMissing = false}) async {
    IriTerm documentIri = primaryResourceIri.getDocumentIri();
    // 1. Extract resource and document IRIs (with validation)

    final (
      oldAppData: oldAppData,
      oldFrameworkGraph: oldFrameworkGraph,
      mergeContract: mergeContract,
      governedByFiles: governedByFiles
    ) = await _prepare(type, documentIri);
    if (oldAppData == null && !acceptMissing) {
      throw ArgumentError(
          'Cannot patch non-existing document $documentIri - use save() instead');
    }

    // let the caller derive the app data from the old state
    final appData = modifier(oldAppData == null ? RdfGraph() : oldAppData);

    return await _save(
      type,
      primaryResourceIri,
      documentIri,
      appData,
      oldAppData,
      oldFrameworkGraph,
      mergeContract,
      governedByFiles,
      physicalTime: physicalTime,
    );
  }

  Future<
      ({
        RdfGraph? oldAppData,
        RdfGraph? oldFrameworkGraph,
        MergeContract mergeContract,
        List<IriTerm> governedByFiles
      })> _prepare(IriTerm type, IriTerm documentIri) async {
    StoredDocument? existingStoredDocument;
    try {
      existingStoredDocument = await _storage.getDocument(documentIri);
    } catch (e) {
      _log.warning('Failed to load existing document $documentIri: $e');
      // Continue with save - treat as new document
    }
    final oldDocument = existingStoredDocument?.document;

    final governedByFiles =
        _computeIsGovernedBy(oldDocument, documentIri, _config, type);

    // load the governing documents / merge contracts for correct document splitting
    final mergeContract = await _mergeContractLoader.load(governedByFiles);

    final (appGraph: oldAppData, frameworkGraph: oldFrameworkGraph) =
        oldDocument == null
            ? (appGraph: null, frameworkGraph: null)
            : _splitDocument(oldDocument, documentIri, mergeContract);
    return (
      oldAppData: oldAppData,
      oldFrameworkGraph: oldFrameworkGraph,
      mergeContract: mergeContract,
      governedByFiles: governedByFiles
    );
  }

  Future<DocumentSaveResult?> _save(
    IriTerm type,
    IriTerm resourceIri,
    IriTerm documentIri,
    RdfGraph appData,
    RdfGraph? oldAppData,
    RdfGraph? oldFrameworkGraph,
    MergeContract mergeContract,
    List<IriTerm> governedByFiles, {
    int? physicalTime,
  }) async {
    RdfGraph? oldDocument;
    RdfGraph? crdtDocument;
    RdfGraph? frameworkGraph;
    try {
      // Validate input parameters
      if (appData.isEmpty) {
        throw ArgumentError('Cannot save empty graph');
      }

      // Validate resource graph structure
      _validateResourceGraph(documentIri, resourceIri, type, appData);

      _log.fine('Saving resource $resourceIri to document $documentIri');

      // 3. Generate latest clock
      final oldClock = oldFrameworkGraph == null
          ? null
          : _extractCrdtClock(oldFrameworkGraph, documentIri);
      final clock = oldClock == null
          ? _hlcService.newClock(documentIri, physicalTime: physicalTime)
          : _hlcService.incrementClock(documentIri, oldClock,
              physicalTime: physicalTime);
      final physicalTimestamp = clock.physicalTime;

      // 4. Detect property changes between old and new app graphs and generate CRDT metadata
      final appBlankNodes = _identifiedBlankNodeBuilder
          .computeCanonicalBlankNodes(documentIri, appData, mergeContract);
      final oldAppBlankNodes = oldAppData == null
          ? IdentifiedBlankNodes.empty<IriTerm>()
          : _identifiedBlankNodeBuilder.computeCanonicalBlankNodes(
              documentIri, oldAppData, mergeContract);
      final crdtMetadata = _generateCrdtMetadataForChanges(
        documentIri,
        appData,
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
        return null;
      }
      final createdAt = oldFrameworkGraph?.findSingleObject<LiteralTerm>(
              documentIri, SyncManagedDocument.crdtCreatedAt) ??
          LiteralTermExtensions.dateTime(DateTime.fromMillisecondsSinceEpoch(
              physicalTimestamp,
              isUtc: true));

      // Calculate new shards based on current appData
      final (allShards, removed, missingGroupIndices) =
          await _shardDeterminer.calculateShards(
        type,
        resourceIri,
        documentIri,
        appData,
        oldAppData,
        oldFrameworkGraph,
      );

      // 5. Construct complete CRDT document with framework metadata
      final documentTriples = _constructCrdtDocument(
        documentIri,
        oldFrameworkGraph,
        crdtMetadata.metadataGraph,
        governedByFiles,
        resourceIri,
        type,
        createdAt,
        clock,
        appBlankNodes,
        allShards,
      );
      frameworkGraph = RdfGraph.fromTriples(documentTriples);
      final frameworkMetadata = _generateCrdtMetadataForChanges(
        documentIri,
        frameworkGraph,
        _identifiedBlankNodeBuilder.computeCanonicalBlankNodes(
            documentIri, frameworkGraph, mergeContract),
        oldFrameworkGraph,
        oldFrameworkGraph == null
            ? IdentifiedBlankNodes.empty<IriTerm>()
            : _identifiedBlankNodeBuilder.computeCanonicalBlankNodes(
                documentIri, oldFrameworkGraph, mergeContract),
        mergeContract,
        clock,
        isFrameworkData: true, // Mark as framework data
      );
      // add framework property changes
      propertyChanges.addAll(frameworkMetadata.propertyChanges);

      // Add all framework metadata triples
      documentTriples.addNodes(documentIri, SyncManagedDocument.hasStatement,
          frameworkMetadata.metadataGraph);

      // Add all app data triples
      documentTriples.addAll(appData.triples);

      crdtDocument = RdfGraph.fromTriples(documentTriples);

      // TODO: maybe not set updatedAt to physical time of the crdt changes,
      // but use PhysicalTimestampFactory to get "now"?
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

      _log.info(
          'Successfully saved document $documentIri with ${propertyChanges.length} property changes');
      return (
        documentIri: documentIri,
        resourceIri: resourceIri,
        crdtDocument: crdtDocument,
        appData: appData,
        previousCursor: saveResult.previousCursor,
        currentCursor: saveResult.currentCursor,
        missingGroupIndices: missingGroupIndices,
        physicalTime: clock.physicalTime,
      );
    } on UnidentifiedBlankNodeException catch (e, stackTrace) {
      _log.severe('Save operation failed for type $type', e, stackTrace);
      final blankNode = e.blankNode;
      _throwIfUsedIn(stackTrace, "Old Document", oldDocument, blankNode);
      _throwIfUsedIn(stackTrace, "New App Data", appData, blankNode);
      _throwIfUsedIn(
          stackTrace, "New Framework Data", frameworkGraph, blankNode);
      _throwIfUsedIn(stackTrace, "New Document", crdtDocument, blankNode);
      rethrow;
    } catch (e, stackTrace) {
      _log.severe('Save operation failed for type $type', e, stackTrace);
      rethrow;
    }
  }

  void _throwIfUsedIn(StackTrace stackTrace, String context,
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

  /// Close the sync system and free resources.
  Future<void> close() async {
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
      CurrentCrdtClock clock,
      {bool isFrameworkData = false}) {
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
          physicalClock: clock.physicalTime,
        );

        metadataGraphs.addAll(metadataGraph);

        // Record property change using canonical IRI (for identified blank nodes) or IRI
        for (final propertyChangeIri in addedSubject.propertyChangeIris) {
          propertyChanges.add(PropertyChange(
            resourceIri: propertyChangeIri,
            propertyIri: predicate,
            changedAtMs: clock.physicalTime,
            changeLogicalClock: clock.logicalTime,
            isFrameworkProperty: isFrameworkData,
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
          physicalClock: clock.physicalTime,
        );

        metadataGraphs.addAll(metadataGraph);

        // Record property change using canonical IRI (for identified blank nodes) or IRI
        for (final propertyChangeIri in entry.key.propertyChangeIris) {
          propertyChanges.add(PropertyChange(
            resourceIri: propertyChangeIri,
            propertyIri: predicate,
            changedAtMs: clock.physicalTime,
            changeLogicalClock: clock.logicalTime,
            isFrameworkProperty: isFrameworkData,
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

  Future<bool> hasDocument(IriTerm documentIri) async {
    return (await _storage.getDocument(documentIri) != null);
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
