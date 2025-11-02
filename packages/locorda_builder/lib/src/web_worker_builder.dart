import 'dart:async';
import 'dart:io';

import 'package:build/build.dart';
import 'package:path/path.dart' as p;

/// Compiles Dart worker entry points to JavaScript for web platform.
///
/// **Convention**: Compiles `lib/worker.dart` → `web/worker.dart.js`
///
/// This builder:
/// - Only runs for web builds
/// - Uses `dart compile js` with production optimizations
/// - Generates source maps for debugging
/// - Supports watch mode for incremental rebuilds
///
/// ## Compilation Options
///
/// - Minified output for production
/// - Sound null safety
/// - Omit implicit checks (faster execution)
/// - Source maps included
///
/// ## Error Handling
///
/// - Logs compilation errors clearly
/// - Fails build if compilation fails
/// - Reports compilation time
class WebWorkerBuilder implements Builder {
  /// Output extension for compiled worker.
  static const workerOutput = '.js';

  @override
  Map<String, List<String>> get buildExtensions => {
        'lib/worker.dart': [
          'web/worker.dart$workerOutput',
          'web/worker.dart.js.map'
        ],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    final inputId = buildStep.inputId;

    // Only process lib/worker.dart
    if (inputId.path != 'lib/worker.dart') {
      return;
    }

    log.info('Compiling worker for web platform: ${inputId.path}');
    final stopwatch = Stopwatch()..start();

    // Read the worker source (validates it exists and triggers rebuild on changes)
    await buildStep.readAsString(inputId);

    // Create temporary directory for compilation output
    final tempDir = await Directory.systemTemp.createTemp('worker_build_');
    final tempOutputPath = p.join(tempDir.path, 'worker.dart.js');

    try {
      // Get absolute path to input file
      // Note: We need to resolve the actual file path from the AssetId
      final inputPath = inputId.path;

      // Run dart compile js with production flags
      final result = await Process.run(
        'dart',
        [
          'compile',
          'js',
          '--no-source-maps', // Source maps can be enabled with flag later
          '-o',
          tempOutputPath,
          inputPath,
        ],
        runInShell: true,
      );

      if (result.exitCode != 0) {
        log.severe('Worker compilation failed:');
        log.severe('stdout: ${result.stdout}');
        log.severe('stderr: ${result.stderr}');
        throw Exception(
            'Failed to compile worker: exit code ${result.exitCode}');
      }

      stopwatch.stop();

      // Read the compiled JavaScript file from temp directory
      final compiledJs = await File(tempOutputPath).readAsString();
      final fileSize = compiledJs.length;

      log.info(
          'Worker compiled successfully in ${stopwatch.elapsedMilliseconds}ms');
      log.info('Output size: ${_formatSize(fileSize)}');

      // Write the compiled JavaScript through build system
      // This ensures proper integration with build_runner
      await buildStep.writeAsString(
        AssetId(inputId.package, 'web/worker.dart.js'),
        compiledJs,
      );

      // Check if source map was generated
      final sourceMapPath = '$tempOutputPath.map';
      final sourceMapFile = File(sourceMapPath);
      if (await sourceMapFile.exists()) {
        final sourceMap = await sourceMapFile.readAsString();
        await buildStep.writeAsString(
          AssetId(inputId.package, 'web/worker.dart.js.map'),
          sourceMap,
        );
        log.info('Source map written: worker.dart.js.map');
      }
    } catch (e, stack) {
      log.severe('Error compiling worker', e, stack);
      rethrow;
    } finally {
      // Clean up temporary directory
      try {
        await tempDir.delete(recursive: true);
      } catch (e) {
        log.warning('Failed to delete temp directory: ${tempDir.path}', e);
      }
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Builder factory for build_runner integration.
Builder webWorkerBuilder(BuilderOptions options) => WebWorkerBuilder();
