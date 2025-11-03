/// Worker entry point for Personal Notes App.
///
/// This file runs in a separate isolate/web worker and handles:
/// - Database operations (DriftStorage)
/// - CRDT synchronization
/// - Solid Pod communication
/// - All heavy computation
///
/// The main thread only handles UI and communicates via messages.
library;

import 'package:locorda/worker.dart';
import 'package:locorda_core/locorda_core.dart';
import 'package:locorda_drift/locorda_drift.dart';
import 'package:locorda_solid/locorda_solid.dart';
import 'package:locorda_solid_auth_worker/worker.dart';
import 'package:locorda_worker/locorda_worker.dart';
import 'package:personal_notes_app/utils/logging_setup.dart';

/// Worker entry point for web workers.
///
/// On web, the compiled JS is loaded and main() is called automatically.
void main() {
  print('Personal Notes App Worker starting... 4');
  workerMain(createEngineParams, workerInitializer: setupWorkerLogging);
}

/// Factory function that creates and configures the SyncEngine in the worker.
///
/// This function is passed to `workerMain()` and called by the framework during
/// the worker setup process after receiving configuration from the main thread.
///
/// Framework provides:
/// - [config]: SyncEngineConfig (already converted from LocordaConfig by main thread)
/// - [context]: WorkerContext with communication channel for cross-thread operations
///
/// App creates:
/// - Storage (DriftStorage with platform-specific options)
/// - Backends (SolidBackend with WorkerSolidAuthProvider)
///
/// Returns configured SyncEngine instance that will handle all sync operations.
Future<EngineParams> createEngineParams(
  SyncEngineConfig config,
  WorkerContext context,
) async =>
    EngineParams(
      storage: await DriftStorage.create(
        web: LocordaDriftWebOptions(
          sqlite3Wasm: Uri.parse('sqlite3.wasm'),
          driftWorker: Uri.parse('drift_worker.js'),
        ),
        native: await DriftNativeOptionsConnector.receiver(context),
      ),
      backends: [
        // Create auth provider that communicates with main thread
        // This receives credentials from main thread and generates DPoP tokens locally
        SolidBackend(auth: SolidAuthConnector.receiver(context)),
      ],
    );
