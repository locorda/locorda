/// Native (dart:io) implementation for worker creation.
///
/// Uses Isolate.spawn for worker thread on native platforms (VM, AOT).
library;

import 'dart:async';

import 'native_worker_handle.dart';
import 'worker_handle.dart';

Future<LocordaWorkerHandle> createImpl(
  EngineParamsFactory paramsFactory,
  String jsScript,
  String? debugName,
) {
  // jsScript is ignored on native - only needed for web
  return NativeWorkerHandle.create(paramsFactory, debugName);
}
