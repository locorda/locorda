import 'package:locorda/src/config/locorda_config.dart';
import 'package:locorda/src/config/locorda_config_util.dart';
import 'package:locorda_core/locorda_core.dart';

IndexItemData? _toIndexItemGraphConfig(IndexItem? item) {
  if (item == null) return null;
  return IndexItemData(item.properties);
}

FullIndexData _toFullIndexGraphConfig(
        ResourceConfig parentConfig, FullIndex index) =>
    FullIndexData(
      localName: getIndexName(parentConfig, index),
      item: _toIndexItemGraphConfig(index.item),
      itemFetchPolicy: index.itemFetchPolicy,
    );

GroupIndexData _toGroupIndexGraphConfig(
        ResourceConfig parentConfig, GroupIndex index) =>
    GroupIndexData(
      localName: getIndexName(parentConfig, index),
      item: _toIndexItemGraphConfig(index.item),
      groupingProperties: index.groupingProperties,
    );

CrdtIndexData _toCrdtIndexGraphConfig(
    ResourceConfig parentConfig, CrdtIndex index) {
  if (index is FullIndex) {
    return _toFullIndexGraphConfig(parentConfig, index);
  } else if (index is GroupIndex) {
    return _toGroupIndexGraphConfig(parentConfig, index);
  } else {
    throw ArgumentError('Unknown index type: ${index.runtimeType}');
  }
}

ResourceConfigData _toResourceGraphConfig(
    ResourceConfig resource, ResourceTypeCache resourceTypeCache) {
  final typeIri = resourceTypeCache.getIri(resource.type);
  final indices = resource.indices
      .map((index) => _toCrdtIndexGraphConfig(resource, index))
      .toList();

  return ResourceConfigData(
    typeIri: typeIri,
    crdtMapping: resource.crdtMapping,
    indices: indices,
  );
}

SyncEngineConfig toSyncEngineConfig(
    LocordaConfig config, ResourceTypeCache resourceTypeCache) {
  final resources = config.resources
      .map((resource) => _toResourceGraphConfig(resource, resourceTypeCache))
      .toList();

  return SyncEngineConfig(resources: resources);
}
