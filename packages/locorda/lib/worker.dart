/// Locorda worker utilities (Pure Dart).
///
/// This is the Flutter-free version for use in web workers and native isolates.
/// Only exports the receiver/worker side of connectors.
///
/// ## Usage in Worker
///
/// ```dart
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
library;

export 'src/driftworker/drift_native_options_connector_worker.dart'
    show DriftNativeOptionsConnector;
