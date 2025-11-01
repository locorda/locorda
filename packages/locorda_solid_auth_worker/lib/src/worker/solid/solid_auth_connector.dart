/// Main-thread bridge for Solid authentication in worker architecture.
///
/// Synchronizes authentication state from main thread to worker isolate.
library;

import 'dart:async';

import 'package:locorda_solid/src/auth/solid_auth_provider.dart';
import 'package:locorda_solid_auth_worker/locorda_solid_auth_worker.dart';
import 'package:locorda_worker/locorda_worker.dart';
import 'package:logging/logging.dart';
import 'package:solid_auth/solid_auth.dart';

final _log = Logger('SolidAuthConnector');

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
class SolidAuthConnector implements WorkerPlugin {
  final SolidAuth _solidAuth;
  final LocordaWorker _workerHandle;
  StreamSubscription? _tokenChangedSubscription;

  SolidAuthConnector._({
    required SolidAuth solidAuth,
    required LocordaWorker workerHandle,
  })  : _solidAuth = solidAuth,
        _workerHandle = workerHandle;

  /// Creates a plugin factory for this connector.
  ///
  /// Pass the main thread's [solidAuth] instance. The returned factory will be
  /// called by the worker framework with the [LocordaWorker].
  static WorkerPluginFactory sender(SolidAuth solidAuth) {
    return (LocordaWorker workerHandle) {
      return SolidAuthConnector._(
        solidAuth: solidAuth,
        workerHandle: workerHandle,
      );
    };
  }

  /// Listens for auth state requests from worker and responds with current state.
  ///
  /// Also subscribes to future auth state changes and pushes updates to worker.
  /// Uses Request/Response pattern for initial state to avoid race conditions.
  ///
  /// ## Token Refresh Strategy
  ///
  /// **Reactive (Primary)**: Worker requests refresh on-demand
  ///    - Used when worker detects expired token (e.g., 401 error)
  ///    - Provides immediate recovery from token expiry
  ///    - No background timers - mobile-friendly
  ///
  /// **Proactive (Future)**: Listen to `solid_auth` token changed stream
  ///    - Once our fork exposes `onTokenChanged` stream
  ///    - Event-driven - no polling, no timers
  ///    - Instant propagation when `solid_auth` refreshes internally
  @override
  Future<void> initialize() async {
    _log.info('Plugin initialized, listening for requests...');

    // Listen for messages from worker (both state requests and refresh requests)
    _workerHandle.messages.listen((message) async {
      if (message is! Map<String, dynamic>) return;

      // Only process __channel messages
      if (message['__channel'] != true) return;

      final channelData = message['data'];
      _log.fine(
          'Received __channel message: ${channelData is Map ? channelData['type'] : channelData.runtimeType}');

      if (channelData is! Map<String, dynamic>) return;

      switch (channelData['type']) {
        case 'RequestAuthState':
          _log.info('Processing RequestAuthState...');
          await _sendCurrentState();
          _log.info('Auth state sent');

        case 'RequestTokenRefresh':
          final requestId = channelData['requestId'] as int?;
          final reason = channelData['reason'] as String?;
          _log.info(
            'Processing RequestTokenRefresh (id=$requestId, reason=$reason)...',
          );
          await _handleTokenRefreshRequest(requestId);
      }
    });

    // Listen for auth state changes and push updates immediately
    _solidAuth.isAuthenticatedNotifier.addListener(_handleAuthStateChange);
    _log.info('Subscribed to auth state changes');

    // TODO: Enable once solid_auth fork exposes onTokenChanged stream
    // Event-driven proactive refresh - no timers needed
    // _tokenChangedSubscription = _solidAuth.onTokenChanged?.listen((_) {
    //   _log.fine('Token changed event - pushing to worker');
    //   _sendCurrentState();
    // });
  }

  /// Handles token refresh request from worker.
  ///
  /// Responds with fresh credentials by re-exporting from [SolidAuth].
  /// The [SolidAuth] automatically handles token refresh internally.
  Future<void> _handleTokenRefreshRequest(int? requestId) async {
    if (requestId == null) {
      _log.warning('Token refresh request missing requestId - ignoring');
      return;
    }

    if (!_solidAuth.isAuthenticated) {
      _log.warning('Token refresh requested but not authenticated');
      _workerHandle.sendMessage({
        '__channel': true,
        'data': {
          'type': 'TokenRefreshResponse',
          'requestId': requestId,
          'credentials': null,
        },
      });
      return;
    }

    // solid_auth handles token refresh internally when we export
    final dpopCredentials = _solidAuth.exportDpopCredentials();
    final webId = _solidAuth.currentWebId;

    _workerHandle.sendMessage({
      '__channel': true,
      'data': {
        'type': 'TokenRefreshResponse',
        'requestId': requestId,
        'credentials': dpopCredentials.toJson(),
        'webId': webId,
      },
    });
    _log.info('Sent token refresh response (id=$requestId)');
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
        '__channel': true,
        'data': UpdateAuthMessage(credentials: null).toJson(),
      });
      return;
    }

    final dpopCredentials = _solidAuth.exportDpopCredentials();
    final webId = _solidAuth.currentWebId;
    _workerHandle.sendMessage({
      '__channel': true,
      'data': UpdateAuthMessage(
        credentials: dpopCredentials,
        webId: webId,
      ).toJson(),
    });
  }

  /// Stops listening and cleans up resources.
  @override
  Future<void> dispose() async {
    _solidAuth.isAuthenticatedNotifier.removeListener(_handleAuthStateChange);
    await _tokenChangedSubscription?.cancel();
    _log.info('Disposed - stopped listeners');
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
    return WorkerSolidAuthProvider(context.channel);
  }
}
