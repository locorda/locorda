/// Worker entry point for isolate/web worker execution.
///
/// Provides the main message loop and context management for worker-based
/// SyncEngine instances.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:locorda_worker/src/worker/worker_channel.dart';
import 'package:locorda_worker/src/worker/worker_handle.dart';
import 'package:locorda_worker/src/worker/worker_messages.dart';
import 'package:locorda_core/locorda_core.dart';
import 'package:rdf_core/rdf_core.dart';

// Conditional import for web worker implementation
import 'web_worker_entry_point_stub.dart'
    if (dart.library.js_interop) 'web_worker_entry_point.dart';

/// Abstraction for sending messages back to main thread.
///
/// This allows the same worker context to work with both native isolates
/// (using SendPort) and web workers (using postMessage).
abstract class WorkerMessageSender {
  void send(Object? message);
}

/// Native isolate implementation using SendPort
class IsolateSender implements WorkerMessageSender {
  final SendPort _sendPort;

  IsolateSender(this._sendPort);

  @override
  void send(Object? message) => _sendPort.send(message);
}

/// Context for worker execution.
///
/// Manages the SyncEngine instance and message routing within the worker.
class WorkerContext {
  final WorkerMessageSender _sender;
  final RdfGraphCodec _codec = TurtleCodec();

  /// Communication channel for cross-thread operations (e.g., auth)
  final WorkerChannel channel;

  SyncEngine? _syncSystem;

  /// Active hydration streams keyed by request ID
  final Map<String, StreamSubscription<HydrationBatch>> _activeStreams = {};

  /// Subscription to sync status stream
  StreamSubscription<SyncState>? _syncStatusSubscription;

  WorkerContext(this._sender, this.channel);

  /// Send a message back to the main thread (package-visible for web worker).
  void sendMessage(WorkerMessage message) {
    _sender.send(message.toJson());
  }

  /// Set the sync system instance (package-visible for web worker).
  void setSyncSystem(SyncEngine syncSystem) {
    _syncSystem = syncSystem;

    // Subscribe to sync status updates and forward to main thread
    _syncStatusSubscription =
        syncSystem.syncManager.statusStream.listen((state) {
      final statusString = switch (state.status) {
        SyncStatus.idle => 'idle',
        SyncStatus.syncing => 'syncing',
        SyncStatus.success => 'success',
        SyncStatus.error => 'error',
      };

      _sendMessage(SyncStateUpdateMessage(
        status: statusString,
        lastSyncTime: state.lastSyncTime,
        errorMessage: state.errorMessage,
      ));
    });
  }

  /// Send a message back to the main thread
  void _sendMessage(WorkerMessage message) {
    _sender.send(message.toJson());
  }

  /// Handle incoming message from main thread
  Future<void> handleMessage(Object? message) async {
    if (message is! Map<String, dynamic>) {
      return; // Ignore non-JSON messages
    }

    try {
      final workerMessage = deserializeMessage(message);

      if (workerMessage is SaveRequest) {
        await _handleSave(workerMessage);
      } else if (workerMessage is DeleteDocumentRequest) {
        await _handleDelete(workerMessage);
      } else if (workerMessage is ConfigureGroupIndexSubscriptionRequest) {
        await _handleConfigureGroupIndex(workerMessage);
      } else if (workerMessage is HydrateStreamRequest) {
        await _handleHydrateStream(workerMessage);
      } else if (workerMessage is SyncTriggerRequest) {
        await _handleSyncTrigger(workerMessage);
      } else if (workerMessage is EnableAutoSyncRequest) {
        await _handleEnableAutoSync(workerMessage);
      } else if (workerMessage is DisableAutoSyncRequest) {
        await _handleDisableAutoSync(workerMessage);
      } else if (workerMessage is GetSyncStateRequest) {
        await _handleGetSyncState(workerMessage);
      }
      // Note: SetupRequest is NOT handled here - setup is done by app's setupFn
      // Note: Auth updates are NOT handled by framework - use WorkerChannel for app-specific messages
    } catch (e, st) {
      // Log error but don't crash worker
      print('Worker error handling message: $e\n$st');
    }
  }

  Future<void> _handleSave(SaveRequest request) async {
    try {
      if (_syncSystem == null) {
        throw StateError('Sync system not initialized');
      }

      final typeIri = IriTerm(request.typeIri);
      final appData = _codec.decode(request.appDataTurtle);

      await _syncSystem!.save(typeIri, appData);

      _sendMessage(SaveResponse(request.requestId, success: true));
    } catch (e, st) {
      _sendMessage(SaveResponse(
        request.requestId,
        success: false,
        error: '$e\n$st',
      ));
    }
  }

  Future<void> _handleDelete(DeleteDocumentRequest request) async {
    try {
      if (_syncSystem == null) {
        throw StateError('Sync system not initialized');
      }

      final typeIri = IriTerm(request.typeIri);
      final externalIri = IriTerm(request.externalIri);

      await _syncSystem!.deleteDocument(typeIri, externalIri);

      _sendMessage(DeleteDocumentResponse(request.requestId, success: true));
    } catch (e, st) {
      _sendMessage(DeleteDocumentResponse(
        request.requestId,
        success: false,
        error: '$e\n$st',
      ));
    }
  }

  Future<void> _handleConfigureGroupIndex(
      ConfigureGroupIndexSubscriptionRequest request) async {
    try {
      if (_syncSystem == null) {
        throw StateError('Sync system not initialized');
      }

      final groupKeyGraph = _codec.decode(request.groupKeyGraphTurtle);
      final policyMap =
          jsonDecode(request.itemFetchPolicy) as Map<String, dynamic>;
      final itemFetchPolicy = ItemFetchPolicy.fromMap(policyMap);

      await _syncSystem!.configureGroupIndexSubscription(
        request.indexName,
        groupKeyGraph,
        itemFetchPolicy,
      );

      _sendMessage(ConfigureGroupIndexSubscriptionResponse(
        request.requestId,
        success: true,
      ));
    } catch (e, st) {
      _sendMessage(ConfigureGroupIndexSubscriptionResponse(
        request.requestId,
        success: false,
        error: '$e\n$st',
      ));
    }
  }

  Future<void> _handleHydrateStream(HydrateStreamRequest request) async {
    try {
      if (_syncSystem == null) {
        throw StateError('Sync system not initialized');
      }

      final typeIri = IriTerm(request.typeIri);

      final stream = _syncSystem!.hydrateStream(
        typeIri: typeIri,
        indexName: request.indexName,
        cursor: request.cursor,
        initialBatchSize: request.initialBatchSize,
      );

      // Subscribe to stream and forward batches to main thread
      final subscription = stream.listen(
        (batch) {
          // Serialize graphs to Turtle
          final updates = batch.updates
              .map((item) => (item.$1.value, _codec.encode(item.$2)))
              .toList();

          final deletions = batch.deletions
              .map((item) => (item.$1.value, _codec.encode(item.$2)))
              .toList();

          _sendMessage(HydrationBatchMessage(
            request.requestId,
            updates: updates,
            deletions: deletions,
            cursor: batch.cursor,
            isComplete: false,
          ));
        },
        onError: (e, st) {
          // Send error as final batch
          _sendMessage(HydrationBatchMessage(
            request.requestId,
            updates: [],
            deletions: [],
            isComplete: true,
          ));
          _activeStreams.remove(request.requestId);
        },
        onDone: () {
          // Send completion marker
          _sendMessage(HydrationBatchMessage(
            request.requestId,
            updates: [],
            deletions: [],
            isComplete: true,
          ));
          _activeStreams.remove(request.requestId);
        },
      );

      _activeStreams[request.requestId] = subscription;
    } catch (e) {
      // Send error as immediate completion
      _sendMessage(HydrationBatchMessage(
        request.requestId,
        updates: [],
        deletions: [],
        isComplete: true,
      ));
    }
  }

  Future<void> _handleSyncTrigger(SyncTriggerRequest request) async {
    try {
      if (_syncSystem == null) {
        throw StateError('Sync system not initialized');
      }

      await _syncSystem!.syncManager.sync();

      _sendMessage(SyncTriggerResponse(request.requestId, success: true));
    } catch (e, st) {
      _sendMessage(SyncTriggerResponse(
        request.requestId,
        success: false,
        error: '$e\n$st',
      ));
    }
  }

  Future<void> _handleEnableAutoSync(EnableAutoSyncRequest request) async {
    try {
      if (_syncSystem == null) {
        throw StateError('Sync system not initialized');
      }

      _syncSystem!.syncManager.enableAutoSync(
        interval: Duration(minutes: request.intervalMinutes),
      );

      _sendMessage(EnableAutoSyncResponse(request.requestId, success: true));
    } catch (e) {
      // On error, still send success=false response
      _sendMessage(EnableAutoSyncResponse(request.requestId, success: false));
    }
  }

  Future<void> _handleDisableAutoSync(DisableAutoSyncRequest request) async {
    try {
      if (_syncSystem == null) {
        throw StateError('Sync system not initialized');
      }

      _syncSystem!.syncManager.disableAutoSync();

      _sendMessage(DisableAutoSyncResponse(request.requestId, success: true));
    } catch (e) {
      // On error, still send success=false response
      _sendMessage(DisableAutoSyncResponse(request.requestId, success: false));
    }
  }

  Future<void> _handleGetSyncState(GetSyncStateRequest request) async {
    try {
      if (_syncSystem == null) {
        throw StateError('Sync system not initialized');
      }

      final state = _syncSystem!.syncManager.currentState;
      final statusString = switch (state.status) {
        SyncStatus.idle => 'idle',
        SyncStatus.syncing => 'syncing',
        SyncStatus.success => 'success',
        SyncStatus.error => 'error',
      };

      _sendMessage(GetSyncStateResponse(
        request.requestId,
        status: statusString,
        lastSyncTime: state.lastSyncTime,
        errorMessage: state.errorMessage,
      ));
    } catch (e, st) {
      // On error, return error state
      _sendMessage(GetSyncStateResponse(
        request.requestId,
        status: 'error',
        errorMessage: '$e\n$st',
      ));
    }
  }

  /// Clean up resources
  Future<void> dispose() async {
    // Cancel sync status subscription
    await _syncStatusSubscription?.cancel();

    // Cancel all active streams
    for (final subscription in _activeStreams.values) {
      await subscription.cancel();
    }
    _activeStreams.clear();

    // Close sync system
    await _syncSystem?.close();
  }
}

/// Standard worker entry point for native isolates.
///
/// This function registers the app's setup function and returns a reference
/// to the static entry point that can be passed to Isolate.spawn().
///
/// Framework responsibilities:
/// - Establish communication with main thread
/// - Receive and deserialize SyncEngineConfig
/// - Call app's params factory with config + context
/// - Create SyncEngine from returned EngineParams
/// - Wrap SyncEngine in message handler
/// - Forward all messages to/from SyncEngine
///
/// App responsibilities (via params factory):
/// - Create Storage (e.g., DriftStorage)
/// - Create Backends (e.g., SolidBackend with WorkerSolidAuthProvider)
/// - Return EngineParams containing storage and backends
///
/// Example usage in app's worker.dart:
/// ```dart
/// void main() {
///   workerMain((config, context) async {
///     final storage = DriftStorage(...);
///     final backends = [SolidBackend(auth: WorkerSolidAuthProvider(context.channel))];
///     return EngineParams(storage: storage, backends: backends);
///   });
/// }
/// ```
///
/// Then in main thread setup:
/// ```dart
/// import 'worker.dart' show createEngineParams;
///
/// final handle = await LocordaWorkerHandle.create(
///   paramsFactory: createEngineParams,
///   jsScript: 'worker.dart.js',
/// );
/// ```

// FIXME: if this is needed, why is it unused?
/// Global setup function storage (needed for web workers where main() is called)
// ignore: unused_element
EngineParamsFactory? _currentSetupFunction;

/// Entry point for web workers - called when worker JS loads.
///
/// Web workers start by calling the compiled main() function.
/// Apps must call this with their setup function in worker.dart's main():
///
/// ```dart
/// // lib/worker.dart
/// void main() {
///   workerMain(createEngineParams);
/// }
/// ```
void workerMain(EngineParamsFactory setupFn) {
  // FIXME: wtf?
  // Store setup function for later (not currently needed but kept for consistency)
  _currentSetupFunction = setupFn;

  // Start web worker message loop (delegates to platform-specific implementation)
  startWebWorkerLoop(setupFn);
}

/// Entry point for native isolates - receives factory via parameter.

/// Entry point for native isolates - receives factory via parameter.
///
/// This is called by NativeWorkerHandle after Isolate.spawn().
/// The factory function is passed directly, no global storage needed.
void startWorkerIsolate(
    SendPort mainSendPort, EngineParamsFactory factory) async {
  // 1. Establish bidirectional communication
  final receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);

  // 2. Wait for SetupRequest with config
  final firstMessage = await receivePort.first;
  if (firstMessage is! Map<String, dynamic>) {
    throw StateError('Expected setup message, got: $firstMessage');
  }

  final setupRequest = SetupRequest.fromJson(firstMessage);
  final config = SyncEngineConfig.fromJson(setupRequest.config);

  // 3. Create WorkerChannel for app-specific messages
  final channel = WorkerChannel((message) {
    // Send app-specific messages with special marker
    mainSendPort.send({'__channel': true, 'data': message});
  });

  // 4. Create WorkerContext
  final context = WorkerContext(
    IsolateSender(mainSendPort),
    channel,
  );

  // 5. Call app's setup function
  try {
    final engineParams = await factory(config, context);
    context._syncSystem =
        await SyncEngine.createForParams(config: config, params: engineParams);
    context._sendMessage(SetupResponse(setupRequest.requestId, success: true));
  } catch (e, st) {
    context._sendMessage(SetupResponse(
      setupRequest.requestId,
      success: false,
      error: 'Setup failed: $e\n$st',
    ));
    return; // Abort worker
  }

  // 6. Start message loop
  receivePort.listen((message) async {
    if (message is Map<String, dynamic>) {
      // Check if it's a channel message
      if (message['__channel'] == true) {
        channel.deliver(message['data']);
      } else {
        // Framework message - handle normally
        await context.handleMessage(message);
      }
    }
  });
}
