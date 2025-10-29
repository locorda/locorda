import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'worker_handle.dart';

/// Web platform implementation using Web Workers (modern web API).
class WebWorkerHandle implements LocordaWorkerHandle {
  final web.Worker _worker;
  final StreamController<Object?> _controller = StreamController.broadcast();

  WebWorkerHandle._(this._worker);

  /// Creates worker from compiled JavaScript file.
  ///
  /// The [jsScript] must be a path to a compiled JS file (e.g., 'worker.dart.js').
  /// User must compile their worker.dart to JS beforehand:
  /// ```bash
  /// dart compile js -o web/worker.dart.js lib/worker.dart
  /// ```
  static Future<WebWorkerHandle> create(
    String jsScript,
    String? debugName,
  ) async {
    final worker = web.Worker(jsScript.toJS);
    final handle = WebWorkerHandle._(worker);

    // Set up message listener using modern EventTarget API
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

    // Wait for 'ready' message from worker
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
