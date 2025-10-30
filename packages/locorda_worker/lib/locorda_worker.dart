/// Worker-based architecture for offloading heavy operations to isolate/worker.
///
/// Use this API to run SyncEngine in a separate thread, keeping the
/// main thread responsive for UI.
library;

export 'src/worker/worker_entry_point.dart' show workerMain, WorkerContext;
export 'src/worker/worker_channel.dart' show WorkerChannel;
export 'src/worker/worker_handle.dart'
    show LocordaWorkerHandle, EngineParamsFactory;
export 'src/worker/worker_plugin.dart' show WorkerPlugin, WorkerPluginFactory;
export 'src/worker/proxy_sync_engine.dart' show ProxySyncEngine;
