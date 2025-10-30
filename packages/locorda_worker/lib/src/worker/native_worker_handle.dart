import 'dart:async';
import 'dart:isolate';

import 'worker_handle.dart';
import 'worker_entry_point.dart';

/// Message sent to isolate entry point with factory function.
class _IsolateStartMessage {
  final SendPort sendPort;
  final EngineParamsFactory factory;

  _IsolateStartMessage(this.sendPort, this.factory);
}

/// Native platform implementation using Dart isolates.
class NativeWorkerHandle implements LocordaWorkerHandle {
  final SendPort _sendPort;
  final ReceivePort _receivePort;
  final Isolate _isolate;

  NativeWorkerHandle._(
    this._sendPort,
    this._receivePort,
    this._isolate,
  );

  /// Creates worker by spawning isolate with given factory function.
  ///
  /// The factory is passed via message to the generic isolate entry point.
  static Future<NativeWorkerHandle> create(
    EngineParamsFactory paramsFactory,
    String? debugName,
  ) async {
    final receivePort = ReceivePort();

    // Spawn isolate with generic entry point
    final isolate = await Isolate.spawn(
      _isolateEntryPoint,
      _IsolateStartMessage(receivePort.sendPort, paramsFactory),
      debugName: debugName,
    );

    // Wait for SendPort from worker
    final sendPort = await receivePort.first as SendPort;

    return NativeWorkerHandle._(sendPort, receivePort, isolate);
  }

  /// Generic isolate entry point that receives factory via message.
  ///
  /// This is a static function that can be spawned by Isolate.spawn().
  /// It receives the app's factory function and delegates to framework.
  static void _isolateEntryPoint(_IsolateStartMessage message) {
    // Call framework's isolate setup with the factory
    startWorkerIsolate(message.sendPort, message.factory);
  }

  @override
  void sendMessage(Object message) {
    _sendPort.send(message);
  }

  @override
  Stream<Object?> get messages => _receivePort;

  @override
  Future<void> dispose() async {
    _receivePort.close();
    _isolate.kill(priority: Isolate.immediate);
  }
}
