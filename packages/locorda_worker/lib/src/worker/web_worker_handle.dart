import 'dart:async';
import 'dart:js_interop';

import 'package:locorda_core/locorda_core.dart';
import 'package:web/web.dart' as web;

import 'locorda_worker.dart';

/// Web platform implementation using Web Workers (modern web API).
class WebWorkerHandle implements LocordaWorker {
  final web.Worker _worker;
  final StreamController<Object?> _controller = StreamController.broadcast();

  WebWorkerHandle._(this._worker);

  /// Creates worker with plugin support.
  ///
  /// Execution order guarantees plugins are ready before worker starts:
  /// 1. Spawn web worker (creates communication channel)
  /// 2. Caller initializes plugins via callback (sets up listeners)
  /// 3. Send config to worker (triggers engine initialization)
  /// 4. Wait for 'ready' (worker has created SyncEngine)
  ///
  /// The [jsScript] must be a path to a compiled JS file (e.g., 'worker.dart.js').
  /// Compile with: `dart compile js -o web/worker.dart.js lib/worker.dart`
  static Future<WebWorkerHandle> create(
    String jsScript,
    SyncEngineConfig config,
    String? debugName,
    Future<void> Function(WebWorkerHandle handle) initializePlugins,
  ) async {
    // 1. Spawn web worker
    final worker = web.Worker(jsScript.toJS);
    final handle = WebWorkerHandle._(worker);

    // Set up message listener
    worker.addEventListener(
        'message',
        (web.Event event) {
          final messageEvent = event as web.MessageEvent;
          handle._controller.add(messageEvent.data);
        }.toJS);

    // Set up error listener
    worker.addEventListener(
        'error',
        (web.Event event) {
          final errorEvent = event as web.ErrorEvent;
          handle._controller.addError(
            Exception('Worker error: ${errorEvent.message}'),
          );
        }.toJS);

    // 2. Initialize plugins
    await initializePlugins(handle);

    // 3. Send config
    handle.sendMessage({'type': 'InitConfig', 'config': config.toJson()});

    // 4. Wait for ready
    await handle.messages.firstWhere((msg) => msg == 'ready');

    return handle;
  }

  @override
  void sendMessage(Object message) {
    _worker.postMessage(message.jsify());
  }

  @override
  Stream<Object?> get messages => _controller.stream;

  @override
  Future<void> dispose() async {
    await _controller.close();
    _worker.terminate();
  }
}
