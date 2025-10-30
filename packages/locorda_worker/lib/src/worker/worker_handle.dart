import 'dart:async';

import 'package:locorda_core/locorda_core.dart';

import 'worker_entry_point.dart';
import 'worker_handle_impl_native.dart'
    if (dart.library.html) 'worker_handle_impl_web.dart' as impl;

/// Factory function type for creating EngineParams in worker.
///
/// Apps implement this to configure storage, backends, and other worker-side resources.
/// The framework creates the SyncEngine from the returned EngineParams.
typedef EngineParamsFactory = Future<EngineParams> Function(
  SyncEngineConfig config,
  WorkerContext context,
);

/// Platform-agnostic handle for communication with worker isolate/thread.
///
/// Provides unified interface for both native isolates (via Isolate.spawn)
/// and web workers, hiding platform-specific details from user code.
abstract class LocordaWorkerHandle {
  /// Creates worker handle auto-detecting the current platform.
  ///
  /// - [paramsFactory]: Function that creates EngineParams in worker thread
  /// - [jsScript]: Path to compiled JS worker for web platform (e.g., 'worker.dart.js')
  /// - [debugName]: Optional name for debugging/logging purposes
  ///
  /// The factory automatically uses isolate on native platforms and
  /// web worker on web, eliminating need for platform checks in user code.
  ///
  /// ## Worker Setup Pattern
  ///
  /// Your worker file must call `workerMain()` with your factory:
  ///
  /// ```dart
  /// // lib/worker.dart
  /// import 'package:locorda_worker/locorda_worker.dart';
  ///
  /// void main() {
  ///   workerMain(createEngineParams);
  /// }
  ///
  /// Future<EngineParams> createEngineParams(
  ///   SyncEngineConfig config,
  ///   WorkerContext context,
  /// ) async {
  ///   final storage = DriftStorage(...);
  ///   final backends = [SolidBackend(...)];
  ///   // Return parameters - framework creates SyncEngine from these
  ///   return EngineParams(
  ///     storage: storage,
  ///     backends: backends,
  ///   );
  /// }
  /// ```
  ///
  /// Then use high-level API in main thread:
  /// ```dart
  /// import 'worker.dart' show createEngineParams;
  ///
  /// final sync = await Locorda.createWithWorker(
  ///   paramsFactory: createEngineParams,
  ///   jsScript: 'worker.dart.js',
  ///   // ... config
  /// );
  /// ```
  static Future<LocordaWorkerHandle> create({
    required EngineParamsFactory paramsFactory,
    required String jsScript,
    String? debugName,
  }) async {
    return impl.createImpl(paramsFactory, jsScript, debugName);
  }

  /// Sends message to worker.
  ///
  /// Messages must be JSON-serializable (primitives, maps, lists).
  void sendMessage(Object message);

  /// Stream of messages received from worker.
  ///
  /// Each message is a JSON-serializable object sent by worker.
  Stream<Object?> get messages;

  /// Terminates worker and cleans up resources.
  ///
  /// After disposal, [sendMessage] and [messages] must not be used.
  Future<void> dispose();
}
