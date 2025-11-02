/// Build-time transformations for Locorda applications.
///
/// Provides builders for:
/// - **WebWorkerBuilder**: Compiles `lib/worker.dart` to `web/worker.dart.js`
///
/// ## Usage
///
/// Add to your `pubspec.yaml`:
///
/// ```yaml
/// dev_dependencies:
///   locorda_builder: ^0.1.0
///   build_runner: ^2.4.0
/// ```
///
/// The builder is automatically applied to projects that depend on `locorda_builder`.
///
/// Run `dart run build_runner build` or use watch mode during development:
/// `dart run build_runner watch`
///
/// ## Convention over Configuration
///
/// - Worker source: `lib/worker.dart`
/// - Output: `web/worker.dart.js`
/// - No additional configuration needed
///
/// ## Web Assets
///
/// For web platform, you need to manually provide:
/// - `web/sqlite3.wasm` - SQLite WebAssembly module
/// - `web/drift_worker.js` - Drift's web worker
///
/// Download from:
/// - https://github.com/simolus3/sqlite3.dart/releases/latest
/// - https://github.com/simolus3/drift/releases/latest
library;

export 'src/web_worker_builder.dart';
