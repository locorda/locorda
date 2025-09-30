// TODO: generalize to a generic fetcher that also does etag caching etc?
import 'package:locorda_core/src/generated/rdf.dart';
import 'package:locorda_core/src/rdf/rdf_extensions.dart';
import 'package:rdf_core/rdf_core.dart';
import 'package:http/http.dart' as http;

class HttpRdfGraphFetcher implements RdfGraphFetcher {
  final http.Client httpClient;
  final RdfCore rdfCore;
  HttpRdfGraphFetcher({
    required this.httpClient,
    required this.rdfCore,
  });
  @override
  Future<RdfGraph> fetch(IriTerm iri) async {
    final response = await httpClient.get(Uri.parse(iri.value));
    if (response.statusCode == 200) {
      // Parse the RDF graph from the response body
      return rdfCore.decode(response.body,
          contentType: "text/turtle", documentUrl: iri.value);
    } else {
      throw Exception('Failed to load RDF graph: ${response.statusCode}');
    }
  }
}

abstract interface class RdfGraphFetcher {
  Future<RdfGraph> fetch(IriTerm iri);
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
  Future<Map<IriTerm, RdfGraph>> loadRdfDocumentsRecursively(
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
