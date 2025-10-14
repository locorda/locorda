import 'package:locorda_core/locorda_core.dart';
import 'package:locorda_core/src/crdt_document_manager.dart';
import 'package:locorda_core/src/index/index_manager.dart';
import 'package:locorda_core/src/storage/storage_interface.dart';
import 'package:locorda_core/src/sync/shard_document_generator.dart';
import 'package:logging/logging.dart';

final _log = Logger('SyncFunction');

/// Synchronization function that generates shard documents from DB entries.
///
/// The sync function is triggered periodically or manually. It:
/// 1. Detects shards with changes (via physical clock comparison)
/// 2. Loads all active (non-deleted) entries for those shards from DB
/// 3. Generates complete shard documents from entries
/// 4. Saves shard documents (DocumentManager handles diffing and tombstones)
/// 5. Creates missing GroupIndices based on save results
class SyncFunction {
  final ShardDocumentGenerator _shardDocumentGenerator;
  final Storage _storage;

  SyncFunction({
    required Backend backend,
    required Storage storage,
    required CrdtDocumentManager documentManager,
    required IndexManager indexManager,
  })  : _shardDocumentGenerator = ShardDocumentGenerator(
          storage: storage,
          documentManager: documentManager,
          indexManager: indexManager,
        ),
        _storage = storage;

  Future<void> call(DateTime syncTime) async {
    // Prepare
    await _ensureShardDocumentsAreUpToDate(syncTime);

    // Sync with remote
    await _syncWithRemote(syncTime);
  }

  Future<void> _ensureShardDocumentsAreUpToDate(DateTime syncTime) async {
    _log.info('Sync triggered - finding shards to update');

    // 1. Get timestamp of last sync
    final lastSyncTimestamp = await _storage.getLastShardSyncTimestamp();
    _log.fine('Last sync timestamp: $lastSyncTimestamp');
    try {
      // 2. Generate shard documents for all shards with changes since last sync
      await _shardDocumentGenerator(syncTime, lastSyncTimestamp);

      // 3. Update last sync timestamp to current time
      // Use the current physical time to mark when this sync completed
      final now = syncTime.millisecondsSinceEpoch;
      await _storage.updateLastShardSyncTimestamp(now);
      _log.fine('Updated last sync timestamp to: $now');
    } catch (e, st) {
      _log.severe('Error during shard document generation', e, st);
      rethrow;
    }
  }
  
  Future<void> _syncWithRemote(DateTime syncTime) async {
    /*
    */
  }
}
