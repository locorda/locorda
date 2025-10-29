/// Generic message channel for worker-main thread communication.
///
/// Provides a bidirectional pub/sub message bus for app-specific communication
/// that goes beyond the framework's standard SyncEngine operations.
///
/// Use cases:
/// - Authentication credential updates (Solid, OAuth, etc.)
/// - Custom background tasks
/// - App-specific sync strategies
/// - Plugin/extension communication
///
/// The framework provides the channel, apps define their own message types.
library;

import 'dart:async';

/// Bidirectional communication channel between main thread and worker.
///
/// Framework-agnostic: Apps define their own message types and protocols.
/// Messages are transmitted as JSON-serializable objects.
class WorkerChannel {
  final StreamController<Object?> _incomingController =
      StreamController.broadcast();
  final void Function(Object? message) _sendMessage;

  WorkerChannel(this._sendMessage);

  /// Send a message to the other side of the channel (main ↔ worker).
  void send(Object? message) {
    _sendMessage(message);
  }

  /// Stream of incoming messages from the other side.
  Stream<Object?> get messages => _incomingController.stream;

  /// Internal: Deliver incoming message from transport layer.
  void deliver(Object? message) {
    _incomingController.add(message);
  }

  /// Close the channel and clean up resources.
  Future<void> close() async {
    await _incomingController.close();
  }
}
