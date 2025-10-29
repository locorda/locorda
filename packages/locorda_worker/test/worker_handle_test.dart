import 'dart:async';

import 'package:locorda_core/locorda_core.dart';
import 'package:locorda_worker/src/worker/worker_entry_point.dart';
import 'package:locorda_worker/src/worker/worker_handle.dart';
import 'package:test/test.dart';

// Mock SyncEngine for testing
class _MockSyncEngine implements SyncEngine {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<SyncEngine> _testWorkerFactory(
  SyncEngineConfig config,
  WorkerContext context,
) async {
  return _MockSyncEngine();
}

void main() {
  group('LocordaWorkerHandle.create (platform-agnostic)', () {
    test('creates worker on current platform', () async {
      final worker = await LocordaWorkerHandle.create(
        syncEngineFactory: _testWorkerFactory,
        jsScript: 'worker.dart.js', // Ignored on native
        debugName: 'test-worker',
      );

      expect(worker, isA<LocordaWorkerHandle>());

      await worker.dispose();
    });

    test('provides message stream', () async {
      final worker = await LocordaWorkerHandle.create(
        syncEngineFactory: _testWorkerFactory,
        jsScript: 'worker.dart.js',
      );

      expect(worker.messages, isA<Stream<Object?>>());

      await worker.dispose();
    });

    test('allows sending messages', () async {
      final worker = await LocordaWorkerHandle.create(
        syncEngineFactory: _testWorkerFactory,
        jsScript: 'worker.dart.js',
      );

      // Should not throw
      worker.sendMessage({'test': 'data'});
      worker.sendMessage('string message');
      worker.sendMessage(42);

      await Future.delayed(const Duration(milliseconds: 50));
      await worker.dispose();
    });

    test('disposes cleanly', () async {
      final worker = await LocordaWorkerHandle.create(
        syncEngineFactory: _testWorkerFactory,
        jsScript: 'worker.dart.js',
      );

      await expectLater(worker.dispose(), completes);
    });

    test('can create multiple workers', () async {
      final worker1 = await LocordaWorkerHandle.create(
        syncEngineFactory: _testWorkerFactory,
        jsScript: 'worker.dart.js',
        debugName: 'worker-1',
      );

      final worker2 = await LocordaWorkerHandle.create(
        syncEngineFactory: _testWorkerFactory,
        jsScript: 'worker.dart.js',
        debugName: 'worker-2',
      );

      expect(worker1, isNot(same(worker2)));

      await worker1.dispose();
      await worker2.dispose();
    });
  });
}
