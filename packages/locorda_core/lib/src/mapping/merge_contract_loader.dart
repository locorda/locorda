import 'dart:collection';

import 'package:locorda_core/src/generated/_index.dart';
import 'package:locorda_core/src/mapping/merge_contract.dart';
import 'package:locorda_core/src/mapping/recursive_rdf_loader.dart';
import 'package:locorda_core/src/rdf/rdf_extensions.dart';
import 'package:logging/logging.dart';
import 'package:rdf_core/rdf_core.dart';

final _log = Logger('MergeContractLoader');

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

class CachingMergeContractLoader implements MergeContractLoader {
  final MergeContractLoader _inner;
  final LinkedHashMap<String, Future<MergeContract>> _cache = LinkedHashMap();
  final int maxCacheSize;

  CachingMergeContractLoader(this._inner, {this.maxCacheSize = 50});

  String _cacheKey(List<IriTerm> iris) => iris.length == 1
      ? iris.first.value
      : iris.map((iri) => iri.value).join('|');

  @override
  Future<MergeContract> load(List<IriTerm> isGovernedBy) {
    final key = _cacheKey(isGovernedBy);

    // Check if already in cache (and move to end for LRU)
    if (_cache.containsKey(key)) {
      final future = _cache.remove(key)!;
      _cache[key] = future;
      return future;
    }

    // Load and cache the result
    final future = _inner.load(isGovernedBy).catchError((error) {
      // Remove from cache on error to allow retry
      _cache.remove(key);
      return Future<MergeContract>.error(error);
    });

    _cache[key] = future;

    // Evict oldest entry if cache is full
    if (_cache.length > maxCacheSize) {
      final oldestKey = _cache.keys.first;
      _cache.remove(oldestKey);
    }

    return future;
  }
}

abstract interface class MergeContractLoader {
  Future<MergeContract> load(List<IriTerm> isGovernedBy);
}

class StandardMergeContractLoader implements MergeContractLoader {
  final RecursiveRdfLoader fetcher;

  StandardMergeContractLoader(this.fetcher);

  @override
  Future<MergeContract> load(List<IriTerm> isGovernedBy) async {
    final loadedContractDocuments = await fetcher.loadRdfDocumentsRecursively(
        isGovernedBy,
        extractors: const [DocumentMappingDependencyExtractor()]);
    final all = loadedContractDocuments.values.mergeGraphs();

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
        ?.booleanValue;
    final isIdentifying = graph
        .findSingleObject<LiteralTerm>(ref, McRule.isIdentifying)
        ?.booleanValue;
    final isPathIdentifying = graph
        .findSingleObject<LiteralTerm>(ref, McRule.isPathIdentifying)
        ?.booleanValue;

    return PredicateRule(
      predicateIri: predicateIri,
      mergeWith: mergeWithIri,
      stopTraversal: stopTraversal,
      isIdentifying: isIdentifying,
      isPathIdentifying: isPathIdentifying,
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
