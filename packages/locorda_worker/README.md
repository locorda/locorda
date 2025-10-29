# locorda_worker

Worker infrastructure for Locorda - Platform-agnostic architecture for running heavy operations in separate isolate/worker thread.

## Overview

This package provides the core worker infrastructure used by Locorda to offload CPU and I/O-intensive operations (CRDT merging, database access, HTTP requests) to a separate thread, keeping the main thread responsive for UI.

**Key Features:**
- **Platform-agnostic**: Automatic detection - uses Dart Isolates on native, Web Workers on web
- **Type-safe messaging**: Structured request/response protocol with request correlation
- **Plugin system**: Extensible architecture for authentication bridges and custom functionality
- **Worker channel**: Bidirectional pub/sub for app-specific cross-thread communication

## Architecture

### Main Thread
- **Dart object layer** (`Locorda`) - Work with typed Dart objects (e.g., `Note`, `Category`)
- **RDF mapping** - Bidirectional conversion between Dart objects and RDF graphs
- Lightweight proxy (`ProxysyncEngine`)
- Serializes RDF graphs to Turtle for transmission
- Routes requests/responses by ID
- Manages plugins (e.g., auth bridges)

### Worker Thread
- Full `SyncEngine` instance
- **CRDT merge logic** - All conflict resolution happens here
- **Database (Drift/SQLite)** - All storage I/O
- **HTTP backends** (Solid, etc.) - All network requests
- **DPoP token generation** - Cryptographic operations

### Communication
- **Framework messages**: Save/delete documents, hydration streams, sync triggers
- **Worker channel**: App-specific messages (auth updates, custom commands)

## Usage

### Step 1: Define Your SyncEngine Factory (Required)

Every application needs a **top-level** SyncEngine factory function that creates the complete CRDT sync engine (`SyncEngine`) in the worker thread. This engine handles all RDF-level operations: CRDT merging, conflict resolution, storage persistence, remote synchronization, and data hydration.

> ⚠️ **Important**: The factory function **must be a top-level function** (not a method, not a closure). This is required for cross-isolate function passing on native platforms.

```dart
// lib/worker.dart
import 'package:locorda_worker/locorda_worker.dart';
import 'package:locorda_core/locorda_core.dart';

void main() {
  workerMain(createSyncEngine);
}

// This MUST be a top-level function
Future<SyncEngine> createSyncEngine(
  SyncEngineConfig config,
  WorkerContext context,
) async {
  // Set up storage (runs in worker)
  final storage = DriftStorage(...);
  
  // Set up backends (HTTP happens in worker)
  final backends = [SolidBackend(...)];
  
  return SyncEngine.create(
    storage: storage,
    backends: backends,
    config: config,
  );
}
```

### Step 2: Use High-Level API (Recommended)

Most users should use the high-level `Locorda` API from the `locorda` package:

```dart
import 'package:locorda/locorda.dart';
import 'worker.dart' show createSyncEngine;

final sync = await Locorda.createWithWorker(
  syncEngineFactory: createSyncEngine,
  jsScript: 'worker.dart.js',
  plugins: [...],
  config: LocordaConfig(...),
);
```

### Step 2 Alternative: Direct Worker Handle Usage (Advanced)

Use this approach if you:
- Want to work directly with **RDF graphs** instead of typed Dart classes (no mapping layer)
- Need fine-grained control over worker lifecycle

```dart
import 'package:locorda_worker/locorda_worker.dart';
import 'worker.dart' show createSyncEngine;

// Create worker handle
final workerHandle = await LocordaWorkerHandle.create(
  syncEngineFactory: createSyncEngine,
  jsScript: 'worker.dart.js', // For web: dart compile js lib/worker.dart
  debugName: 'locorda-worker',
);

// Create proxy for main thread
final syncEngine = await ProxysyncEngine.create(
  workerHandle: workerHandle,
  config: syncEngineConfig,
);

// Work directly with RDF graphs (no Dart object mapping)
final rdfGraph = RdfGraph();
// ... build your RDF graph manually
await syncEngine.save(rdfGraph);
```

## Worker Plugins

Plugins extend worker functionality from the main thread. Common use case: authentication bridges.

```dart
class MyAuthPlugin implements WorkerPlugin {
  final MyAuth _auth;
  final LocordaWorkerHandle _worker;
  
  MyAuthPlugin(this._auth, this._worker);
  
  @override
  Future<void> initialize() async {
    // Forward auth state changes to worker
    _auth.onStateChange.listen((state) {
      _worker.sendMessage({
        '__channel': {'type': 'auth', 'credentials': state.toJson()},
      });
    });
  }
  
  @override
  Future<void> dispose() async {
    // Clean up
  }
}

// Register plugin
final workerHandle = await LocordaWorkerHandle.create(
  syncEngineFactory: createSyncEngine,
  jsScript: 'worker.dart.js',
);

// Initialize plugin manually (or use Locorda.createWithWorker which does this)
final plugin = MyAuthPlugin(auth, workerHandle);
await plugin.initialize();
```

## Worker Channel

For custom app-specific communication beyond framework operations:

### Main Thread
```dart
final channel = WorkerChannel((msg) => workerHandle.sendMessage({'__channel': msg}));

// Send custom message
channel.send({'action': 'customCommand', 'data': {...}});

// Receive responses
channel.messages.listen((msg) {
  print('Worker says: $msg');
});
```

### Worker Thread
```dart
Future<SyncEngine> createSyncEngine(
  SyncEngineConfig config,
  WorkerContext context,
) async {
  // Access channel from context
  context.channel.messages.listen((msg) {
    if (msg['action'] == 'customCommand') {
      // Handle command
      context.channel.send({'result': 'done'});
    }
  });
  
  // ... setup and return SyncEngine
}
```

## Web Platform Notes

For web, compile your worker to JavaScript:

```bash
dart compile js lib/worker.dart -o web/worker.dart.js
```

Then reference it in `LocordaWorkerHandle.create(jsScript: 'worker.dart.js')`.

## See Also

- `locorda` - High-level API (recommended entry point)
- `locorda_solid_auth_worker` - Solid authentication bridge plugin
- `locorda_core` - Core sync engine (runs in worker)
