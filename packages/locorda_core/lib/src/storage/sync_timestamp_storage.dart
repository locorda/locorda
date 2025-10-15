/// Extension methods for common sync timestamp operations on Storage.
///
/// These convenience methods wrap the generic settings API with
/// type-safe, domain-specific helpers for sync timestamps.
///
/// **Important**: Remote sync timestamps are now stored per-remote in the
/// RemoteSettings table, not in the Settings table. These helpers only
/// handle LOCAL shard sync timestamps. For remote timestamps, use the
/// Storage implementation's remote-specific methods directly.
library;

import 'package:locorda_core/locorda_core.dart';

/// Setting keys for sync timestamp storage
abstract final class _SyncSettingKeys {
  /// Key for last shard document generation timestamp
  static const String lastShardSyncTimestamp = 'sync.last_shard_sync_timestamp';
}

/// Extension methods for sync timestamp operations on Storage.
extension SyncTimestampStorage on Storage {
  /// Get last shard sync timestamp from settings.
  ///
  /// This timestamp tracks when shard documents were last generated locally.
  /// Returns 0 if no shard sync has been performed yet.
  Future<int> getLastShardSyncTimestamp() async {
    final settings =
        await getSettings([_SyncSettingKeys.lastShardSyncTimestamp]);
    final value = settings[_SyncSettingKeys.lastShardSyncTimestamp];
    return value != null ? int.parse(value) : 0;
  }

  /// Update last shard sync timestamp in settings.
  ///
  /// Called after successful shard document generation (Phase 0).
  ///
  /// Parameters:
  /// - [timestamp]: Physical clock timestamp (milliseconds since epoch)
  Future<void> updateLastShardSyncTimestamp(int timestamp) async {
    await setSetting(
        _SyncSettingKeys.lastShardSyncTimestamp, timestamp.toString());
  }
}
