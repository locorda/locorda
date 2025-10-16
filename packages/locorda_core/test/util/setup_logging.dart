import 'dart:async';

import 'package:logging/logging.dart';

StreamSubscription<LogRecord>? subscription;

void setupTestLogging([Level level = Level.WARNING]) {
  Logger.root.level = level;
  if (subscription != null) {
    return;
  }
  subscription = Logger.root.onRecord.listen((record) {
    // ignore: avoid_print
    print('${record.level.name}: ${record.time}: ${record.message}');
    if (record.error != null) {
      // ignore: avoid_print
      print('Error: ${record.error}');
    }
    if (record.stackTrace != null) {
      // ignore: avoid_print
      print('Stack trace:\n${record.stackTrace}');
    }
  });
}
