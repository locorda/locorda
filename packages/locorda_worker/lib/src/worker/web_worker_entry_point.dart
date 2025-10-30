/// Web Worker implementation of the worker entry point.
///
/// This file contains the dart:js_interop-based implementation for web workers.
library;

import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'worker_channel.dart';
import 'worker_entry_point.dart';
import 'worker_handle.dart';
import 'worker_messages.dart';
import 'package:locorda_core/locorda_core.dart';

/// Access to the global scope in a Web Worker.
///
/// In web workers, there's a global `self` object that represents the worker's
/// global scope (similar to `window` in the main thread).
@JS('self')
external web.EventTarget get workerGlobalScope;

/// Web worker message sender using postMessage on global scope
class WebWorkerSender implements WorkerMessageSender {
  @override
  void send(Object? message) {
    // Use the global postMessage function available in worker scope
    _postMessage(message.jsify());
  }
}

/// Direct access to postMessage in worker global scope
@JS('self.postMessage')
external void _postMessage(JSAny? message);

/// Start the web worker message loop.
///
/// This sets up the message handler for the web worker's global scope
/// and initializes the worker when the first setup message arrives.
void startWebWorkerLoop(EngineParamsFactory setupFn) {
  WorkerContext? context;
  bool isInitializing = false;

  // Set up message listener on web worker global scope
  workerGlobalScope.addEventListener(
    'message',
    ((web.Event event) {
      // Extract message data synchronously
      final messageEvent = event as web.MessageEvent;
      final data = messageEvent.data.dartify();

      if (data is! Map<String, dynamic>) return;

      // Handle message asynchronously (fire-and-forget pattern for event handlers)
      _handleWorkerMessage(
        data,
        () => context,
        (newContext) {
          context = newContext;
          isInitializing = false;
        },
        setupFn,
        () => isInitializing,
        () => isInitializing = true,
      ).catchError((e, st) {
        // Log error and attempt to send error message to main thread
        print('Web worker error: $e\n$st');
        try {
          _postMessage({
            'type': 'error',
            'error': '$e',
            'stackTrace': '$st',
          }.jsify());
        } catch (_) {
          // If even error reporting fails, just log
          print('Failed to send error to main thread');
        }
      });
    }).toJS,
  );
}

/// Handle a worker message asynchronously.
///
/// Uses callbacks to access and update context to avoid mutable closure variables.
Future<void> _handleWorkerMessage(
  Map<String, dynamic> data,
  WorkerContext? Function() getContext,
  void Function(WorkerContext) setContext,
  EngineParamsFactory engineParamsFactory,
  bool Function() isInitializing,
  void Function() markInitializing,
) async {
  final context = getContext();

  if (context == null) {
    // Prevent concurrent initialization
    if (isInitializing()) {
      print('Warning: Received setup message while already initializing');
      return;
    }
    markInitializing();

    try {
      // First message must be SetupRequest
      final setupRequest = SetupRequest.fromJson(data);
      final config = SyncEngineConfig.fromJson(setupRequest.config);

      // Create WorkerChannel for app-specific messages
      final channel = WorkerChannel((message) {
        _postMessage({'__channel': true, 'data': message}.jsify());
      });

      // Create WorkerContext
      final newContext = WorkerContext(WebWorkerSender(), channel);

      // Initialize sync system
      final engineParams = await engineParamsFactory(config, newContext);
      final syncSystem = await SyncEngine.createForParams(
          params: engineParams, config: config);
      newContext.setSyncSystem(syncSystem);

      // Store context before sending success response
      setContext(newContext);

      newContext.sendMessage(
        SetupResponse(setupRequest.requestId, success: true),
      );

      // Send 'ready' signal to main thread
      _postMessage('ready'.toJS);
    } catch (e, st) {
      // Create temporary context for error response
      final channel = WorkerChannel((message) {
        _postMessage({'__channel': true, 'data': message}.jsify());
      });
      final tempContext = WorkerContext(WebWorkerSender(), channel);
      tempContext.sendMessage(SetupResponse(
        data['requestId'] as String? ?? 'unknown',
        success: false,
        error: 'Setup failed: $e\n$st',
      ));
      // Don't set context on failure
      markInitializing(); // Reset flag
    }
  } else {
    // Worker is initialized - handle messages
    try {
      // Check if it's a channel message
      if (data['__channel'] == true) {
        context.channel.deliver(data['data']);
      } else {
        // Framework message - handle normally
        await context.handleMessage(data);
      }
    } catch (e, st) {
      // Log but don't crash worker
      print('Error handling message: $e\n$st');
      rethrow; // Propagate to outer catchError
    }
  }
}
