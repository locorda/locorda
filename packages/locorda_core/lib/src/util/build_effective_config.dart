import 'package:locorda_core/locorda_core.dart';

class IndexNames {
  static const fullIndices = "lcrd-full-indices";
  static const installations = "lcrd-installation-index";
  static const groupIndexTemplates = "lcrd-group-index-templates";
}

/// The index item configuration for the index of indices.
final indexIndexItemConfig = IndexItemData({IdxFullIndex.indexesClass});

SyncEngineConfig buildEffectiveConfig(SyncEngineConfig config) {
  // Automatically add configuration for Framework-Owned resources
  final intermediateConfig = config.withResourcesAdded([
    ResourceConfigData(
      typeIri: CrdtClientInstallation.classIri,
      crdtMapping: Uri.parse(
          'https://w3id.org/solid-crdt-sync/mappings/client-installation-v1'),
      indices: [
        FullIndexData(
            localName: IndexNames.installations,
            itemFetchPolicy: ItemFetchPolicy.onRequest)
      ],
    ),
    ResourceConfigData(
        typeIri: IdxShard.classIri,
        crdtMapping:
            Uri.parse('https://w3id.org/solid-crdt-sync/mappings/shard-v1'),
        // No indices for shards
        indices: []),
    ResourceConfigData(
        typeIri: IdxGroupIndex.classIri,
        crdtMapping:
            Uri.parse('https://w3id.org/solid-crdt-sync/mappings/index-v1'),
        // No indices for indices
        indices: []),
  ]);

  final allResourceIris = intermediateConfig.resources
      .map((r) => r.typeIri)
      .toSet()
    ..addAll({IdxFullIndex.classIri, IdxGroupIndexTemplate.classIri});

  final effectiveConfig = intermediateConfig.withResourcesAdded([
    ResourceConfigData(
        typeIri: IdxFullIndex.classIri,
        crdtMapping:
            Uri.parse('https://w3id.org/solid-crdt-sync/mappings/index-v1'),
        // No indices for indices
        indices: [
          FullIndexData(
              localName: IndexNames.fullIndices,
              item: indexIndexItemConfig,
              // We want to sync all indices of all resource types we handle,
              // but not the others which we do not know anything about
              itemFetchPolicy: ItemFetchPolicy.prefetchFiltered(
                IdxFullIndex.indexesClass,
                allResourceIris,
              ))
        ]),
    ResourceConfigData(
        typeIri: IdxGroupIndexTemplate.classIri,
        crdtMapping:
            Uri.parse('https://w3id.org/solid-crdt-sync/mappings/index-v1'),
        // No indices for indices
        indices: [
          FullIndexData(
              localName: IndexNames.groupIndexTemplates,
              item: indexIndexItemConfig,
              // We want to sync all indices of all resource types we handle,
              // but not the others which we do not know anything about
              itemFetchPolicy: ItemFetchPolicy.prefetchFiltered(
                IdxGroupIndexTemplate.indexesClass,
                allResourceIris,
              ))
        ]),
  ]);
  return effectiveConfig;
}
