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

// Main API facade
export 'src/locorda_graph_sync.dart'
    show
        LocordaGraphSync,
        IdentifiedGraph,
        PhysicalTimestampFactory,
        LogicalClockFactory,
        InstallationIdFactory;

export 'src/hydration_result.dart' show HydrationResult, HydrationSubscription;

// Core interfaces
export 'src/auth/auth_interface.dart' show Auth;

export 'src/storage/storage_interface.dart'
    show Storage, StoredDocument, DocumentMetadata, PropertyChange;

export 'src/backend/backend.dart' show Backend;

export 'src/mapping/resource_locator.dart' show ResourceLocator;

export 'src/storage/remote_storage.dart' show RemoteStorage;

// CRDT implementations
export 'src/crdt/crdt_types.dart'
    show CrdtType, LwwRegister, FwwRegister, OrSet;

export 'src/crdt/hybrid_logical_clock.dart'
    show HybridLogicalClock, HlcTimestamp;

// NOTE: CRDT annotations have been moved to locorda_annotations package
// Use that package for @CrdtLwwRegister, @CrdtOrSet, etc. annotations

// Sync engine
export 'src/sync/sync_engine.dart' show SyncEngine;

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

export 'src/mapping/pod_iri_config.dart' show PodIriConfig;

// Vocabularies
export 'src/vocabulary/idx_vocab.dart' show IdxVocab;
