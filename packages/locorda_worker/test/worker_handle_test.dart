import 'dart:async';

import 'package:locorda_core/locorda_core.dart';
import 'package:locorda_worker/src/worker/worker_entry_point.dart';
import 'package:locorda_worker/src/worker/locorda_worker.dart';
import 'package:locorda_worker/src/worker/locorda_worker_impl_native.dart'
    if (dart.library.html) 'package:locorda_worker/src/worker/locorda_worker_impl_web.dart'
    as impl;
import 'package:test/test.dart';

Future<EngineParams> _createEngineParams(
  SyncEngineConfig config,
  WorkerContext context,
) async =>
    EngineParams(storage: InMemoryStorage(), backends: []);

SyncEngineConfig _createTestConfig() => SyncEngineConfig(
      resources: [],
    );

/// Helper to create worker without plugins (for simple tests)
Future<LocordaWorker> _createWorker({
  required EngineParamsFactory engineParamsFactory,
  required SyncEngineConfig config,
  required String jsScript,
  String? debugName,
}) {
  return impl.createImpl(
    engineParamsFactory,
    config,
    jsScript,
    debugName,
    (_) async {}, // No plugins
  );
}

void main() {
  group('LocordaWorker (platform-agnostic)', () {
    test('creates worker on current platform', () async {
      final worker = await _createWorker(
        engineParamsFactory: _createEngineParams,
        config: _createTestConfig(),
        jsScript: 'worker.dart.js', // Ignored on native
        debugName: 'test-worker',
      );

      expect(worker, isA<LocordaWorker>());

      await worker.dispose();
    });

    test('provides message stream', () async {
      final worker = await _createWorker(
        engineParamsFactory: _createEngineParams,
        config: _createTestConfig(),
        jsScript: 'worker.dart.js',
      );

      expect(worker.messages, isA<Stream<Object?>>());

      await worker.dispose();
    });

    test('allows sending messages', () async {
      final worker = await _createWorker(
        engineParamsFactory: _createEngineParams,
        config: _createTestConfig(),
        jsScript: 'worker.dart.js',
      );

      // Send test channel messages (won't be deserialized by framework)
      // Using __channel marker so worker treats them as app-specific messages
      worker.sendMessage({'__channel': true, 'data': 'test-message-1'});
      worker.sendMessage({'__channel': true, 'data': 'test-message-2'});
      worker.sendMessage({'__channel': true, 'data': 'test-message-3'});

      await Future.delayed(const Duration(milliseconds: 50));
      await worker.dispose();
    });

    test('disposes cleanly', () async {
      final worker = await _createWorker(
        engineParamsFactory: _createEngineParams,
        config: _createTestConfig(),
        jsScript: 'worker.dart.js',
      );

      await expectLater(worker.dispose(), completes);
    });

    test('can create multiple workers', () async {
      final worker1 = await _createWorker(
        engineParamsFactory: _createEngineParams,
        config: _createTestConfig(),
        jsScript: 'worker.dart.js',
        debugName: 'worker-1',
      );

      final worker2 = await _createWorker(
        engineParamsFactory: _createEngineParams,
        config: _createTestConfig(),
        jsScript: 'worker.dart.js',
        debugName: 'worker-2',
      );

      expect(worker1, isNot(same(worker2)));

      await worker1.dispose();
      await worker2.dispose();
    });
  });
}
