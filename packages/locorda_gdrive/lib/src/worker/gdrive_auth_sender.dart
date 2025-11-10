/// Main-thread sender for Google Drive authentication state.
///
/// Synchronizes authentication state from main thread to worker isolate.
library;

import 'package:locorda_gdrive/src/gdrive_auth.dart';
import 'package:locorda_gdrive/src/worker/gdrive_auth_messages.dart';
import 'package:locorda_worker/locorda_worker.dart';
import 'package:logging/logging.dart';

final _log = Logger('GDriveAuthSender');

/// Main-thread plugin that sends Google Drive auth updates to worker.
///
/// Listens to [GDriveAuth] authentication state changes and sends
/// credentials to the worker via [WorkerChannel].
class GDriveAuthSender implements WorkerPlugin {
  final GDriveAuth _authBridge;
  final LocordaWorker _workerHandle;

  GDriveAuthSender({
    required GDriveAuth authBridge,
    required LocordaWorker workerHandle,
  })  : _authBridge = authBridge,
        _workerHandle = workerHandle;

  @override
  Future<void> initialize() async {
    // Listen to auth state changes
    _authBridge.isAuthenticatedNotifier.addListener(_onAuthChanged);

    // Send initial auth state
    await _sendAuthUpdate();

    // Listen for requests from worker
    _workerHandle.messages
        .where((msg) => msg is Map<String, dynamic>)
        .cast<Map<String, dynamic>>()
        .listen(_handleWorkerMessage);
  }

  void _onAuthChanged() {
    _log.fine('Auth state changed, sending update to worker');
    _sendAuthUpdate();
  }

  Future<void> _sendAuthUpdate() async {
    try {
      final isAuth = await _authBridge.isAuthenticated();

      if (isAuth) {
        final accessToken = await _authBridge.getAccessToken();
        _workerHandle.sendMessage(UpdateAuthMessage(
          accessToken: accessToken,
          userEmail: _authBridge.userEmail,
          // TODO: Add token expiry time if available
        ).toJson());
      } else {
        _workerHandle.sendMessage(UpdateAuthMessage(
          accessToken: null,
          userEmail: null,
        ).toJson());
      }
    } catch (e, stackTrace) {
      _log.severe('Error sending auth update to worker', e, stackTrace);
    }
  }

  void _handleWorkerMessage(dynamic message) {
    if (message is! Map<String, dynamic>) return;

    final type = message['type'] as String?;
    switch (type) {
      case 'RequestAuthStateMessage':
        _log.fine('Worker requested auth state, sending update');
        _sendAuthUpdate();
      case 'TokenRefreshRequest':
        _handleTokenRefreshRequest(TokenRefreshRequest.fromJson(message));
    }
  }

  Future<void> _handleTokenRefreshRequest(TokenRefreshRequest request) async {
    _log.info('Worker requested token refresh: ${request.reason}');

    try {
      await _authBridge.refreshToken(reason: request.reason);
      final accessToken = await _authBridge.getAccessToken();

      _workerHandle.sendMessage(TokenRefreshResponse(
        requestId: request.requestId,
        accessToken: accessToken,
        // TODO: Add expiry time
      ).toJson());
    } catch (e, stackTrace) {
      _log.severe('Token refresh failed', e, stackTrace);
      _workerHandle.sendMessage(TokenRefreshResponse(
        requestId: request.requestId,
        error: e.toString(),
      ).toJson());
    }
  }

  @override
  Future<void> dispose() async {
    _authBridge.isAuthenticatedNotifier.removeListener(_onAuthChanged);
  }
}
