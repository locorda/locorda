import 'package:logging/logging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_notes_app/utils/logging_setup.dart';

void main() {
  group('setupConsoleLogging', () {
    setUp(() {
      // Clear any existing handlers
      Logger.root.clearListeners();
      Logger.root.level = Level.ALL;
    });

    tearDown(() {
      // Clean up
      Logger.root.clearListeners();
    });

    test('should configure Logger.root with specified level', () {
      setupConsoleLogging(level: Level.WARNING);

      expect(Logger.root.level, Level.WARNING);
    });

    test('should default to INFO level', () {
      setupConsoleLogging();

      expect(Logger.root.level, Level.INFO);
    });

    test('should handle log records without throwing', () {
      setupConsoleLogging();

      final logger = Logger('test');

      // Should not throw
      expect(() => logger.info('Test message'), returnsNormally);
      expect(() => logger.warning('Warning message'), returnsNormally);
      expect(() => logger.severe('Error message', 'error'), returnsNormally);
    });

    test('should support multiple timestamp formats', () {
      // Should not throw for any format
      expect(
        () => setupConsoleLogging(timestampFormat: TimestampFormat.none),
        returnsNormally,
      );
      expect(
        () => setupConsoleLogging(timestampFormat: TimestampFormat.short),
        returnsNormally,
      );
      expect(
        () => setupConsoleLogging(timestampFormat: TimestampFormat.full),
        returnsNormally,
      );
    });

    test('should support multiple log formats', () {
      // Should not throw for any format
      expect(
        () => setupConsoleLogging(format: LogFormat.colored),
        returnsNormally,
      );
      expect(
        () => setupConsoleLogging(format: LogFormat.plain),
        returnsNormally,
      );
    });

    test('should handle stack traces without throwing', () {
      setupConsoleLogging();

      final logger = Logger('test');

      expect(
        () => logger.severe(
          'Error with stack trace',
          'error object',
          StackTrace.current,
        ),
        returnsNormally,
      );
    });

    test('can be called multiple times (replaces previous setup)', () {
      setupConsoleLogging(level: Level.INFO);
      setupConsoleLogging(level: Level.WARNING);

      // Last call wins
      expect(Logger.root.level, Level.WARNING);
    });
  });
}
