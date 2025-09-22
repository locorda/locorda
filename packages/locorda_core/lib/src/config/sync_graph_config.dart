import 'package:locorda_core/src/config/sync_config_base.dart';
import 'package:locorda_core/src/index/index_config_base.dart';
import 'package:rdf_core/rdf_core.dart';

class IndexItemGraphConfig extends IndexItemConfigBase {
  const IndexItemGraphConfig(super.properties);
}

sealed class CrdtIndexGraphConfig extends CrdtIndexConfigBase {
  IndexItemGraphConfig? get item;
}

class FullIndexGraphConfig extends FullIndexConfigBase
    implements CrdtIndexGraphConfig {
  final IndexItemGraphConfig? item;
  const FullIndexGraphConfig({
    required super.localName,
    this.item,
    super.itemFetchPolicy = ItemFetchPolicy.prefetch,
  }) : super(item: item);
}

class GroupIndexGraphConfig extends GroupIndexConfigBase
    implements CrdtIndexGraphConfig {
  final IndexItemGraphConfig? item;

  const GroupIndexGraphConfig({
    required super.localName,
    this.item,
    super.groupingProperties = const [],
  }) : super(item: item);
}

class ResourceGraphConfig extends ResourceConfigBase {
  final List<CrdtIndexGraphConfig> indices;

  final IriTerm typeIri;
  ResourceGraphConfig({
    required this.typeIri,
    required super.crdtMapping,
    required this.indices,
  }) : super(indices: indices);
}

class SyncGraphConfig extends SyncConfigBase {
  final List<ResourceGraphConfig> resources;

  SyncGraphConfig({required this.resources}) : super(resources: resources);

  ResourceGraphConfig getResourceConfig(IriTerm type) {
    return resources.firstWhere((r) => r.typeIri == type);
  }
}
