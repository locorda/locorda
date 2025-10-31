# locorda_solid_auth_worker

Solid authentication integration for Locorda's worker architecture.

## Overview

This package bridges Solid authentication between main thread and worker isolate/thread. It synchronizes authentication state and credentials from the main thread's `SolidAuth` to the worker, where they're used for authenticated HTTP requests.

## Architecture

### Main Thread: SolidAuthConnector

The `SolidAuthConnector` runs on the main thread and:
- Listens to `SolidAuth.isAuthenticatedNotifier` for state changes
- Extracts DPoP credentials and WebID when authenticated
- Sends `UpdateAuthMessage` to worker via `WorkerChannel`
- Clears credentials in worker when logged out

### Worker Thread: WorkerSolidAuthProvider

The `WorkerSolidAuthProvider` runs in the worker and:
- Receives authentication updates via `WorkerChannel`
- Implements `SolidAuthProvider` interface for `SolidBackend`
- Generates DPoP tokens locally using transmitted credentials
- Provides `isAuthenticatedNotifier` to trigger backend initialization

## Usage

### Main Thread Setup

```dart
import 'package:solid_auth/solid_auth.dart';
import 'package:locorda/locorda.dart';
import 'package:locorda_solid_auth_worker/locorda_solid_auth_worker.dart';

// Initialize SolidAuth
final solidAuth = SolidAuth(...);
await solidAuth.init();

// Setup Locorda with worker and SolidAuthConnector plugin
final sync = await Locorda.createWithWorker(
  engineParamsFactory: createEngineParams,
  jsScript: 'worker.dart.js',
  plugins: [
    SolidAuthConnector.responder(solidAuth),
  ],
  // ... other config
);
```

### Worker Thread Setup

```dart
import 'package:locorda_worker/locorda_worker.dart';
import 'package:locorda_solid_auth_worker/locorda_solid_auth_worker.dart';
import 'package:locorda_solid/locorda_solid.dart';

Future<EngineParams> createEngineParams(
  SyncEngineConfig config,
  WorkerContext context,
) async {
  // Create auth provider from worker context
  final authProvider = SolidAuthConnector.requester(context);
  
  // Use in SolidBackend
  final backend = SolidBackend(auth: authProvider);
  
  // Backend automatically initializes remotes when authenticated
  
  // ... create storage and return EngineParams
  return EngineParams(
    storage: storage,
    backends: [backend],
  );
}
```

## How It Works

1. **Login on Main Thread**: User logs in via `SolidAuth.login()`
2. **State Change Detected**: `SolidAuthConnector` receives notification via `isAuthenticatedNotifier`
3. **Credentials Extracted**: DPoP credentials and WebID extracted from `SolidAuth`
4. **Message Sent**: `UpdateAuthMessage` sent to worker via channel
5. **Worker Updated**: `WorkerSolidAuthProvider` updates internal state
6. **Listeners Notified**: `isAuthenticatedNotifier` in worker notifies `SolidBackend`
7. **Backend Initializes**: `SolidBackend` creates `SolidRemoteStorage` with WebID

## Key Features

- **Automatic Synchronization**: Auth state changes propagate automatically from main to worker
- **Local DPoP Generation**: DPoP tokens generated in worker where HTTP requests happen
- **Minimal Serialization**: Only credentials transmitted once, tokens generated per-request
- **Clean Lifecycle**: Proper setup/teardown via `WorkerPlugin` interface
- **Type-Safe Messages**: Structured `UpdateAuthMessage` instead of raw maps

## See Also

- `locorda_worker` - Core worker infrastructure
- `locorda_solid` - Solid backend implementation
- `solid_auth` - Main thread authentication