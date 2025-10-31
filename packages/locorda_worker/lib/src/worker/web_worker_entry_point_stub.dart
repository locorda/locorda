/// Stub for web worker entry point (used on non-web platforms).
library;

import 'locorda_worker.dart';

/// Stub implementation that throws on non-web platforms.
void startWebWorkerLoop(EngineParamsFactory setupFn) {
  throw UnsupportedError('Web workers are only supported on web platform');
}
