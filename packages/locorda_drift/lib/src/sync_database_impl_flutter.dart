/// Flutter implementation of SyncDatabase factory using drift_flutter.
///
/// This implementation is selected via conditional import on native platforms.
/// It uses drift_flutter for automatic Flutter platform detection.
library;

import 'package:drift_flutter/drift_flutter.dart';

import 'drift_options.dart';
import 'sync_database.dart';

/// Extension methods to convert Locorda options to drift_flutter options.
extension LocordaDriftWebOptionsX on LocordaDriftWebOptions {
  /// Convert to drift_flutter's DriftWebOptions.
  DriftWebOptions toDriftWebOptions() => DriftWebOptions(
        sqlite3Wasm: sqlite3Wasm,
        driftWorker: driftWorker,
        onResult: onResult,
        initializeDatabase: initializeDatabase,
      );
}

extension LocordaDriftNativeOptionsX on LocordaDriftNativeOptions {
  /// Convert to drift_flutter's DriftNativeOptions.
  ///
  /// Resolves all closures to their actual values before conversion,
  /// because drift_flutter will spawn a new isolate for database operations,
  /// and closures cannot cross isolate boundaries.
  Future<DriftNativeOptions> toDriftNativeOptions() async {
    // Resolve all closures to actual values before passing to drift_flutter
    final resolvedDatabasePath =
        databasePath != null ? await databasePath!() : null;
    final resolvedDatabaseDirectory =
        databaseDirectory != null ? await databaseDirectory!() : null;
    final resolvedTempDirectoryPath =
        tempDirectoryPath != null ? await tempDirectoryPath!() : null;

    return DriftNativeOptions(
      shareAcrossIsolates: shareAcrossIsolates,
      isolateDebugLog: isolateDebugLog,
      // Pass resolved values, not closures
      databasePath: resolvedDatabasePath != null
          ? () => Future.value(resolvedDatabasePath)
          : null,
      databaseDirectory: resolvedDatabaseDirectory != null
          ? () => Future.value(resolvedDatabaseDirectory)
          : null,
      tempDirectoryPath: resolvedTempDirectoryPath != null
          ? () => Future.value(resolvedTempDirectoryPath)
          : null,
    );
  }
}

/// Flutter-specific implementation of SyncDatabase factory.
///
/// Uses drift_flutter's driftDatabase() for automatic platform selection.
class SyncDatabaseImpl {
  /// Create SyncDatabase with Flutter platform detection.
  ///
  /// Converts Locorda options to drift_flutter options and uses
  /// driftDatabase() for automatic platform selection.
  /// Returns Future for API consistency with web implementation.
  static Future<SyncDatabase> create({
    LocordaDriftWebOptions? web,
    LocordaDriftNativeOptions? native,
  }) async {
    // Resolve native options closures before passing to drift_flutter
    final resolvedNativeOptions =
        native != null ? await native.toDriftNativeOptions() : null;

    final executor = driftDatabase(
      name: 'locorda_sync',
      web: web?.toDriftWebOptions(),
      native: resolvedNativeOptions,
    );
    return SyncDatabase.forExecutor(executor);
  }
}
