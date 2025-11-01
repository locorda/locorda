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

export 'src/backend/in_memory_backend.dart' show InMemoryBackend;
// Resource-focused configuration
export 'src/config/config_base.dart' show ResourceConfigBase, ConfigBase;
export 'src/config/config_base_validator.dart' show ConfigBaseValidator;
export 'src/config/sync_engine_config.dart'
    show
        IndexItemData,
        CrdtIndexData,
        FullIndexData,
        GroupIndexData,
        ResourceConfigData,
        SyncEngineConfig;
export 'src/config/sync_engine_config_validator.dart'
    show SyncEngineConfigValidator;
export 'src/config/validation.dart'
    show
        ValidationResult,
        ValidationIssue,
        ValidationError,
        ValidationWarning,
        SyncConfigValidationException;
// CRDT implementations
// TODO: why do we export these?
export 'src/crdt/crdt_types.dart' show CrdtType, LwwRegister, OrSet;
// Vocabularies
export 'src/generated/_index.dart'
    show
        IdxShardEntry,
        Algo,
        IdxShard,
        Crdt,
        AlgoAlgorithm,
        AlgoG_Register,
        AlgoImmutable,
        AlgoLWW_Register,
        AlgoOR_Set,
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
        SyncUniversalProperties;
export 'src/hydration_result.dart' show HydrationSubscription;
export 'src/sync_engine.dart' show HydrationBatch, IdentifiedGraph;
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
export 'src/sync_engine.dart' show SyncEngine, IdentifiedGraph;
export 'src/mapping/root_iri_config.dart' show RootIriConfig;
export 'src/mapping/resource_locator.dart'
    show
        ResourceLocator,
        LocalResourceLocator,
        ResourceIdentifier,
        UnsupportedIriException;
export 'src/mapping/iri_translator.dart'
    show IriTranslator, BaseIriTranslator, NoOpIriTranslator;
export 'src/storage/remote_id.dart' show RemoteId;
export 'src/storage/remote_storage.dart' show RemoteStorage;
export 'src/storage/storage_interface.dart'
    show
        Storage,
        StoredDocument,
        DocumentMetadata,
        PropertyChange,
        SaveDocumentResult,
        DocumentsResult;
export 'src/storage/concurrent_update_exception.dart'
    show ConcurrentUpdateException;
export 'src/storage/in_memory_storage.dart' show InMemoryStorage;

// NOTE: CRDT annotations have been moved to locorda_annotations package
// Use that package for @CrdtLwwRegister, @CrdtOrSet, etc. annotations

// Sync engine and manager
export 'src/sync_engine.dart' show SyncEngine, EngineParams;
export 'src/sync/sync_manager.dart' show SyncManager, AutoSyncConfig;
export 'src/sync/sync_state.dart' show SyncState, SyncStatus, SyncTrigger;
