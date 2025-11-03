/// Stub for web worker entry point (used on non-web platforms).
library;

import 'package:logging/logging.dart';

import 'locorda_worker.dart';

final _log = Logger('web_worker_entry_point_stub');

/// Stub implementation that throws on non-web platforms.
void startWebWorkerLoop(EngineParamsFactory setupFn) {
  _log.info('In stub startWebWorkerLoop - throwing UnsupportedError');
  throw UnsupportedError('Web workers are only supported on web platform');
}
