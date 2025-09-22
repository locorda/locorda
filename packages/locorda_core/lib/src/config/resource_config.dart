/// Resource-focused configuration for CRDT sync setup.
///
/// This provides a resource-centric API where all configuration flows from
/// "what resources am I working with?" rather than separate configuration
/// of indices, mappings, and paths.
library;

import 'package:rdf_core/rdf_core.dart';
import 'package:rdf_mapper/rdf_mapper.dart';
import 'package:locorda_core/src/index/index_config.dart';
import 'package:locorda_core/src/index/regex_transform_validation.dart';
import 'validation.dart';

/// Configuration for a single resource type in the sync system.
///
/// Organizes all resource-specific configuration in one place:
/// - Default storage paths on the Pod
/// - CRDT mapping information
/// - Index configurations for this resource
class ResourceConfig {
  /// The Dart type this configuration applies to.
  final Type type;

  /// Uri to the CRDT mapping file for this resource type.
  final Uri crdtMapping;

  /// Index configurations for this resource type.
  /// Can include multiple indices (e.g., by category, by date, full index).
  final List<CrdtIndexConfig> indices;

  const ResourceConfig({
    required this.type,
    required this.crdtMapping,
    this.indices = const [],
  });

  /// Create a resource config with a simple single index.
  ResourceConfig.withSingleIndex({
    required this.type,
    required this.crdtMapping,
    required CrdtIndexConfig index,
  }) : indices = [index];
}

/// Configuration for the entire sync system organized by resources.
class SyncConfig {
  /// All resource configurations for the application.
  final List<ResourceConfig> resources;

  const SyncConfig({
    required this.resources,
  });

  /// Get all index configurations across all resources.
  List<CrdtIndexConfig> getAllIndices() {
    return resources.expand((resource) => resource.indices).toList();
  }

  /// Get resource configuration for a specific type.
  ResourceConfig? getResourceConfig(Type type) {
    return resources.cast<ResourceConfig?>().firstWhere(
          (resource) => resource?.type == type,
          orElse: () => null,
        );
  }

  Map<Type, IriTerm> buildResourceTypeCache(RdfMapper _mapper) {
    final resourceTypeCache = <Type, IriTerm>{};
    for (final resource in resources) {
      if (!resourceTypeCache.containsKey(resource.type)) {
        final typeIri = _getTypeIri(_mapper, resource);
        if (typeIri != null) {
          resourceTypeCache[resource.type] = typeIri;
        }
      }
    }
    return resourceTypeCache;
  }

  static IriTerm? _getTypeIri(RdfMapper mapper, ResourceConfig resource) {
    final registry = mapper.registry;
    try {
      return registry.getResourceSerializerByType(resource.type).typeIri;
    } on SerializerNotFoundException {
      return null;
    }
  }

  /// Validates an IRI string by attempting to construct an IriTerm from it.
  /// Adds an error to the ValidationResult if the IRI is invalid.
  static void _validateIri(String iri, ValidationResult result, String context,
      {Map<String, Object>? contextData}) {
    try {
      IriTerm(iri);
    } catch (e) {
      result.addError('$context: Invalid IRI "$iri" - $e', context: {
        'iri': iri,
        'validation_error': e.toString(),
        ...?contextData,
      });
    }
  }

  /// Validate this configuration for consistency and correctness.
  ValidationResult validate(
    Map<Type, IriTerm> resourceTypeCache, {
    required RdfMapper mapper,
  }) {
    final result = ValidationResult();

    _validateResourceUniqueness(result, resourceTypeCache);
    _validateCrdtMappings(result);
    _validateIndexConfigurations(result);

    _validateMapperTypes(result, mapper);

    return result;
  }

  void _validateResourceUniqueness(
      ValidationResult result, Map<Type, IriTerm> resourceTypeCache) {
    // Check for duplicate Dart types
    final dartTypes = <Type>{};
    final rdfTypeIris = <String, Type>{};

    for (final resource in resources) {
      // Check for duplicate Dart types
      if (dartTypes.contains(resource.type)) {
        result.addError(
            'Duplicate resource type: ${resource.type}. Each Dart type can only be configured once.',
            context: {'type': resource.type});
        continue; // Skip further processing for this resource
      }
      dartTypes.add(resource.type);

      // Check for RDF type IRI collisions
      try {
        final rdfTypeIri = resourceTypeCache[resource.type];
        if (rdfTypeIri != null) {
          final rdfTypeIriString = rdfTypeIri.iri;
          if (rdfTypeIris.containsKey(rdfTypeIriString)) {
            result.addError(
                'RDF type IRI collision: ${resource.type} and ${rdfTypeIris[rdfTypeIriString]} '
                'both use $rdfTypeIriString. Each Dart type must have a unique RDF type IRI.',
                context: {
                  'conflicting_types': [
                    resource.type,
                    rdfTypeIris[rdfTypeIriString]
                  ],
                  'rdf_iri': rdfTypeIriString
                });
          }
          rdfTypeIris[rdfTypeIriString] = resource.type;
        } else {
          result.addError(
              'No RDF type IRI found for ${resource.type}. Resource types must be annotated with @PodResource.',
              context: {'type': resource.type});
        }
      } catch (e) {
        result.addError(
            'Could not resolve RDF type IRI for ${resource.type}: $e',
            context: {'type': resource.type, 'error': e.toString()});
      }
    }
  }

  void _validateCrdtMappings(ValidationResult result) {
    for (final resource in resources) {
      final uri = resource.crdtMapping;

      if (!uri.isAbsolute) {
        result.addError(
            'CRDT mapping URI must be absolute for ${resource.type}: $uri',
            context: {'type': resource.type, 'uri': uri});
      }

      if (uri.scheme == 'http') {
        result.addWarning(
            'CRDT mapping URI should use HTTPS for ${resource.type}: $uri',
            context: {'type': resource.type, 'uri': uri});
      }
    }
  }

  void _validateIndexConfigurations(ValidationResult result) {
    // Track local names per index item type across all resources
    final localNamesByItemType = <Type, Map<String, List<Type>>>{};
    // Track groupKeyType and localName combinations for GroupIndex uniqueness
    final groupKeyLocalNameCombinations = <String, List<(Type, String)>>{};

    for (final resource in resources) {
      for (final index in resource.indices) {
        // Check for empty or invalid local names
        if (index.localName.isEmpty) {
          result.addError(
              'Index local name cannot be empty for ${resource.type}',
              context: {'type': resource.type, 'index': index});
        }

        // Track local names by index item type (if index has an item type)
        if (index.item != null) {
          final itemType = index.item!.itemType;
          final localNamesForType = localNamesByItemType.putIfAbsent(
              itemType, () => <String, List<Type>>{});

          localNamesForType
              .putIfAbsent(index.localName, () => [])
              .add(resource.type);
        }

        // Validate GroupIndex specific requirements
        if (index is GroupIndex) {
          if (index.groupingProperties.isEmpty) {
            result.addError(
                'GroupIndex must have at least one grouping property for ${resource.type}',
                context: {'type': resource.type, 'index': index});
          }

          // Track groupKeyType + localName combination for uniqueness
          final groupKeyTypeName = index.groupKeyType.toString();
          final combinationKey = '$groupKeyTypeName:${index.localName}';
          groupKeyLocalNameCombinations
              .putIfAbsent(combinationKey, () => [])
              .add((resource.type, index.localName));

          // Validate grouping properties
          for (final property in index.groupingProperties) {
            // Validate predicate IRI
            _validateIri(
              property.predicate.iri,
              result,
              'GroupingProperty predicate for ${resource.type}',
              contextData: {
                'type': resource.type,
                'property': property.predicate.iri,
                'index': index,
              },
            );

            // Check for zero or negative hierarchy levels
            if (property.hierarchyLevel <= 0) {
              result.addError(
                  'GroupingProperty hierarchy level must be positive for ${resource.type}. Got: ${property.hierarchyLevel}',
                  context: {
                    'type': resource.type,
                    'property': property.predicate.iri,
                    'hierarchyLevel': property.hierarchyLevel,
                    'index': index,
                  });
            }

            // Check for empty missing value
            if (property.missingValue != null &&
                property.missingValue!.isEmpty) {
              result.addError(
                  'GroupingProperty missing value cannot be empty for ${resource.type}. Use null to indicate no default value.',
                  context: {
                    'type': resource.type,
                    'property': property.predicate.iri,
                    'missingValue': property.missingValue,
                    'index': index,
                  });
            }

            // Validate regex transforms
            if (property.transforms != null &&
                property.transforms!.isNotEmpty) {
              final transformValidationResult =
                  RegexTransformValidator.validateList(property.transforms!);
              result.addSubvalidationResult(
                  '[${resource.type}][Grouping][${property.predicate.iri}]',
                  {
                    'type': resource.type,
                    'property': property.predicate.iri,
                    'index': index,
                  },
                  transformValidationResult);
            }
          }

          // Check for hierarchy level gaps
          final hierarchyLevels = index.groupingProperties
              .map((p) => p.hierarchyLevel)
              .toSet()
              .toList()
            ..sort();

          for (int i = 1; i < hierarchyLevels.length; i++) {
            if (hierarchyLevels[i] - hierarchyLevels[i - 1] > 1) {
              result.addWarning(
                  'Hierarchy level gap detected in GroupIndex for ${resource.type}: '
                  'level ${hierarchyLevels[i - 1]} is followed by ${hierarchyLevels[i]}. '
                  'Consider using consecutive hierarchy levels for better organization.',
                  context: {
                    'type': resource.type,
                    'gap_before': hierarchyLevels[i - 1],
                    'gap_after': hierarchyLevels[i],
                    'index': index,
                  });
            }
          }
        }
      }
    }

    // Check for duplicate local names within the same index item type
    localNamesByItemType.forEach((itemType, localNames) {
      localNames.forEach((localName, resourceTypes) {
        if (resourceTypes.length > 1) {
          result.addError(
              'Duplicate index local name "$localName" for index item type $itemType. '
              'Used by resources: ${resourceTypes.join(', ')}. '
              'Local names must be unique per index item type.',
              context: {
                'localName': localName,
                'itemType': itemType,
                'conflictingResources': resourceTypes
              });
        }
      });
    });

    // Check for duplicate groupKeyType + localName combinations
    groupKeyLocalNameCombinations.forEach((combinationKey, entries) {
      if (entries.length > 1) {
        final resourceTypes = entries.map((e) => e.$1).toList();
        final localName = entries.first.$2;
        result.addError(
            'Duplicate groupKeyType and localName combination: $combinationKey. '
            'Used by resources: ${resourceTypes.join(', ')}. '
            'GroupIndex groupKeyType and localName combinations must be unique.',
            context: {
              'combinationKey': combinationKey,
              'localName': localName,
              'conflictingResources': resourceTypes
            });
      }
    });
  }

  void _validateMapperTypes(ValidationResult result, RdfMapper mapper) {
    // Collect all types that need mappers
    final requiredTypes = <Type>{};

    // Add all resource dart types
    for (final resource in resources) {
      requiredTypes.add(resource.type);
    }

    // Add all index item types and groupKeyTypes
    for (final resource in resources) {
      for (final index in resource.indices) {
        if (index.item != null) {
          requiredTypes.add(index.item!.itemType);
        }

        // Add groupKeyType for GroupIndex
        if (index is GroupIndex) {
          requiredTypes.add(index.groupKeyType);
        }
      }
    }

    // Check if mapper can handle each required type
    for (final type in requiredTypes) {
      // Skip primitive types like String - they're not mappable types
      if (type == String || type == int || type == double || type == bool) {
        result.addError(
            'Type $type is a primitive type and cannot be used as a mappable resource, groupKey, or itemType. '
            'Use proper RDF-mapped classes instead.',
            context: {'type': type});
        continue;
      }

      // Try to get a serializer for the type - this is the definitive test
      try {
        final serializer = mapper.registry.getResourceSerializerByType(type);
        if (serializer.typeIri != null) {
          var hasDeserializer = mapper.registry
                  .hasGlobalResourceDeserializerForType(serializer.typeIri!) ||
              mapper.registry
                  .hasGlobalResourceDeserializerForType(serializer.typeIri!);
          if (!hasDeserializer) {
            result.addError(
                'Type $type has a serializer but no deserializer registered in RdfMapper. '
                'Ensure the type is properly annotated with @PodResource, @RdfGlobalResource or @RdfLocalResource - or a mapper is implemented and registered manually.',
                context: {'type': type, 'typeIri': serializer.typeIri});
          }
        }
      } on SerializerNotFoundException {
        result.addError(
            'Type $type is not registered in RdfMapper. '
            'Ensure the type is properly annotated with @PodResource, @RdfGlobalResource or @RdfLocalResource - or a mapper is implemented and registered manually.',
            context: {'type': type});
      } catch (e) {
        result.addWarning(
            'Could not verify mapper registration for type $type: $e',
            context: {'type': type, 'error': e.toString()});
      }
    }
  }

  /// Find the resource and index configuration for a given type and local name.
  ///
  /// Searches through all resources and their indices to find a matching
  /// configuration where the index item type matches T and localName matches.
  /// Returns the resource configuration and index configuration as a record,
  /// or null if no match is found.
  ///
  /// This is used during hydration setup to determine how to convert
  /// resources to index items for a specific stream.
  (ResourceConfig, CrdtIndexConfig)? findIndexConfigForType<T>(
      String localName) {
    // Search through all resources and their indices
    for (final resourceConfig in resources) {
      for (final index in resourceConfig.indices) {
        // Check if this index matches our type T and localName
        if (index.item != null &&
            index.item!.itemType == T &&
            index.localName == localName) {
          // Found matching index
          return (resourceConfig, index);
        }
      }
    }
    return null;
  }
}
