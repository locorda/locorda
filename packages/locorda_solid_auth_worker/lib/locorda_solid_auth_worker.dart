/// Solid authentication bridge for Locorda worker architecture.
///
/// Synchronizes authentication state and credentials from main thread's
/// [SolidAuth] to worker isolate, where they're used for authenticated
/// HTTP requests via [SolidBackend].
///
/// ## Main Thread
///
/// Use [SolidAuthConnector] as a worker plugin:
///
/// ```dart
/// final sync = await Locorda.createWithWorker(
///   engineParamsFactory: createEngineParams,
///   jsScript: 'worker.dart.js',
///   plugins: [
///     SolidAuthConnector.responder(solidAuth),
///   ],
///   // ... other config
/// );
/// ```
///
/// ## Worker Thread
///
/// Create auth provider in SyncEngine factory:
///
/// ```dart
/// Future<SyncEngine> createEngineParams(
///   SyncEngineConfig config,
///   WorkerContext context,
/// ) async {
///   final authProvider = SolidAuthConnector.requester(context);
///   final backend = SolidBackend(auth: authProvider);
///   // ... return SyncEngine
/// }
/// ```
library;

export 'src/worker/solid/solid_auth_connector.dart' show SolidAuthConnector;
export 'src/worker/solid/solid_auth_messages.dart' show UpdateAuthMessage;
export 'src/worker/solid/worker_solid_auth_provider.dart'
    show WorkerSolidAuthProvider;
