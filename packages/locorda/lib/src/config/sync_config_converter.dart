import 'package:locorda/src/config/sync_config.dart';
import 'package:locorda/src/config/sync_config_util.dart';
import 'package:locorda_core/locorda_core.dart';

IndexItemGraphConfig? _toIndexItemGraphConfig(IndexItem? item) {
  if (item == null) return null;
  return IndexItemGraphConfig(item.properties);
}

FullIndexGraphConfig _toFullIndexGraphConfig(
        ResourceConfig parentConfig, FullIndex index) =>
    FullIndexGraphConfig(
      localName: getIndexName(parentConfig, index),
      item: _toIndexItemGraphConfig(index.item),
      itemFetchPolicy: index.itemFetchPolicy,
    );

GroupIndexGraphConfig _toGroupIndexGraphConfig(
        ResourceConfig parentConfig, GroupIndex index) =>
    GroupIndexGraphConfig(
      localName: getIndexName(parentConfig, index),
      item: _toIndexItemGraphConfig(index.item),
      groupingProperties: index.groupingProperties,
    );

CrdtIndexGraphConfig _toCrdtIndexGraphConfig(
    ResourceConfig parentConfig, CrdtIndex index) {
  if (index is FullIndex) {
    return _toFullIndexGraphConfig(parentConfig, index);
  } else if (index is GroupIndex) {
    return _toGroupIndexGraphConfig(parentConfig, index);
  } else {
    throw ArgumentError('Unknown index type: ${index.runtimeType}');
  }
}

ResourceGraphConfig _toResourceGraphConfig(
    ResourceConfig resource, ResourceTypeCache resourceTypeCache) {
  final typeIri = resourceTypeCache.getIri(resource.type);
  final indices = resource.indices
      .map((index) => _toCrdtIndexGraphConfig(resource, index))
      .toList();

  return ResourceGraphConfig(
    typeIri: typeIri,
    crdtMapping: resource.crdtMapping,
    indices: indices,
  );
}

SyncGraphConfig toSyncGraphConfig(
    SyncConfig config, ResourceTypeCache resourceTypeCache) {
  final resources = config.resources
      .map((resource) => _toResourceGraphConfig(resource, resourceTypeCache))
      .toList();

  return SyncGraphConfig(resources: resources);
}
