/// Stub for web worker entry point (used on non-web platforms).
library;

import 'worker_handle.dart';

/// Stub implementation that throws on non-web platforms.
void startWebWorkerLoop(SyncEngineFactory setupFn) {
  throw UnsupportedError('Web workers are only supported on web platform');
}
