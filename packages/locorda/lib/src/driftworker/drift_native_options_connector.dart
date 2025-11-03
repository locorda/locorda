/// Main thread connector for Drift native database options in worker architecture.
///
/// Provides both sender() and receiver() methods:
/// - sender(): Creates WorkerPlugin for main thread (uses path_provider, has Flutter deps)
/// - receiver(): Delegates to DriftNativeOptionsReceiver (Pure Dart, no Flutter deps)
///
/// Uses Request/Response pattern to avoid race conditions with broadcast streams.
/// Worker requests paths when needed, main thread responds with resolved values.
library;

import 'dart:async';

import 'package:locorda/src/driftworker/drift_native_options_receiver_native.dart'
    if (dart.library.html) 'package:locorda/src/driftworker/drift_native_options_receiver_web.dart';
import 'package:locorda/src/driftworker/drift_native_options_sender_native.dart'
    if (dart.library.html) 'package:locorda/src/driftworker/drift_native_options_sender_web.dart';
import 'package:locorda_drift/locorda_drift.dart';
import 'package:locorda_worker/locorda_worker.dart';

/// Main thread API for Drift native database options connector.
///
/// Provides sender() to create a WorkerPlugin for the main thread, and receiver()
/// for workers (though workers typically import via worker.dart instead).
///
/// The sender plugin:
/// 1. Listens for RequestDriftOptions from worker
/// 2. Resolves database and temp directory paths using path_provider
/// 3. Sends ResponseDriftOptionsMessage back to worker via WorkerChannel
///
/// ## Usage
///
/// Register as plugin during sync system setup:
///
/// ```dart
/// final sync = await Locorda.createWithWorker(
///   engineParamsFactory: createEngineParams,
///   jsScript: 'worker.dart.js',
///   plugins: [
///     DriftNativeOptionsConnector.sender(),
///   ],
///   // ... other config
/// );
/// ```
///
/// For testing or custom paths:
///
/// ```dart
/// plugins: [
///   DriftNativeOptionsConnector.sender(
///     databaseDirectory: () async => '/custom/db/path',
///     tempDirectoryPath: () async => '/custom/temp/path',
///   ),
/// ],
/// ```
///
/// In worker, receive the options:
///
/// ```dart
/// // Import worker-specific export (recommended for workers):
/// import 'package:locorda/worker.dart';
///
/// Future<EngineParams> createEngineParams(
///   SyncEngineConfig config,
///   WorkerContext context,
/// ) async {
///   final nativeOptions = await DriftNativeOptionsConnector.receiver(context);
///   final storage = await DriftStorage.create(
///     web: LocordaDriftWebOptions(...),
///     native: nativeOptions,
///   );
///   // ... return EngineParams
/// }
/// ```
class DriftNativeOptionsConnector {
  /// Creates a plugin factory for this connector.
  ///
  /// The returned factory will be called by the worker framework with the [LocordaWorker].
  ///
  /// By default, uses [getApplicationDocumentsDirectory] and [getTemporaryDirectory].
  /// For testing or custom paths, provide custom provider functions.
  static WorkerPluginFactory sender({
    final Future<String> Function()? databasePath,
    final Future<Object> Function()? databaseDirectory,
    final Future<String?> Function()? tempDirectoryPath,
  }) =>
      DriftNativeOptionsSender.sender(
        databasePath: databasePath,
        databaseDirectory: databaseDirectory,
        tempDirectoryPath: tempDirectoryPath,
      );

  /// Worker-side receiver that waits for database paths from main thread.
  ///
  /// Delegates to DriftNativeOptionsReceiver for the actual implementation.
  /// This method has no Flutter dependencies and can be called from workers.
  ///
  /// Uses Request/Response pattern: Worker sends request to main thread,
  /// which resolves paths and responds. This avoids race conditions with
  /// broadcast streams.
  ///
  /// Throws [TimeoutException] after 5 seconds if no response is received,
  /// with helpful error message about missing plugin registration.
  ///
  /// Example:
  /// ```dart
  /// Future<EngineParams> createEngineParams(
  ///   SyncEngineConfig config,
  ///   WorkerContext context,
  /// ) async {
  ///   final nativeOptions = await DriftNativeOptionsConnector.receiver(context);
  ///   return EngineParams(
  ///     storage: await DriftStorage.create(native: nativeOptions),
  ///     // ...
  ///   );
  /// }
  /// ```
  static Future<LocordaDriftNativeOptions> receiver(
    WorkerContext context, {
    Duration timeout = const Duration(seconds: 5),
  }) =>
      DriftNativeOptionsReceiver.receiver(context, timeout: timeout);
}
