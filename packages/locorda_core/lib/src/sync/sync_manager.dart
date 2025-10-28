/// Sync manager for coordinating synchronization operations and status.
library;

import 'dart:async';

import 'sync_state.dart';

/// Configuration for automatic sync behavior.
class AutoSyncConfig {
  /// Whether automatic sync is enabled.
  final bool enabled;

  /// Interval between automatic sync operations.
  /// Only used when [enabled] is true.
  final Duration interval;

  /// Whether to trigger sync automatically on startup.
  final bool syncOnStartup;

  const AutoSyncConfig({
    this.enabled = false,
    this.interval = const Duration(minutes: 5),
    this.syncOnStartup = true,
  });

  const AutoSyncConfig.disabled()
      : enabled = false,
        interval = const Duration(minutes: 5),
        syncOnStartup = false;

  /// Create an enabled auto-sync configuration.
  const AutoSyncConfig.enabled({
    Duration interval = const Duration(minutes: 5),
    bool syncOnStartup = true,
  })  : enabled = true,
        interval = interval,
        syncOnStartup = syncOnStartup;

  factory AutoSyncConfig.fromJson(Map<String, dynamic> autoSyncJson) {
    // Parse auto sync config if present
    return AutoSyncConfig(
      enabled: autoSyncJson['enabled'] as bool? ?? false,
      interval: Duration(minutes: autoSyncJson['intervalMinutes'] as int? ?? 5),
      syncOnStartup: autoSyncJson['syncOnStartup'] as bool? ?? true,
    );
  }
}

abstract interface class SyncManager {
  /// Stream of sync state changes.
  ///
  /// Emits a new [SyncState] whenever the sync status changes.
  /// This is a broadcast stream, so multiple listeners are supported.
  Stream<SyncState> get statusStream;

  /// Current sync state (synchronous access).
  SyncState get currentState;

  /// Whether a sync operation is currently in progress.
  bool get isSyncing;

  /// Trigger a manual sync operation.
  ///
  /// If a sync is already in progress, this will wait for it to complete
  /// and then return without triggering another sync.
  ///
  /// Returns a [Future] that completes when the sync operation finishes
  /// (either successfully or with an error).
  Future<void> sync();

  /// Enable automatic sync with the given interval.
  ///
  /// If automatic sync is already enabled, this will update the interval.
  void enableAutoSync({Duration interval = const Duration(minutes: 5)});

  /// Disable automatic sync.
  ///
  /// Any in-progress sync will complete normally.
  void disableAutoSync();

  /// Clean up resources.
  ///
  /// Should be called when the sync manager is no longer needed.
  /// After disposal, no further operations are allowed.
  Future<void> dispose();
}
