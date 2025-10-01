import 'package:locorda_core/src/config/sync_config_base.dart';
import 'package:locorda_core/src/index/index_config_base.dart';
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

class ResourceGraphConfig extends ResourceConfigBase {
  final List<CrdtIndexGraphConfig> indices;

  final IriTerm typeIri;
  ResourceGraphConfig({
    required this.typeIri,
    required super.crdtMapping,
    required this.indices,
  }) : super(indices: indices);

  factory ResourceGraphConfig.fromJson(Map<String, dynamic> json) {
    final typeIri = IriTerm(json['typeIri'] as String);
    final crdtMappingStr = json['crdtMapping'] as String;
    final crdtMapping = Uri.parse(crdtMappingStr);

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
    );
  }
}

class SyncGraphConfig extends SyncConfigBase {
  final List<ResourceGraphConfig> resources;

  SyncGraphConfig({required this.resources}) : super(resources: resources);

  factory SyncGraphConfig.fromJson(Map<String, dynamic> json) {
    final resourcesJson = json['resources'] as List<dynamic>;
    final resources = resourcesJson
        .map((r) => ResourceGraphConfig.fromJson(r as Map<String, dynamic>))
        .toList();

    return SyncGraphConfig(resources: resources);
  }

  ResourceGraphConfig getResourceConfig(IriTerm type) {
    return resources.firstWhere((r) => r.typeIri == type);
  }
}
