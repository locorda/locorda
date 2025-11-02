/// Main-thread bridge for Solid authentication in worker architecture.
///
/// Synchronizes authentication state from main thread to worker isolate.
library;

import 'package:locorda_solid/src/auth/solid_auth_provider.dart';
import 'package:locorda_solid_auth_worker/locorda_solid_auth_worker.dart';
import 'package:locorda_solid_auth_worker/src/worker/solid/solid_auth_sender.dart';
import 'package:locorda_worker/locorda_worker.dart';
import 'package:solid_auth/solid_auth.dart';

/// Worker plugin that bridges Solid authentication from main thread to worker.
///
/// This connector:
/// 1. Listens to [SolidAuth.isAuthenticatedNotifier] for state changes
/// 2. Extracts DPoP credentials and WebID when authenticated
/// 3. Sends [UpdateAuthMessage] to worker via [WorkerChannel]
/// 4. Clears credentials in worker when logged out
///
/// The worker's [SolidAuthReceiver] receives these messages and provides
/// authentication for [SolidBackend] HTTP requests.
///
/// ## Usage
///
/// Register as plugin during sync system setup:
///
/// ```dart
/// final solidAuth = SolidAuth(...);
/// await solidAuth.init();
///
/// final sync = await Locorda.createWithWorker(
///   engineParamsFactory: createEngineParams,
///   jsScript: 'worker.dart.js',
///   plugins: [
///     SolidAuthConnector.sender(solidAuth),
///   ],
///   // ... other config
/// );
/// ```
///
/// In worker, create the SyncEngine instance:
///
/// ```dart
/// Future<SyncEngine> createEngineParams(
///   SyncEngineConfig config,
///   WorkerContext context,
/// ) async {
///   final authProvider = SolidAuthConnector.receiver(context);
///   final backend = SolidBackend(auth: authProvider);
///   // ... create storage and return SyncEngine
/// }
/// ```
class SolidAuthConnector {
  /// Creates a plugin factory for this connector.
  ///
  /// Pass the main thread's [solidAuth] instance. The returned factory will be
  /// called by the worker framework with the [LocordaWorker].
  static WorkerPluginFactory sender(SolidAuth solidAuth) {
    return (LocordaWorker workerHandle) {
      return SolidAuthSender(
        solidAuth: solidAuth,
        workerHandle: workerHandle,
      );
    };
  }

  /// Creates auth provider for worker context.
  ///
  /// Call this in the worker entry point to create a [SolidAuthProvider]
  /// that receives credentials from the main thread and generates DPoP tokens
  /// locally for HTTP requests.
  ///
  /// Example:
  /// ```dart
  /// void workerEntryPoint() {
  ///   startWorkerIsolate((context) async {
  ///     final authProvider = SolidAuthConnector.receiver(context);
  ///     final backend = SolidBackend(auth: authProvider);
  ///   });
  /// }
  /// ```
  static SolidAuthProvider receiver(WorkerContext context) {
    return SolidAuthReceiver(context.channel);
  }
}
