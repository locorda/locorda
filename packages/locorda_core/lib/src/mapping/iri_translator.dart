import 'package:locorda_core/src/config/sync_graph_config.dart';
import 'package:locorda_core/src/mapping/resource_locator.dart';
import 'package:rdf_core/rdf_core.dart';

/// Translates between external (user-friendly) and internal (canonical) IRIs
///
/// External IRIs follow custom templates (e.g., https://example.com/categories/work)
/// Internal IRIs use the LocalResourceLocator format (tag:locorda.org,2025:l:...)
///
/// This enables applications to work with friendly URIs while the framework
/// uses stable, structured identifiers internally.
class IriTranslator {
  final ResourceLocator _resourceLocator;
  final Map<IriTerm, ResourceGraphConfig> _configByType;

  /// Maps external IRI prefixes to their type IRIs for efficient lookup
  final Map<String, IriTerm> _prefixToType = {};

  IriTranslator(
      {required ResourceLocator resourceLocator,
      required List<ResourceGraphConfig> resourceConfigs})
      : _resourceLocator = resourceLocator,
        _configByType = {
          for (final config in resourceConfigs) config.typeIri: config
        } {
    // Build prefix-to-type mapping for efficient external IRI detection
    for (final config in resourceConfigs) {
      final template = config.documentIriTemplate;
      if (template != null) {
        _prefixToType[template.prefix] = config.typeIri;
      }
    }
  }

  /// Translates an external IRI to internal IRI
  ///
  /// If the IRI matches a documentIriTemplate, extracts the ID and converts to internal format.
  /// If no template matches, returns the IRI unchanged (already internal or unmanaged).
  ///
  /// Example:
  /// - Input: https://example.com/categories/work#it
  /// - Output: tag:locorda.org,2025:l:aHR0...#it
  IriTerm externalToInternal(IriTerm externalIri) {
    final iriValue = externalIri.value;

    // Extract fragment if present
    final fragmentIndex = iriValue.indexOf('#');
    final documentIriValue =
        fragmentIndex >= 0 ? iriValue.substring(0, fragmentIndex) : iriValue;
    final fragment =
        fragmentIndex >= 0 ? iriValue.substring(fragmentIndex + 1) : null;

    // Try to match against templates using prefix lookup
    for (final entry in _prefixToType.entries) {
      final prefix = entry.key;
      if (!documentIriValue.startsWith(prefix)) continue;

      final typeIri = entry.value;
      final config = _configByType[typeIri]!;
      final template = config.documentIriTemplate!;

      final id = template.extractId(documentIriValue);
      if (id != null) {
        // Found a match - convert to internal IRI
        final identifier = fragment != null
            ? ResourceIdentifier(typeIri, id, fragment)
            : ResourceIdentifier.document(typeIri, id);

        return _resourceLocator.toIri(identifier);
      }
    }

    // No template match - IRI is either already internal or unmanaged
    return externalIri;
  }

  /// Translates an internal IRI to external IRI
  ///
  /// If the IRI is a LocalResourceLocator IRI and has a documentIriTemplate configured,
  /// converts to the external format. Otherwise returns unchanged.
  ///
  /// Example:
  /// - Input: tag:locorda.org,2025:l:aHR0...#it
  /// - Output: https://example.com/categories/work#it
  IriTerm internalToExternal(IriTerm internalIri) {
    // Check if this is a local IRI
    if (!LocalResourceLocator.isLocalIri(internalIri)) {
      return internalIri;
    }

    // Extract type and ID from internal IRI
    // We need to try all possible type IRIs to find a match
    for (final config in _configByType.values) {
      if (config.documentIriTemplate == null) continue;

      try {
        final identifier =
            _resourceLocator.fromIri(config.typeIri, internalIri);

        // Successfully extracted - convert to external IRI
        final template = config.documentIriTemplate!;
        final externalDocumentIri = template.toIri(identifier.id);
        final externalIriValue = identifier.fragment != null
            ? '$externalDocumentIri#${identifier.fragment}'
            : externalDocumentIri;

        return IriTerm(externalIriValue);
      } catch (e) {
        // This type didn't match - try next one
        continue;
      }
    }

    // No template configured or couldn't extract - return as is
    return internalIri;
  }

  /// Translates all IRIs in a graph from external to internal format
  ///
  /// Converts all subject, predicate, and object IRIs that match configured templates
  RdfGraph translateGraphToInternal(RdfGraph externalGraph) {
    if (_prefixToType.isEmpty) {
      return externalGraph;
    }
    final triples = externalGraph.triples.map((triple) {
      final subject = switch (triple.subject) {
        IriTerm iri => externalToInternal(iri),
        _ => triple.subject,
      };

      // Predicates are always IriTerms
      final predicate =
          externalToInternal(triple.predicate as IriTerm) as RdfPredicate;

      final object = switch (triple.object) {
        IriTerm iri => externalToInternal(iri),
        _ => triple.object,
      };

      return Triple(subject, predicate, object);
    });

    return RdfGraph.fromTriples(triples);
  }

  /// Translates all IRIs in a graph from internal to external format
  ///
  /// Converts all subject, predicate, and object IRIs that have templates configured
  RdfGraph translateGraphToExternal(RdfGraph internalGraph) {
    if (_prefixToType.isEmpty) {
      return internalGraph;
    }
    final triples = internalGraph.triples.map((triple) {
      final subject = switch (triple.subject) {
        IriTerm iri => internalToExternal(iri),
        _ => triple.subject,
      };

      // Predicates are always IriTerms
      final predicate =
          internalToExternal(triple.predicate as IriTerm) as RdfPredicate;

      final object = switch (triple.object) {
        IriTerm iri => internalToExternal(iri),
        _ => triple.object,
      };

      return Triple(subject, predicate, object);
    });

    return RdfGraph.fromTriples(triples);
  }
}
