import 'package:locorda_core/src/crdt/crdt_types.dart';
import 'package:locorda_core/src/generated/_index.dart';
import 'package:locorda_core/src/hlc_service.dart';
import 'package:locorda_core/src/mapping/framework_iri_generator.dart';
import 'package:locorda_core/src/mapping/identified_blank_node_builder.dart';
import 'package:locorda_core/src/mapping/merge_contract.dart';
import 'package:locorda_core/src/mapping/metadata_generator.dart';
import 'package:locorda_core/src/rdf/rdf_extensions.dart';
import 'package:locorda_core/src/storage/storage_interface.dart';
import 'package:locorda_core/src/sync/data_types.dart';
import 'package:logging/logging.dart';
import 'package:rdf_core/rdf_core.dart';

final _log = Logger('RemoteDocumentMerger');

/// Result of merging local and remote document states.
class MergeResult {
  /// The merged document (may be same as local if remote had no new changes).
  final RdfGraph mergedGraph;

  MergeResult({
    required this.mergedGraph,
  });
}

/// Handles CRDT-based merging of local and remote document states.
///
/// Implements property-level CRDT merge following the specification in
/// CRDT-SPECIFICATION.md Section 5 (Merge Process Details).
class RemoteDocumentMerger {
  // Storage will be needed for property change history during actual merge
  // ignore: unused_field
  final Storage _storage;
  final HlcService _hlcService;

  // Will be needed once proper CRDT property merge is implemented

  final CrdtTypeRegistry _crdtTypeRegistry;
  final FrameworkIriGenerator _iriGenerator;

  late final IdentifiedBlankNodeBuilder _identifiedBlankNodeBuilder =
      IdentifiedBlankNodeBuilder(iriGenerator: _iriGenerator);

  // Will be needed once proper CRDT property merge is implemented
  // ignore: unused_field
  late final MetadataGenerator _metadataGenerator =
      MetadataGenerator(frameworkIriGenerator: _iriGenerator);

  RemoteDocumentMerger({
    required Storage storage,
    required HlcService hlcService,
    required CrdtTypeRegistry crdtTypeRegistry,
    required FrameworkIriGenerator frameworkIriGenerator,
  })  : _storage = storage,
        _hlcService = hlcService,
        _crdtTypeRegistry = crdtTypeRegistry,
        _iriGenerator = frameworkIriGenerator;

  /// Merge local document with remote version using CRDT rules.
  ///
  /// Implements the merge algorithm from CRDT-SPECIFICATION.md Section 5:
  /// 1. Identify Statement and Clock subjects (framework metadata)
  /// 2. Merge Clocks (max of logical/physical times + increment own installation)
  /// 3. Organize Statements for efficient lookup during property merge
  /// 4. Iterate over all subjects (except Statement/Clock subjects)
  /// 5. For each subject, iterate over properties and merge using CRDT algorithms
  /// 6. Property merge returns merged values AND merged statements (tombstones)
  /// 7. Build result document with merged triples, statements, and merged clock
  ///
  /// Parameters:
  /// - [mergeContract]: Contract defining CRDT algorithms per property
  /// - [documentIri]: The document being synchronized
  /// - [localGraph]: Current local state (may be null if new from remote)
  /// - [remoteGraph]: Remote state (may be null if deleted remotely)
  ///
  /// Returns: Merge result indicating merged state and sync direction.
  Future<MergeResult> merge({
    required MergeContract mergeContract,
    required IriTerm documentIri,
    required RdfGraph? localGraph,
    required RdfGraph? remoteGraph,
  }) async {
    final mergeContext = CrdtMergeContext(
      iriGenerator: _iriGenerator,
      metadataGenerator: _metadataGenerator,
    );

    _log.fine('Merging document $documentIri');

    // Handle null cases
    if (remoteGraph == null) {
      _log.fine('Remote is null - keeping local');
      return MergeResult(
        mergedGraph: localGraph!,
      );
    }

    if (localGraph == null) {
      _log.fine('Local is null - accepting remote');
      return MergeResult(
        mergedGraph: remoteGraph,
      );
    }

    // Organize the graphs
    final localOGraph =
        OrganizedGraph.fromGraph(documentIri, localGraph, _hlcService);
    final remoteOGraph =
        OrganizedGraph.fromGraph(documentIri, remoteGraph, _hlcService);

    // Step 4-7: Iterate subjects, merge properties per CRDT type
    final mergeResults = _mergeSubjectsAndProperties(
      documentIri,
      localOGraph,
      remoteOGraph,
      mergeContract,
      mergeContext,
    );

    _log.fine('Merged ${mergeResults.mergedTriples.length} triples ');

    // Step 8: Build final result document
    final result = _buildResultDocument(
      documentIri: documentIri,
      mergeResults: mergeResults,
      localGraph: localGraph,
      remoteGraph: remoteGraph,
      mergeContract: mergeContract,
    );

    return result;
  }

  /// Merges all subjects and their properties using CRDT algorithms.
  ///
  /// For each subject (excluding clock and statement subjects):
  /// 1. Compute identified blank nodes for both graphs
  /// 2. Get all properties on the subject
  /// 3. For each property, call appropriate CRDT merge algorithm
  /// 4. Collect merged values and statements
  ///
  /// Returns merged triples and metadata about the merge.
  MergeResults _mergeSubjectsAndProperties(
    IriTerm documentIri,
    OrganizedGraph localGraph,
    OrganizedGraph remoteGraph,
    MergeContract mergeContract,
    CrdtMergeContext mergeContext,
  ) {
    final mergedSubjects =
        MergeSubject.createMergeSubjects(localGraph, remoteGraph)
            .map((subject) => _mergeSubject(
                  documentIri,
                  subject,
                  localGraph,
                  remoteGraph,
                  mergeContract,
                  mergeContext,
                ));

    return MergeResults.join(mergedSubjects);
  }

  MergeResults _mergeSubject(
    IriTerm documentIri,
    MergeSubject subject,
    OrganizedGraph localGraph,
    OrganizedGraph remoteGraph,
    MergeContract mergeContract,
    CrdtMergeContext mergeContext,
  ) {
    // FIXME: Implement subject deletion handling!

    if (subject.type == MergeSubjectType.blankNodeIdentifier ||
        subject.type == MergeSubjectType.statement) {
      // Skip blank node identifier and statement subjects - they need to be handled
      // differently (as part of property merges).
      // Note though, that the clock entries will be merged here like all other subjects
      return MergeResults.empty();
    }
    // Get all properties for this subject from both graphs
    final allPredicates = <RdfPredicate>{
      if (subject.localSubject != null)
        ...localGraph.fullGraph
            .matching(subject: subject.localSubject)
            .predicates,
      if (subject.remoteSubject != null)
        ...remoteGraph.fullGraph
            .matching(subject: subject.remoteSubject)
            .predicates,
    };

    // In the end: the type itself is merged as a property like any other, so
    // this is only for determining the CRDT algorithm to use per property.
    // We ensure to be deterministic by sorting and picking the first type IRI from the merged set.
    final localTypeIris = _getTypes(subject.localSubject, localGraph);
    final remoteTypeIris = _getTypes(subject.remoteSubject, remoteGraph);
    final typeIri = ({...localTypeIris, ...remoteTypeIris}.toList()
          ..sort((a, b) => a.value.compareTo(b.value)))
        .firstOrNull;

    // Merge each property individually
    final predicateMergeResults = <MergeResults>[];
    for (final predicate in allPredicates) {
      final algorithmIri =
          mergeContract.getEffectiveMergeWith(typeIri, predicate);
      final type = _crdtTypeRegistry.getType(algorithmIri);
      final result = type.remoteMerge(
          subject: subject,
          predicate: predicate,
          local: localGraph,
          remote: remoteGraph,
          mergeContext: mergeContext);
      if (result != null) {
        predicateMergeResults.add(result);
      }
    }
    return MergeResults.join(predicateMergeResults);
  }

  Set<IriTerm> _getTypes(RdfSubject? subject, OrganizedGraph graph) {
    return subject == null
        ? const {}
        : graph.fullGraph.getMultiValueObjects<IriTerm>(subject, Rdf.type);
  }

  /// Builds the final merged document with clock, data, and statements.
  ///
  /// Per CRDT spec Section 2.3:
  /// - Increments own installation's logical time in merged clock
  /// - Combines merged triples, statements, and clock
  /// - Determines if local or remote had changes (for sync decisions)
  ///
  /// Returns complete MergeResult ready for storage or transmission.
  MergeResult _buildResultDocument({
    required IriTerm documentIri,
    required MergeResults mergeResults,
    required RdfGraph localGraph,
    required RdfGraph remoteGraph,
    required MergeContract mergeContract,
  }) {
    final allTriples = <Triple>{
      ...mergeResults.mergedTriples
          // filter out old clock hash triples - clock hash will be recomputed
          // and appended below
          .where((t) => !(t.subject == documentIri &&
              t.predicate ==
                  SyncManagedDocument
                      .crdtClockHash)), // Exclude old clock entries
    };

    final preliminaryGraph = RdfGraph.fromTriples(allTriples);
    final identifiedBlankNodes =
        _identifiedBlankNodeBuilder.computeCanonicalBlankNodes(
            documentIri, preliminaryGraph, mergeContract);
    final identifiedBlankNodeTriples = identifiedBlankNodes
        .identifiedMap.entries
        .expand((e) => e.value.expand((canonicalIri) => [
              Triple(documentIri, SyncManagedDocument.hasBlankNodeMapping,
                  canonicalIri),
              Triple(canonicalIri, SyncBlankNodeMapping.blankNode, e.key)
            ]));

    // Add statement reification triples
    final statementTriples = mergeResults.mergedStatements.values
        .map((stmt) => switch (stmt.key) {
              SubjectMetadataStatement(subject: var subject) =>
                _metadataGenerator.createResourceMetadata(
                    documentIri,
                    IdTerm.create(subject, identifiedBlankNodes),
                    (subject) =>
                        _convertToTriples(stmt, identifiedBlankNodes, subject)),
              SubjectPredicateMetadataStatement(
                subject: var subject,
                predicate: var predicate
              ) =>
                _metadataGenerator.createPropertyMetadata(
                    documentIri,
                    IdTerm.create(subject, identifiedBlankNodes),
                    predicate,
                    (subject) =>
                        _convertToTriples(stmt, identifiedBlankNodes, subject)),
              TripleMetadataStatement(
                subject: var subject,
                predicate: var predicate,
                object: var object
              ) =>
                _metadataGenerator.createPropertyValueMetadata(
                  documentIri,
                  IdTerm.create(subject, identifiedBlankNodes),
                  predicate,
                  IdTerm.create(object, identifiedBlankNodes),
                  (subject) =>
                      _convertToTriples(stmt, identifiedBlankNodes, subject),
                ),
            })
        .expand((nodes) => nodes.expand((n) => [
              Triple(documentIri, SyncManagedDocument.hasStatement, n.$1),
              ...n.$2.triples
            ]));

    final mergedClock =
        _hlcService.getCurrentClock(preliminaryGraph, documentIri);

    final mergedGraph = preliminaryGraph.withTriples([
      Triple(documentIri, SyncManagedDocument.crdtClockHash,
          LiteralTerm(mergedClock.hash)),
      ...identifiedBlankNodeTriples,
      ...statementTriples,
    ]);

    return MergeResult(
      mergedGraph: mergedGraph,
    );
  }

  Iterable<Triple> _convertToTriples(
    MetadataStatement stmt,
    IdentifiedBlankNodes<IriTerm> identifiedBlankNodes,
    RdfSubject subject,
  ) {
    return stmt.predicateObjectMap.entries.expand((e) => e.value
        .expand<RdfObject>((v) => switch (v) {
              IriTerm() || LiteralTerm() => [v],
              BlankNodeTerm bnode =>
                identifiedBlankNodes.getCanonicalIris(bnode)
            })
        .map((v) => Triple(
              subject,
              e.key,
              v,
            )));
  }
}
