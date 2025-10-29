@TestOn('vm') // Only run on native platforms
import 'dart:async';

import 'package:locorda_core/locorda_core.dart';
import 'package:locorda_worker/src/worker/native_worker_handle.dart';
import 'package:locorda_worker/src/worker/worker_entry_point.dart';
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
  group('NativeWorkerHandle', () {
    test('creates worker successfully', () async {
      final worker = await NativeWorkerHandle.create(
        _testWorkerFactory,
        'test-worker',
      );

      expect(worker, isA<NativeWorkerHandle>());

      await worker.dispose();
    });

    test('exposes messages stream', () async {
      final worker = await NativeWorkerHandle.create(
        _testWorkerFactory,
        'test-worker',
      );

      // Verify stream is available (don't listen yet - isolate already does)
      expect(worker.messages, isA<Stream<Object?>>());

      await worker.dispose();
    });

    test('can send messages', () async {
      final worker = await NativeWorkerHandle.create(
        _testWorkerFactory,
        'test-worker',
      );

      // Send messages - should not throw
      worker.sendMessage({'test': 'message'});
      worker.sendMessage({'index': 1});
      worker.sendMessage({'index': 2});

      // Give isolate time to process
      await Future.delayed(const Duration(milliseconds: 50));

      await worker.dispose();
    });

    test('disposes cleanly', () async {
      final worker = await NativeWorkerHandle.create(
        _testWorkerFactory,
        'test-worker',
      );

      // Should not throw
      await worker.dispose();
    });

    test('can create multiple workers', () async {
      final worker1 = await NativeWorkerHandle.create(
        _testWorkerFactory,
        'worker-1',
      );
      final worker2 = await NativeWorkerHandle.create(
        _testWorkerFactory,
        'worker-2',
      );

      expect(worker1, isA<NativeWorkerHandle>());
      expect(worker2, isA<NativeWorkerHandle>());
      expect(worker1, isNot(same(worker2)));

      await worker1.dispose();
      await worker2.dispose();
    });
  });
}
