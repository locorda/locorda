import 'package:locorda_core/locorda_core.dart';
import 'package:locorda_core/src/generated/crdt/index.dart';
import 'package:locorda_core/src/generated/idx/index.dart';

SyncGraphConfig buildEffectiveConfig(SyncGraphConfig config) {
  // Automatically add configuration for Framework-Owned resources
  final intermediateConfig = config.withResourcesAdded([
    ResourceGraphConfig(
      typeIri: CrdtClientInstallation.classIri,
      crdtMapping: Uri.parse(
          'https://w3id.org/solid-crdt-sync/mappings/client-installation-v1'),
      indices: [
        FullIndexGraphConfig(
            localName: 'lcrd-installation-index',
            itemFetchPolicy: ItemFetchPolicy.onRequest)
      ],
    ),
    ResourceGraphConfig(
        typeIri: IdxShard.classIri,
        crdtMapping:
            Uri.parse('https://w3id.org/solid-crdt-sync/mappings/shard-v1'),
        // No indices for shards
        indices: []),
    ResourceGraphConfig(
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
    ResourceGraphConfig(
        typeIri: IdxFullIndex.classIri,
        crdtMapping:
            Uri.parse('https://w3id.org/solid-crdt-sync/mappings/index-v1'),
        // No indices for indices
        indices: [
          FullIndexGraphConfig(
              localName: "lcrd-full-indices",
              item: IndexItemGraphConfig({IdxFullIndex.indexesClass}),
              // We want to sync all indices of all resource types we handle,
              // but not the others which we do not know anything about
              itemFetchPolicy: ItemFetchPolicy.prefetchFiltered(
                IdxFullIndex.indexesClass,
                allResourceIris,
              ))
        ]),
    ResourceGraphConfig(
        typeIri: IdxGroupIndexTemplate.classIri,
        crdtMapping:
            Uri.parse('https://w3id.org/solid-crdt-sync/mappings/index-v1'),
        // No indices for indices
        indices: [
          FullIndexGraphConfig(
              localName: "lcrd-group-index-templates",
              item: IndexItemGraphConfig({IdxFullIndex.indexesClass}),
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
