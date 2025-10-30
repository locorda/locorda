/// Web (dart:html) implementation for worker creation.
///
/// Uses Web Worker API for worker thread on web platform.
library;

import 'dart:async';

import 'web_worker_handle.dart';
import 'worker_handle.dart';

Future<LocordaWorkerHandle> createImpl(
  EngineParamsFactory paramsFactory,
  String jsScript,
  String? debugName,
) {
  // paramsFactory is ignored on web - worker loads from JS file
  return WebWorkerHandle.create(jsScript, debugName);
}
