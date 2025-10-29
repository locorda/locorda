/// Main-thread bridge for Solid authentication in worker architecture.
///
/// Synchronizes authentication state from main thread to worker isolate.
library;

import 'package:locorda_solid_auth_worker/locorda_solid_auth_worker.dart';
import 'package:locorda_worker/locorda_worker.dart';
import 'package:locorda_solid/src/auth/solid_auth_provider.dart';
import 'package:solid_auth/solid_auth.dart';

/// Worker plugin that bridges Solid authentication from main thread to worker.
///
/// This connector:
/// 1. Listens to [SolidAuth.isAuthenticatedNotifier] for state changes
/// 2. Extracts DPoP credentials and WebID when authenticated
/// 3. Sends [UpdateAuthMessage] to worker via [WorkerChannel]
/// 4. Clears credentials in worker when logged out
///
/// The worker's [WorkerSolidAuthProvider] receives these messages and provides
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
///   syncEngineFactory: createSyncEngine,
///   jsScript: 'worker.dart.js',
///   plugins: [
///     SolidAuthConnector.plugin(solidAuth),
///   ],
///   // ... other config
/// );
/// ```
///
/// In worker, create the SyncEngine instance:
///
/// ```dart
/// Future<SyncEngine> createSyncEngine(
///   SyncEngineConfig config,
///   WorkerContext context,
/// ) async {
///   final authProvider = SolidAuthConnector.provider(context);
///   final backend = SolidBackend(auth: authProvider);
///   // ... create storage and return SyncEngine
/// }
/// ```
class SolidAuthConnector implements WorkerPlugin {
  final SolidAuth _solidAuth;
  final LocordaWorkerHandle _workerHandle;

  SolidAuthConnector._({
    required SolidAuth solidAuth,
    required LocordaWorkerHandle workerHandle,
  })  : _solidAuth = solidAuth,
        _workerHandle = workerHandle;

  /// Creates a plugin factory for this connector.
  ///
  /// Pass the main thread's [solidAuth] instance. The returned factory will be
  /// called by the worker framework with the [LocordaWorkerHandle].
  static WorkerPluginFactory plugin(SolidAuth solidAuth) {
    return (LocordaWorkerHandle workerHandle) {
      return SolidAuthConnector._(
        solidAuth: solidAuth,
        workerHandle: workerHandle,
      );
    };
  }

  /// Starts listening to auth state changes and forwards them to worker.
  ///
  /// Sends current auth state immediately, then subscribes to future changes.
  @override
  Future<void> initialize() async {
    // Send current state immediately
    await _sendCurrentState();

    // Listen for future changes via isAuthenticatedNotifier
    _solidAuth.isAuthenticatedNotifier.addListener(_handleAuthStateChange);
  }

  /// Sends current auth state to worker.
  Future<void> _sendCurrentState() async {
    await _handleAuthStateChange();
  }

  /// Handles auth state change by sending credentials to worker.
  ///
  /// When authenticated, sends DPoP credentials and WebID.
  /// When logged out, sends null credentials to clear worker state.
  Future<void> _handleAuthStateChange() async {
    // Only send credentials when authenticated
    if (!_solidAuth.isAuthenticated || _solidAuth.currentWebId == null) {
      // Send empty credentials to clear worker auth
      _workerHandle.sendMessage({
        '__channel': UpdateAuthMessage(credentials: null).toJson(),
      });
      return;
    }

    final dpopCredentials = _solidAuth.exportDpopCredentials();
    final webId = _solidAuth.currentWebId;
    _workerHandle.sendMessage({
      '__channel': UpdateAuthMessage(
        credentials: dpopCredentials,
        webId: webId,
      ).toJson(),
    });
  }

  /// Stops listening and cleans up resources.
  @override
  Future<void> dispose() async {
    _solidAuth.isAuthenticatedNotifier.removeListener(_handleAuthStateChange);
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
  ///     final authProvider = SolidAuthConnector.provider(context);
  ///     final backend = SolidBackend(auth: authProvider);
  ///   });
  /// }
  /// ```
  static SolidAuthProvider provider(WorkerContext context) {
    return WorkerSolidAuthProvider(context.channel);
  }
}
