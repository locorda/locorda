/// Platform-independent database options for Drift storage.
///
/// These classes replace drift_flutter's DriftWebOptions and DriftNativeOptions
/// to allow usage in pure Dart contexts (like web workers) without Flutter dependencies.
library;

import 'dart:async';
import 'dart:typed_data';

/// Options for web-based Drift databases.
///
/// Platform-independent version of drift_flutter's DriftWebOptions.
/// Used for both Flutter web apps and pure Dart web workers.
final class LocordaDriftWebOptions {
  /// The URI to the sqlite3.wasm file.
  final Uri sqlite3Wasm;

  /// The URI to the drift_worker.js file.
  final Uri driftWorker;

  /// Optional callback for database initialization results.
  ///
  /// The callback receives a dynamic result object from the database initialization.
  /// On web, this is a WasmDatabaseResult from package:drift/wasm.dart.
  final void Function(Object)? onResult;

  /// Optional callback to initialize database from existing data.
  final FutureOr<Uint8List?> Function()? initializeDatabase;

  const LocordaDriftWebOptions({
    required this.sqlite3Wasm,
    required this.driftWorker,
    this.onResult,
    this.initializeDatabase,
  });
}

/// Options for native Drift databases.
///
/// Platform-independent version of drift_flutter's DriftNativeOptions.
/// Used for both Flutter native apps and pure Dart native isolates.
final class LocordaDriftNativeOptions {
  /// Whether to share database across isolates (native only).
  final bool shareAcrossIsolates;

  /// Enable debug logging for isolate communication (native only).
  final bool isolateDebugLog;

  /// Custom database path provider (native only).
  final Future<String> Function()? databasePath;

  /// Custom database directory provider (native only).
  final Future<Object> Function()? databaseDirectory;
  final Future<String?> Function()? tempDirectoryPath;

  const LocordaDriftNativeOptions({
    this.shareAcrossIsolates = true,
    this.isolateDebugLog = false,
    this.databasePath,
    this.databaseDirectory,
    this.tempDirectoryPath,
  });
}
