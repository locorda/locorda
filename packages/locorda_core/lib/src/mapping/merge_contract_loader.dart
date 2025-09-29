// TODO: generalize to a generic fetcher that also does etag caching etc?
import 'package:locorda_core/src/generated/_index.dart';
import 'package:locorda_core/src/mapping/merge_contract.dart';
import 'package:locorda_core/src/rdf/rdf.dart';
import 'package:logging/logging.dart';
import 'package:rdf_core/rdf_core.dart';

final _log = Logger('MergeContractLoader');

class RdfGraphFetcher {
  Future<RdfGraph> fetch(IriTerm iri) async {
    // Implement fetching logic here
    throw UnimplementedError();
  }
}

abstract interface class DependencyExtractor {
  IriTerm? forType();
  Iterable<IriTerm> extractDependencies(RdfSubject subj, RdfGraph graph);
}

class RecursiveRdfLoader {
  final IriTermFactory iriFactory;
  final RdfGraphFetcher fetcher;

  RecursiveRdfLoader({required this.fetcher, required this.iriFactory});

  Future<void> _loadRecursivelySingle(
      IriTerm inputIri,
      Map<IriTerm, RdfGraph> loadedContracts,
      Map<IriTerm, Future<RdfGraph>> inProgress,
      {List<DependencyExtractor> extractors = const []}) async {
    final iri = inputIri.getDocumentIri(iriFactory);
    // Check if already loaded
    if (loadedContracts.containsKey(iri)) return;

    // Check if currently being loaded, and wait for it
    if (inProgress.containsKey(iri)) {
      final graph = await inProgress[iri]!;
      loadedContracts[iri] = graph;
      return;
    }

    // Start loading and track the future
    final future = fetcher.fetch(iri);
    inProgress[iri] = future;

    final graph = await future;
    loadedContracts[iri] = graph;
    inProgress.remove(iri);

    // Extract isGovernedBy IRIs from the graph
    final type = graph.findSingleObject<IriTerm>(iri, Rdf.type);
    final dependencies = <IriTerm>{};
    for (final extractor in extractors) {
      if (extractor.forType() == null || extractor.forType() == type) {
        final deps = extractor.extractDependencies(iri, graph);
        dependencies.addAll(deps.map((iri) => iri.getDocumentIri(iriFactory)));
      }
    }

    await _loadRecursivelyMulti(dependencies, loadedContracts, inProgress,
        extractors: extractors);
  }

  /// Returns a map of document IRI to loaded RdfGraph, loading dependencies determined by extractors recursively.
  Future<Map<IriTerm, RdfGraph>> loadDocumentsRecursively(
          Iterable<IriTerm> iris,
          {List<DependencyExtractor> extractors = const []}) =>
      _loadRecursivelyMulti(iris, {}, {}, extractors: extractors);

  Future<Map<IriTerm, RdfGraph>> _loadRecursivelyMulti(
      Iterable<IriTerm> iris,
      Map<IriTerm, RdfGraph> loadedContracts,
      Map<IriTerm, Future<RdfGraph>> inProgress,
      {List<DependencyExtractor> extractors = const []}) async {
    if (iris.isNotEmpty) {
      // Process all IRIs concurrently for better performance
      await Future.wait(iris.map((iri) => _loadRecursivelySingle(
          iri, loadedContracts, inProgress,
          extractors: extractors)));
    }

    return loadedContracts;
  }
}

class DocumentMappingDependencyExtractor implements DependencyExtractor {
  const DocumentMappingDependencyExtractor();
  @override
  IriTerm? forType() => McDocumentMapping.classIri;

  @override
  Iterable<IriTerm> extractDependencies(RdfSubject subj, RdfGraph graph) {
    final imports =
        graph.getListObjects<IriTerm>(subj, McDocumentMapping.imports);
    final classMappings =
        graph.getListObjects<IriTerm>(subj, McDocumentMapping.classMapping);
    final predicateMappings =
        graph.getListObjects<IriTerm>(subj, McDocumentMapping.predicateMapping);
    return [...imports, ...classMappings, ...predicateMappings];
  }
}

class MergeContractLoader {
  final RecursiveRdfLoader fetcher;

  MergeContractLoader(this.fetcher);

  Future<MergeContract> load(List<IriTerm> isGovernedBy) async {
    final loadedContractDocuments = await fetcher.loadDocumentsRecursively(
        isGovernedBy,
        extractors: const [DocumentMappingDependencyExtractor()]);
    final all = RdfGraph.fromTriples(
        loadedContractDocuments.values.expand((g) => g.triples));

    /*
    ##### 5.2.2.3. The Contract Hierarchy

    **How Import Resolution Works:**

    1. **Framework Import:** `mc:imports ( mappings:core-v1 )` brings in standard
     CRDT framework mappings for infrastructure predicates like `crdt:installationId`, 
     `crdt:deletedAt`, `crdt:logicalTime`. These use global predicate mappings 
     for consistent behavior across all contexts.

    2. **Application Rules:** The local `mc:classMapping` defines domain-specific
     merge behavior for `meal:ShoppingListEntry` properties. All properties use 
     `algo:LWW_Register` since shopping items are typically single-user managed.

    3. **Precedence Resolution:** Conflicts are resolved using deterministic 
      precedence order following the specificity principle 
      (why `rdf:List` is used instead of multi-valued properties):
      1. **Local Class Mappings** (highest priority) - `mc:classMapping`
      2. **Imported Class Mappings** - from `mc:imports` libraries
      3. **Local Predicate Mappings** - `mc:predicateMapping`
      4. **Imported Predicate Mappings** (lowest priority) - from `mc:imports` libraries

      **Key Principle:** Context-specific rules (class mappings) win over global 
      rules (predicate mappings), regardless of local vs imported source. This 
      ensures that specific behaviors defined for particular contexts aren't 
      accidentally overridden by general global rules.

    */

    // Parse loaded RDF graphs and extract mappings
    final documents =
        isGovernedBy.map((iri) => _parseDocumentMapping(all, iri)).toList();

    return MergeContract.fromDocumentMappings(documents);
  }

  DocumentMapping _parseDocumentMapping(RdfGraph all, RdfSubject subject,
      [Set<RdfSubject>? visited]) {
    final seen = visited ?? <RdfSubject>{};
    seen.add(subject);

    final importRefs =
        all.getListObjects<RdfSubject>(subject, McDocumentMapping.imports);
    final classMappingRefs =
        all.getListObjects<RdfSubject>(subject, McDocumentMapping.classMapping);
    final predicateMappingRefs = all.getListObjects<RdfSubject>(
        subject, McDocumentMapping.predicateMapping);
    final classMappings = _parseClassMappings(all, classMappingRefs);
    final predicateMappings = predicateMappingRefs
        .map((ref) => _parsePredicateMapping(all, ref))
        .whereType<PredicateMapping>()
        .toList();
    final imports = importRefs
        .where((ref) {
          if (seen.contains(ref)) {
            _log.warning(
                'Detected cyclic import in merge contract at $ref, skipping.');
            return false;
          } else {
            return true;
          }
        })
        .map((ref) => _parseDocumentMapping(all, ref, seen))
        .toList();
    return DocumentMapping(
        documentIri: subject,
        imports: imports,
        classMappings: classMappings,
        predicateMappings: predicateMappings);
  }

  PredicateRule? _parseRule(RdfGraph graph, RdfSubject ref) {
    final predicateIri = graph.findSingleObject<IriTerm>(ref, McRule.predicate);
    if (predicateIri == null) {
      _log.warning('Predicate mapping missing mc:predicate: $ref');
      return null;
    }
    final mergeWithIri =
        graph.findSingleObject<IriTerm>(ref, McRule.algoMergeWith);
    final stopTraversal = graph
            .findSingleObject<LiteralTerm>(ref, McRule.stopTraversal)
            ?.booleanValue ??
        false;
    final isIdentifying = graph
            .findSingleObject<LiteralTerm>(ref, McRule.isIdentifying)
            ?.booleanValue ??
        false;

    return PredicateRule(
      predicateIri: predicateIri,
      mergeWith: mergeWithIri,
      stopTraversal: stopTraversal,
      isIdentifying: isIdentifying,
    );
  }

  Map<IriTerm, ClassMapping> _parseClassMappings(
      RdfGraph graph, List<RdfSubject> classMappingRefs) {
    final classMappings = <IriTerm, ClassMapping>{};
    for (final ref in classMappingRefs) {
      if (!graph.hasTriples(
          subject: ref, predicate: Rdf.type, object: McClassMapping.classIri)) {
        _log.warning('Skipping invalid class mapping reference: $ref');
        continue;
      }
      final classIri =
          graph.findSingleObject<IriTerm>(ref, McClassMapping.appliesToClass);
      if (classIri == null) {
        _log.warning('Class mapping missing appliesToClass: $ref');
        continue;
      }
      final predicateRuleRefs =
          graph.getMultiValueObjects<RdfSubject>(ref, McClassMapping.rule);
      final predicateMappings = {
        for (var rule in predicateRuleRefs
            .map((r) => _parseRule(graph, r))
            .whereType<PredicateRule>())
          rule.predicateIri: rule
      };
      if (classMappings.containsKey(classIri)) {
        _log.warning('Duplicate class mapping for $classIri, overwriting.');
      }
      classMappings[classIri] = ClassMapping(classIri, predicateMappings);
    }
    return classMappings;
  }

  PredicateMapping? _parsePredicateMapping(RdfGraph graph, RdfSubject ref) {
    if (!graph.hasTriples(
        subject: ref,
        predicate: Rdf.type,
        object: McPredicateMapping.classIri)) {
      _log.warning('Skipping invalid class mapping reference: $ref');
      return null;
    }
    final predicateRuleRefs =
        graph.getMultiValueObjects<RdfSubject>(ref, McPredicateMapping.rule);
    final rules = {
      for (var rule in predicateRuleRefs
          .map((r) => _parseRule(graph, r))
          .whereType<PredicateRule>())
        rule.predicateIri: rule
    };

    return PredicateMapping(rules);
  }
}
