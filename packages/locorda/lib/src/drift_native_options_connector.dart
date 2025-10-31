/// Connector for Drift native database options in worker architecture.
///
/// Uses Request/Response pattern to avoid race conditions with broadcast streams.
/// Worker requests paths when needed, main thread responds with resolved values.
library;

import 'dart:async';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:locorda_worker/locorda_worker.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';

final _log = Logger('DriftNativeOptionsConnector');

/// Response sent from main thread to worker with database paths.
class _ResponseDriftOptionsMessage {
  final String? databaseDirectory;
  final String? tempDirectoryPath;
  final String? databasePath;

  _ResponseDriftOptionsMessage({
    this.databaseDirectory,
    this.tempDirectoryPath,
    this.databasePath,
  });

  Map<String, dynamic> toJson() => {
        'type': 'ResponseDriftOptions',
        if (databaseDirectory != null) 'databaseDirectory': databaseDirectory,
        if (tempDirectoryPath != null) 'tempDirectoryPath': tempDirectoryPath,
        if (databasePath != null) 'databasePath': databasePath,
      };

  factory _ResponseDriftOptionsMessage.fromJson(Map<String, dynamic> json) {
    return _ResponseDriftOptionsMessage(
      databaseDirectory: json['databaseDirectory'] as String?,
      tempDirectoryPath: json['tempDirectoryPath'] as String?,
      databasePath: json['databasePath'] as String?,
    );
  }
}

/// Worker plugin that resolves database paths and sends them to worker.
///
/// This connector:
/// 1. Resolves database and temp directory paths in main thread
/// 2. Sends [_UpdateDriftOptionsMessage] to worker via [WorkerChannel]
/// 3. Worker uses these paths to configure [DriftNativeOptions]
///
/// ## Usage
///
/// Register as plugin during sync system setup:
///
/// ```dart
/// final sync = await Locorda.createWithWorker(
///   engineParamsFactory: createEngineParams,
///   jsScript: 'worker.dart.js',
///   plugins: [
///     DriftNativeOptionsConnector.sender(),
///   ],
///   // ... other config
/// );
/// ```
///
/// For testing or custom paths:
///
/// ```dart
/// plugins: [
///   DriftNativeOptionsConnector.sender(
///     databaseDirectory: () async => '/custom/db/path',
///     tempDirectoryPath: () async => '/custom/temp/path',
///   ),
/// ],
/// ```
///
/// In worker, create the storage:
///
/// ```dart
/// Future<EngineParams> createEngineParams(
///   SyncEngineConfig config,
///   WorkerContext context,
/// ) async {
///   final nativeOptions = await DriftNativeOptionsConnector.receiver(context);
///   final storage = DriftStorage(
///     web: DriftWebOptions(...),
///     native: nativeOptions,
///   );
///   // ... return EngineParams
/// }
/// ```
class DriftNativeOptionsConnector implements WorkerPlugin {
  final LocordaWorker _workerHandle;
  final Future<Object> Function()? _databaseDirectoryProvider;
  final Future<String?> Function()? _tempDirectoryPathProvider;
  final Future<String> Function()? _databasePathProvider;

  DriftNativeOptionsConnector._(
    this._workerHandle, {
    final Future<String> Function()? databasePath,
    Future<Object> Function()? databaseDirectory,
    Future<String?> Function()? tempDirectoryPath,
  })  : _databaseDirectoryProvider = databaseDirectory,
        _tempDirectoryPathProvider = tempDirectoryPath,
        _databasePathProvider = databasePath;

  /// Creates a plugin factory for this connector.
  ///
  /// The returned factory will be called by the worker framework with the [LocordaWorker].
  ///
  /// By default, uses [getApplicationDocumentsDirectory] and [getTemporaryDirectory].
  /// For testing or custom paths, provide custom provider functions.
  static WorkerPluginFactory sender({
    final Future<String> Function()? databasePath,
    final Future<Object> Function()? databaseDirectory,
    final Future<String?> Function()? tempDirectoryPath,
  }) {
    return (LocordaWorker workerHandle) {
      return DriftNativeOptionsConnector._(
        workerHandle,
        databasePath: databasePath,
        databaseDirectory: databaseDirectory,
        tempDirectoryPath: tempDirectoryPath,
      );
    };
  }

  /// Listens for path requests from worker and responds with resolved paths.
  ///
  /// Worker uses Request/Response pattern to avoid race conditions.
  @override
  Future<void> initialize() async {
    _log.info('Plugin initialized, listening for requests...');

    // Listen for requests from worker (filter __channel messages)
    _workerHandle.messages.listen((message) async {
      if (message is! Map<String, dynamic>) return;

      // Only process __channel messages
      if (message['__channel'] != true) return;

      final channelData = message['data'];
      _log.fine(
          'Received __channel message: ${channelData is Map ? channelData['type'] : channelData.runtimeType}');

      if (channelData is Map<String, dynamic> &&
          channelData['type'] == 'RequestDriftOptions') {
        _log.info('Processing RequestDriftOptions...');

        // Resolve paths when requested
        final databasePath = _databasePathProvider != null
            ? await _databasePathProvider()
            : null;
        _log.fine('Database path: $databasePath');

        // Resolve database directory (default: application documents)
        final databaseDir = databasePath != null
            ? null
            : (_databaseDirectoryProvider != null
                ? await _databaseDirectoryProvider()
                : (await getApplicationDocumentsDirectory()).path);
        _log.fine('Database directory: $databaseDir');

        // Resolve temp directory (default: system temp)
        final tempDir = _tempDirectoryPathProvider != null
            ? await _tempDirectoryPathProvider()
            : (await getTemporaryDirectory()).path;
        _log.fine('Temp directory: $tempDir');

        // Send response back to worker
        final response = _ResponseDriftOptionsMessage(
          databaseDirectory: switch (databaseDir) {
            String s => s,
            _ => databaseDir?.toString(),
          },
          tempDirectoryPath: tempDir,
          databasePath: databasePath,
        );

        _log.info('Sending response via __channel: ${response.toJson()}');
        _workerHandle.sendMessage({
          '__channel': true,
          'data': response.toJson(),
        });
        _log.info('Response sent successfully');
      }
    });
  }

  /// No cleanup needed.
  @override
  Future<void> dispose() async {
    // Nothing to clean up
  }

  /// Creates DriftNativeOptions provider for worker context.
  ///
  /// Uses Request/Response pattern: Worker sends request to main thread,
  /// which resolves paths and responds. This avoids race conditions with
  /// broadcast streams.
  ///
  /// Throws [TimeoutException] after 5 seconds if no response is received,
  /// with helpful error message about missing plugin registration.
  ///
  /// Example:
  /// ```dart
  /// Future<EngineParams> createEngineParams(
  ///   SyncEngineConfig config,
  ///   WorkerContext context,
  /// ) async {
  ///   final nativeOptions = await DriftNativeOptionsConnector.receiver(context);
  ///   return EngineParams(
  ///     storage: DriftStorage(native: nativeOptions),
  ///     // ...
  ///   );
  /// }
  /// ```
  static Future<DriftNativeOptions> receiver(
    WorkerContext context, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    _log.info('Worker: Starting provider...');

    final completer = Completer<DriftNativeOptions>();
    late final StreamSubscription subscription;

    // Listen for response from main thread via __channel
    subscription = context.channel.messages.listen((message) {
      _log.fine(
          'Worker: Received __channel message: ${message is Map ? message['type'] : message.runtimeType}');

      if (message is Map<String, dynamic> &&
          message['type'] == 'ResponseDriftOptions') {
        _log.info('Worker: Got ResponseDriftOptions from __channel!');

        final response = _ResponseDriftOptionsMessage.fromJson(message);
        _log.fine(
            'Worker: Parsed response: databaseDirectory=${response.databaseDirectory}, tempDirectory=${response.tempDirectoryPath}, databasePath=${response.databasePath}');

        final options = DriftNativeOptions(
          databaseDirectory: response.databaseDirectory != null
              ? () => Future.value(response.databaseDirectory)
              : null,
          tempDirectoryPath: response.tempDirectoryPath != null
              ? () => Future.value(response.tempDirectoryPath)
              : null,
          databasePath: response.databasePath != null
              ? () => Future.value(response.databasePath!)
              : null,
        );

        _log.info('Worker: Completing with DriftNativeOptions');
        completer.complete(options);
        subscription.cancel();
      }
    });

    // Send request to main thread via __channel
    _log.info('Worker: Sending RequestDriftOptions via __channel...');
    context.channel.send({'type': 'RequestDriftOptions'});
    _log.info('Worker: Request sent, waiting for response...');

    // Wait for response with timeout
    try {
      return await completer.future.timeout(
        timeout,
        onTimeout: () {
          subscription.cancel();
          throw TimeoutException(
            'DriftNativeOptionsConnector: No response received from main thread after ${timeout.inSeconds}s.\n'
            '\n'
            'Did you forget to register the plugin?\n'
            '\n'
            'Add this to your Locorda.createWithWorker() call:\n'
            '  plugins: [\n'
            '    DriftNativeOptionsConnector.sender(),\n'
            '  ],\n',
          );
        },
      );
    } catch (e) {
      subscription.cancel();
      rethrow;
    }
  }
}
