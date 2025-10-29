/// Worker-side Solid authentication provider.
///
/// Generates DPoP tokens locally in the worker using transmitted credentials.
/// This keeps DPoP key operations in the worker thread where HTTP requests happen.
library;

import 'package:locorda_solid_auth_worker/src/worker/solid/solid_auth_messages.dart';
import 'package:locorda_worker/locorda_worker.dart';
import 'package:locorda_solid/locorda_solid.dart';
import 'package:solid_auth/solid_auth.dart';

/// Notifier for worker authentication state changes.
///
/// Implements [AuthValueListenable] to allow [SolidBackend] and other
/// components to subscribe to authentication state changes in the worker.
/// Updates are triggered when [UpdateAuthMessage] is received from main thread.
class _WorkerAuthNotifier implements AuthValueListenable {
  final List<void Function()> _listeners = [];
  bool _isAuthenticated = false;

  @override
  bool get isAuthenticated => _isAuthenticated;

  set isAuthenticated(bool value) {
    if (_isAuthenticated != value) {
      _isAuthenticated = value;
      _notifyListeners();
    }
  }

  @override
  void addListener(void Function() listener) {
    _listeners.add(listener);
  }

  @override
  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  void _notifyListeners() {
    for (final listener in _listeners.toList()) {
      listener();
    }
  }
}

/// Solid authentication provider for worker isolate/thread.
///
/// Receives DPoP credentials from main thread via [WorkerChannel] and generates
/// DPoP tokens locally for each HTTP request. This architecture ensures:
///
/// - **Fresh tokens**: DPoP tokens generated immediately before each request
/// - **Security**: Private key operations stay in worker where HTTP happens
/// - **Performance**: No serialization overhead per request (credentials sent once)
/// - **State sync**: [isAuthenticatedNotifier] triggers backend initialization
///
/// ## Lifecycle
///
/// 1. Created via [SolidAuthConnector.provider] in worker entry point
/// 2. Listens to [WorkerChannel] for [UpdateAuthMessage]
/// 3. Updates internal [_credentials] and [_webId]
/// 4. Notifies listeners via [isAuthenticatedNotifier]
/// 5. [SolidBackend] reacts by initializing remote storage
///
/// ## Usage
///
/// ```dart
/// void workerEntryPoint() {
///   startWorkerIsolate((context) async {
///     final authProvider = SolidAuthConnector.provider(context);
///     final backend = SolidBackend(auth: authProvider);
///     // Backend now reacts to auth state changes automatically
///   });
/// }
/// ```
class WorkerSolidAuthProvider implements SolidAuthProvider {
  final WorkerChannel _channel;
  final _WorkerAuthNotifier _notifier = _WorkerAuthNotifier();
  DpopCredentials? _credentials;
  String? _webId;

  /// Creates provider that listens to [channel] for authentication updates.
  ///
  /// Automatically subscribes to [UpdateAuthMessage] on the channel.
  WorkerSolidAuthProvider(this._channel) {
    // Listen for auth updates on channel
    _channel.messages.listen((message) {
      if (message is Map<String, dynamic> &&
          message['type'] == 'UpdateAuthMessage') {
        final authMessage = UpdateAuthMessage.fromJson(message);
        _credentials = authMessage.credentials;
        _webId = authMessage.webId;
        _notifier.isAuthenticated = _credentials != null;
      }
    });
  }

  /// Generates DPoP token for authenticated HTTP request.
  ///
  /// Creates a fresh DPoP proof token bound to the [url] and [method].
  /// Throws [StateError] if not authenticated (no credentials available).
  @override
  Future<({String accessToken, String dPoP})> getDpopToken(
      String url, String method) async {
    if (_credentials == null) {
      throw StateError('No authentication credentials available in worker');
    }

    final dpop = _credentials!.generateDpopToken(url: url, method: method);
    return (
      accessToken: dpop.accessToken,
      dPoP: dpop.dpopToken,
    );
  }

  /// Current authenticated user's WebID.
  ///
  /// Returns `null` if not authenticated. Updated when [UpdateAuthMessage]
  /// is received from main thread.
  @override
  String? get currentWebId => _webId;

  /// Whether currently authenticated.
  ///
  /// Returns `true` if credentials are available, `false` otherwise.
  @override
  Future<bool> isAuthenticated() async => _credentials != null;

  /// Listenable for authentication state changes.
  ///
  /// [SolidBackend] subscribes to this to know when to initialize/clear remotes.
  /// Notifies listeners when [UpdateAuthMessage] updates credentials.
  @override
  AuthValueListenable get isAuthenticatedNotifier => _notifier;
}
