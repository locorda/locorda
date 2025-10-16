import 'package:locorda_core/src/config/sync_config_base.dart';
import 'package:locorda_core/src/generated/crdt/index.dart';
import 'package:locorda_core/src/index/index_config_base.dart';
import 'package:locorda_core/src/sync/sync_manager.dart';
import 'package:rdf_core/rdf_core.dart';

class IndexItemGraphConfig extends IndexItemConfigBase {
  const IndexItemGraphConfig(super.properties);
  factory IndexItemGraphConfig.fromJson(Map<String, dynamic> json) {
    final propertiesJson = json['properties'] as List<dynamic>;
    final properties = propertiesJson.map((p) => IriTerm(p as String)).toSet();

    return IndexItemGraphConfig(properties);
  }
}

sealed class CrdtIndexGraphConfig extends CrdtIndexConfigBase {
  IndexItemGraphConfig? get item;
}

class FullIndexGraphConfig extends FullIndexConfigBase
    implements CrdtIndexGraphConfig {
  final IndexItemGraphConfig? item;

  const FullIndexGraphConfig(
      {required super.localName, this.item, super.itemFetchPolicy})
      : super(item: item);

  factory FullIndexGraphConfig.fromJson(Map<String, dynamic> json) {
    final localName = json['localName'] as String;
    final itemFetchPolicyStr = json['itemFetchPolicy'] as String?;
    final itemFetchPolicy = switch (itemFetchPolicyStr) {
      'prefetch' => ItemFetchPolicy.prefetch,
      'onRequest' => ItemFetchPolicy.onRequest,
      null => null,
      _ => throw ArgumentError('Unknown itemFetchPolicy: $itemFetchPolicyStr')
    };
    final itemJson = json['item'] as Map<String, dynamic>?;
    final item =
        itemJson != null ? IndexItemGraphConfig.fromJson(itemJson) : null;

    return FullIndexGraphConfig(
        localName: localName, itemFetchPolicy: itemFetchPolicy, item: item);
  }
}

class GroupIndexGraphConfig extends GroupIndexConfigBase
    implements CrdtIndexGraphConfig {
  final IndexItemGraphConfig? item;

  const GroupIndexGraphConfig({
    required super.localName,
    this.item,
    super.groupingProperties = const [],
  }) : super(item: item);

  factory GroupIndexGraphConfig.fromJson(Map<String, dynamic> json) {
    final localName = json['localName'] as String;
    final itemJson = json['item'] as Map<String, dynamic>?;
    final item =
        itemJson != null ? IndexItemGraphConfig.fromJson(itemJson) : null;
    final groupingPropertiesJson =
        json['groupingProperties'] as List<dynamic>? ?? [];
    final groupingProperties = groupingPropertiesJson
        .map((gp) => GroupingProperty.fromJson(gp as Map<String, dynamic>))
        .toList(growable: false);

    return GroupIndexGraphConfig(
        localName: localName,
        groupingProperties: groupingProperties,
        item: item);
  }
}

class DocumentIriTemplate {
  final String template;
  final List<String> variables;

  /// The prefix before the first variable (everything before first '{')
  /// Used for efficient prefix matching when checking if an IRI matches this template
  late final String prefix;

  /// The suffix after the last variable (everything after last '}')
  /// Used for efficient suffix matching when checking if an IRI matches this template
  late final String suffix;

  DocumentIriTemplate._(this.template, this.variables) {
    final firstBraceIndex = template.indexOf('{');
    final lastBraceIndex = template.lastIndexOf('}');

    prefix = firstBraceIndex >= 0
        ? template.substring(0, firstBraceIndex)
        : template;
    suffix = lastBraceIndex >= 0 && lastBraceIndex < template.length - 1
        ? template.substring(lastBraceIndex + 1)
        : '';
  }

  factory DocumentIriTemplate.fromJson(String json) {
    final template = json;
    final variableRegex = RegExp(r'\{([^}]+)\}');
    final variables = variableRegex
        .allMatches(template)
        .map((match) => match.group(1)!)
        .toList(growable: false);

    // Validation: must have exactly one variable and it must be called "id"
    if (variables.length != 1) {
      throw ArgumentError(
          'Document IRI template must have exactly one variable. '
          'Got ${variables.length} variables: $variables in template: $template');
    }

    if (variables.single != 'id') {
      throw ArgumentError('Document IRI template variable must be named "id". '
          'Got: ${variables.single} in template: $template');
    }

    return DocumentIriTemplate._(template, variables);
  }

  /// Efficiently checks if a given IRI matches this template pattern
  ///
  /// First does a quick prefix/suffix check, then extracts the ID if it matches
  /// Returns the extracted URL-decoded ID if the IRI matches, null otherwise
  String? extractId(String iriValue) {
    // Quick prefix check
    if (!iriValue.startsWith(prefix)) {
      return null;
    }

    // Quick suffix check
    if (suffix.isNotEmpty && !iriValue.endsWith(suffix)) {
      return null;
    }

    // Extract the ID value between prefix and suffix
    final startIndex = prefix.length;
    final endIndex =
        suffix.isEmpty ? iriValue.length : iriValue.length - suffix.length;

    if (startIndex >= endIndex) {
      return null;
    }

    final encodedId = iriValue.substring(startIndex, endIndex);

    // URL decode the extracted ID
    return Uri.decodeComponent(encodedId);
  }

  /// Creates an IRI from this template by substituting the URL-encoded ID
  String toIri(String id) {
    // URL encode the ID before substituting
    final encodedId = Uri.encodeComponent(id);
    return template.replaceAll('{id}', encodedId);
  }
}

class ResourceGraphConfig extends ResourceConfigBase {
  final List<CrdtIndexGraphConfig> indices;

  final IriTerm typeIri;
  final DocumentIriTemplate? documentIriTemplate;

  ResourceGraphConfig({
    required this.typeIri,
    required super.crdtMapping,
    required this.indices,
    String? documentIriTemplate,
  })  : documentIriTemplate = documentIriTemplate != null
            ? DocumentIriTemplate.fromJson(documentIriTemplate)
            : null,
        super(indices: indices);

  CrdtIndexGraphConfig getIndexByName(String localName) {
    return indices.firstWhere((i) => i.localName == localName,
        orElse: () =>
            throw ArgumentError('No index found with localName: $localName'));
  }

  factory ResourceGraphConfig.fromJson(Map<String, dynamic> json) {
    final typeIri = IriTerm(json['typeIri'] as String);
    final crdtMappingStr = json['crdtMapping'] as String;
    final crdtMapping = Uri.parse(crdtMappingStr);
    final documentIriTemplate = json['documentIriTemplate'] as String?;

    final indicesJson = json['indices'] as List<dynamic>;
    final indices = <CrdtIndexGraphConfig>[];

    for (final indexJson in indicesJson) {
      final indexType = indexJson['type'] as String;

      switch (indexType) {
        case 'FullIndex':
          indices.add(
              FullIndexGraphConfig.fromJson(indexJson as Map<String, dynamic>));
          break;
        case 'GroupIndex':
          indices.add(GroupIndexGraphConfig.fromJson(
              indexJson as Map<String, dynamic>));
          break;
        default:
          throw ArgumentError('Unknown index type: $indexType');
      }
    }

    return ResourceGraphConfig(
      typeIri: typeIri,
      crdtMapping: crdtMapping,
      indices: indices,
      documentIriTemplate: documentIriTemplate,
    );
  }
}

class SyncGraphConfig extends SyncConfigBase {
  final List<ResourceGraphConfig> resources;

  SyncGraphConfig({
    required this.resources,
    super.autoSyncConfig = const AutoSyncConfig.disabled(),
  }) : super(resources: resources);

  factory SyncGraphConfig.fromJson(Map<String, dynamic> json) {
    final resourcesJson = json['resources'] as List<dynamic>;
    final resources = resourcesJson
        .map((r) => ResourceGraphConfig.fromJson(r as Map<String, dynamic>))
        .toList();

    // Parse auto sync config if present
    final autoSyncJson = json['autoSync'] as Map<String, dynamic>?;
    final autoSyncConfig = autoSyncJson != null
        ? AutoSyncConfig.fromJson(autoSyncJson)
        : const AutoSyncConfig.disabled();

    return SyncGraphConfig(
      resources: resources,
      autoSyncConfig: autoSyncConfig,
    );
  }

  ResourceGraphConfig getResourceConfig(IriTerm type) =>
      resources.firstWhere((r) => r.typeIri == type,
          orElse: () =>
              throw ArgumentError('No resource config found for type: $type'));

  SyncGraphConfig withResourcesAdded(List<ResourceGraphConfig> newResources) {
    final updatedResources = List<ResourceGraphConfig>.from(resources)
      ..addAll(newResources);
    return SyncGraphConfig(
      resources: updatedResources,
      autoSyncConfig: autoSyncConfig,
    );
  }

  /// Find the GroupIndex configuration for the given indexName.
  (ResourceGraphConfig, GroupIndexGraphConfig)? findGroupIndexConfig(
      String indexName) {
    for (final resource in resources) {
      for (final index in resource.indices) {
        if (index is GroupIndexGraphConfig && index.localName == indexName) {
          return (resource, index);
        }
      }
    }
    return null;
  }
}
