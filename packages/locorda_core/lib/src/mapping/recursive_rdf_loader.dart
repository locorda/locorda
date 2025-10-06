// TODO: generalize to a generic fetcher that also does etag caching etc?
import 'package:locorda_core/src/generated/rdf.dart';
import 'package:locorda_core/src/rdf/rdf_extensions.dart';
import 'package:rdf_core/rdf_core.dart';
import 'package:http/http.dart' as http;

abstract interface class Fetcher {
  Future<String> fetch(String url, {String? contentType});
}

class HttpFetcher implements Fetcher {
  final http.Client httpClient;
  HttpFetcher({
    required this.httpClient,
  });

  /// Checks if the server supports content negotiation for the given URL.
  ///
  /// Returns true if the HEAD response indicates the content type matches
  /// the requested type, false otherwise.
  Future<bool> _supportsContentNegotiation(
      String url, String? contentType) async {
    if (contentType == null) return true;

    final headers = <String, String>{'Accept': contentType};
    try {
      final response = await httpClient.head(Uri.parse(url), headers: headers);
      if (response.statusCode != 200) return false;

      final responseContentType = response.headers['content-type'];
      if (responseContentType == null) return false;

      // Check if response content type matches requested type
      // Handle cases like "text/turtle; charset=utf-8"
      return responseContentType
          .toLowerCase()
          .contains(contentType.toLowerCase());
    } catch (e) {
      // If HEAD fails, assume no content negotiation support
      return false;
    }
  }

  @override
  Future<String> fetch(String url, {String? contentType}) async {
    final headers = <String, String>{};
    if (contentType != null) {
      headers['Accept'] = contentType;
    }

    // Check if server supports content negotiation
    final supportsNegotiation =
        await _supportsContentNegotiation(url, contentType);

    // If no content negotiation support and URL doesn't end with .ttl, try appending it
    var fetchUrl = url;
    if (!supportsNegotiation &&
        contentType == 'text/turtle' &&
        !url.endsWith('.ttl')) {
      fetchUrl = '$url.ttl';
    }

    final response =
        await httpClient.get(Uri.parse(fetchUrl), headers: headers);
    if (response.statusCode == 200) {
      return response.body;
    } else {
      throw Exception(
          'Failed to load RDF graph at $fetchUrl: ${response.statusCode}');
    }
  }
}

class StandardRdfGraphFetcher implements RdfGraphFetcher {
  final Fetcher fetcher;
  final RdfCore rdfCore;
  StandardRdfGraphFetcher({
    required this.fetcher,
    required this.rdfCore,
  });
  @override
  Future<RdfGraph> fetch(IriTerm iri) async {
    // Parse the RDF graph from the response body
    return rdfCore.decode(
        await fetcher.fetch(iri.value, contentType: "text/turtle"),
        contentType: "text/turtle",
        documentUrl: iri.value);
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
