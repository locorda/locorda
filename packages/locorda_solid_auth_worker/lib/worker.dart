/// Solid authentication connector for worker isolates (Pure Dart).
///
/// This is the Flutter-free version for use in web workers and native isolates.
/// Only exports the receiver side of the connector.
///
/// ## Usage in Worker
///
/// ```dart
/// import 'package:locorda_solid_auth_worker/worker.dart';
///
/// Future<EngineParams> createEngineParams(
///   SyncEngineConfig config,
///   WorkerContext context,
/// ) async {
///   final authProvider = SolidAuthConnector.receiver(context);
///   final backend = SolidBackend(auth: authProvider);
///   // ... return EngineParams
/// }
/// ```
library;

export 'src/worker/solid/solid_auth_connector_worker.dart'
    show SolidAuthConnector;
export 'src/worker/solid/solid_auth_messages.dart' show UpdateAuthMessage;
export 'src/worker/solid/worker_solid_auth_provider.dart'
    show SolidAuthReceiver;
