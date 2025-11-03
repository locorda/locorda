/// Pure Dart implementation of Drift native options receiver.
///
/// Shared by both drift_native_options_connector_worker.dart (exported via worker.dart)
/// and drift_native_options_connector.dart (main thread can also call receiver).
///
/// This file has no Flutter dependencies and can be used in web workers.
library;

import 'dart:async';

import 'package:locorda_drift/locorda_drift.dart';
import 'package:locorda_worker/locorda_worker.dart';

// No-Op implementation for web:
class DriftNativeOptionsReceiver {
  static Future<LocordaDriftNativeOptions> receiver(
    WorkerContext context, {
    Duration timeout = const Duration(seconds: 5),
  }) =>
      Future.value(LocordaDriftNativeOptions());
}
