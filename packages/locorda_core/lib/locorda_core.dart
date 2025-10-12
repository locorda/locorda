/// Core CRDT synchronization logic for Solid Pods.
///
/// This library provides the platform-agnostic core functionality for
/// syncing RDF data to Solid Pods using CRDT (Conflict-free Replicated Data Types).
///
/// The library follows a 4-layer architecture:
/// 1. Data Resource Layer - Individual RDF resources
/// 2. Merge Contract Layer - CRDT merge behavior rules
/// 3. Indexing Layer - Performance optimization via indices
/// 4. Sync Strategy Layer - Client-side sync strategies
library locorda_core;

// Core interfaces
export 'src/auth/auth_interface.dart' show Auth;
export 'src/backend/backend.dart' show Backend;
// Resource-focused configuration
export 'src/config/sync_config_base.dart'
    show ResourceConfigBase, SyncConfigBase;
export 'src/config/sync_config_base_validator.dart'
    show SyncConfigBaseValidator;
export 'src/config/sync_graph_config.dart'
    show
        IndexItemGraphConfig,
        CrdtIndexGraphConfig,
        FullIndexGraphConfig,
        GroupIndexGraphConfig,
        ResourceGraphConfig,
        SyncGraphConfig;
export 'src/config/sync_graph_config_validator.dart'
    show SyncGraphConfigValidator;
export 'src/config/validation.dart'
    show
        ValidationResult,
        ValidationIssue,
        ValidationError,
        ValidationWarning,
        SyncConfigValidationException;
// CRDT implementations
export 'src/crdt/crdt_types.dart'
    show CrdtType, LwwRegister, FwwRegister, OrSet;
export 'src/crdt/hybrid_logical_clock.dart'
    show HybridLogicalClock, HlcTimestamp;
// Vocabularies
export 'src/generated/_index.dart' show IdxShardEntry
    // TODO: what do we need to export here?
    /*
        ,Algo,
        IdxShard,
        Crdt,
        AlgoAlgorithm,
        AlgoFWW_Register,
        AlgoImmutable,
        AlgoLWW_Register,
        AlgoOR_Set,
        Algon2P_Set,
        CrdtClientInstallation,
        CrdtClockEntry,
        Idx,
        IdxFullIndex,
        IdxGroupIndex,
        IdxGroupIndexTemplate,
        IdxGroupingRule,
        IdxGroupingRuleProperty,
        IdxIndex,
        IdxIndexedProperty,
        IdxModuloHashSharding,
        IdxRegexTransform,
        IdxUniversalProperties,
        Mc,
        McClassMapping,
        McDocumentMapping,
        McMapping,
        McPredicateMapping,
        McRule,
        Solidsync,
        Sync,
        SyncManagedDocument,
        SyncResourceStatement,
        SyncUniversalProperties*/
    ;
export 'src/hydration_result.dart' show HydrationSubscription;
export 'src/locorda_graph_sync.dart' show HydrationBatch, IdentifiedGraph;
// Index configuration
export 'src/index/index_config_base.dart'
    show
        ItemFetchPolicy,
        IndexItemConfigBase,
        CrdtIndexConfigBase,
        GroupIndexConfigBase,
        FullIndexConfigBase,
        RegexTransform,
        GroupingProperty;
// Main API facade
export 'src/locorda_graph_sync.dart' show LocordaGraphSync, IdentifiedGraph;
export 'src/mapping/root_iri_config.dart' show RootIriConfig;
export 'src/mapping/resource_locator.dart'
    show ResourceLocator, LocalResourceLocator, ResourceIdentifier;
export 'src/storage/remote_storage.dart' show RemoteStorage;
export 'src/storage/storage_interface.dart'
    show
        Storage,
        StoredDocument,
        DocumentMetadata,
        PropertyChange,
        SaveDocumentResult,
        DocumentsResult;
// NOTE: CRDT annotations have been moved to locorda_annotations package
// Use that package for @CrdtLwwRegister, @CrdtOrSet, etc. annotations

// Sync engine and manager
export 'src/sync/sync_engine.dart' show SyncEngine;
export 'src/sync/sync_manager.dart' show SyncManager, AutoSyncConfig;
export 'src/sync/sync_state.dart' show SyncState, SyncStatus;
