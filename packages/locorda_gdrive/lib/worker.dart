/// Worker entry point exports for Google Drive backend.
///
/// Use this export in your worker isolate/thread to access worker-side components.
///
/// ## Worker Usage
///
/// ```dart
/// import 'package:locorda_gdrive/worker.dart';
///
/// void main() {
///   workerMain(createEngineParams);
/// }
///
/// Future<EngineParams> createEngineParams(
///   SyncEngineConfig config,
///   WorkerContext context,
/// ) async {
///   // Create auth provider that receives credentials from main thread
///   final authProvider = GDriveAuthConnector.receiver(context);
///
///   // Create backend
///   final backend = GDriveBackend(auth: authProvider);
///
///   // ... create storage
///
///   return EngineParams(
///     storage: storage,
///     backends: [backend],
///   );
/// }
/// ```
library locorda_gdrive.worker;

// Worker-side components only
export 'src/gdrive_backend.dart' show GDriveBackend;
export 'src/auth/gdrive_auth_provider.dart' show GDriveAuthProvider;
export 'src/worker/gdrive_auth_connector.dart' show GDriveAuthConnector;
export 'src/worker/worker_gdrive_auth_provider.dart'
    show WorkerGDriveAuthProvider;
export 'src/gdrive_type_index_manager.dart' show GDriveConfig;
