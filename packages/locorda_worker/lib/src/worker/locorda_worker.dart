import 'dart:async';

import 'package:locorda_core/locorda_core.dart';

import 'worker_entry_point.dart';

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
abstract class LocordaWorker {
  /// Creates worker handle auto-detecting the current platform.
  ///
  /// - [paramsFactory]: Function that creates EngineParams in worker thread
  /// - [config]: SyncEngine configuration to pass to worker
  /// - [jsScript]: Path to compiled JS worker for web platform (e.g., 'worker.dart.js')
  /// - [debugName]: Optional name for debugging/logging purposes
  /// - [workerInitializer]: Optional function to run before engine setup (e.g., logging config)
  ///
  /// The factory automatically uses isolate on native platforms and
  /// web worker on web, eliminating need for platform checks in user code.
  ///
  /// ## Worker Initialization
  ///
  /// The optional [workerInitializer] callback is executed **before** the
  /// engine is created, allowing apps to configure logging, error handlers,
  /// or other worker-global state.
  ///
  /// **IMPORTANT**: The initializer must be a **top-level or static function**,
  /// not a closure, because it's passed through `Isolate.spawn()` on native platforms.
  ///
  /// ```dart
  /// // Define as top-level function
  /// void setupWorkerLogging() {
  ///   Logger.root.level = Level.INFO;
  ///   Logger.root.onRecord.listen((record) {
  ///     print('${record.level.name}: ${record.loggerName}: ${record.message}');
  ///   });
  /// }
  ///
  /// final sync = await Locorda.createWithWorker(
  ///   workerInitializer: setupWorkerLogging,  // Top-level function reference
  ///   // ... other params
  /// );
  /// ```
  ///
  /// If the initializer throws, the error is logged but worker startup continues.
  ///
  /// ## Worker Setup Pattern
  ///
  /// Your worker file must call `workerMain()` with your factory and
  /// optional initializer. Both must be **top-level functions** (not closures)
  /// because they're passed through `Isolate.spawn()` on native platforms.
  ///
  /// ```dart
  /// // lib/worker.dart
  /// import 'package:locorda_worker/locorda_worker.dart';
  /// import 'package:logging/logging.dart';
  ///
  /// void main() {
  ///   workerMain(
  ///     createEngineParams,
  ///     workerInitializer: setupLogging,  // Top-level function
  ///   );
  /// }
  ///
  /// // Top-level function for worker initialization
  /// void setupLogging() {
  ///   Logger.root.level = Level.INFO;
  ///   Logger.root.onRecord.listen((record) {
  ///     print('${record.level.name}: ${record.loggerName}: ${record.message}');
  ///   });
  /// }
  ///
  /// // Top-level factory function
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
  ///   plugins: [...],  // Optional plugins for cross-thread communication
  ///   // ... config
  /// );
  /// ```

  /// Sends message to worker.
  ///
  /// Messages must be JSON-serializable (primitives, maps, lists).
  void sendMessage(Object message);

  /// Stream of messages received from worker.
  ///
  /// Each message is a JSON-serializable object sent by worker.
  ///
  /// **Note:** This stream receives ALL messages from worker, including
  /// both framework messages and `__channel` messages (app-specific).
  /// Filter by checking `message['__channel']` to distinguish them.
  Stream<Object?> get messages;

  /// Terminates worker and cleans up resources.
  ///
  /// After disposal, [sendMessage] and [messages] must not be used.
  Future<void> dispose();
}
