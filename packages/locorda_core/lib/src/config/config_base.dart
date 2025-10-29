/// Resource-focused configuration for CRDT sync setup.
///
/// This provides a resource-centric API where all configuration flows from
/// "what resources am I working with?" rather than separate configuration
/// of indices, mappings, and paths.
library;

import 'package:locorda_core/src/index/index_config_base.dart';
import 'package:locorda_core/src/sync/sync_manager.dart';

/// Configuration for a single resource type in the sync system.
///
/// Organizes all resource-specific configuration in one place:
/// - Default storage paths on the Pod
/// - CRDT mapping information
/// - Index configurations for this resource
class ResourceConfigBase {
  /// Uri to the CRDT mapping file for this resource type.
  final Uri crdtMapping;

  /// Index configurations for this resource type.
  /// Can include multiple indices (e.g., by category, by date, full index).
  final List<CrdtIndexConfigBase> indices;

  const ResourceConfigBase({
    required this.crdtMapping,
    required this.indices,
  });
}

/// Configuration for the entire sync system organized by resources.
class ConfigBase {
  /// All resource configurations for the application.
  final List<ResourceConfigBase> resources;

  /// Configuration for automatic synchronization behavior.
  final AutoSyncConfig autoSyncConfig;

  const ConfigBase({
    required this.resources,
    this.autoSyncConfig = const AutoSyncConfig.disabled(),
  });

  /// Get all index configurations across all resources.
  List<CrdtIndexConfigBase> getAllIndices() {
    return resources.expand((resource) => resource.indices).toList();
  }
}
