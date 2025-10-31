/// Native platform implementation using Dart isolates.
library;

// This file is conditionally imported by worker_handle.dart

import 'dart:async';

import 'package:locorda_core/locorda_core.dart';

import 'native_worker_handle.dart';
import 'locorda_worker.dart';

Future<LocordaWorker> createImpl(
  EngineParamsFactory engineParamsFactory,
  SyncEngineConfig config,
  String jsScript,
  String? debugName,
  Future<void> Function(LocordaWorker handle) initializePlugins, {
  void workerInitializer()?,
}) {
  // jsScript is ignored on native - only needed for web
  return NativeWorkerHandle.create(
    engineParamsFactory,
    config.toJson(),
    debugName,
    initializePlugins,
    workerInitializer: workerInitializer,
  );
}
