/// Offline-first CRDT synchronization with Solid Pods.
///
/// This is the main entry point package that provides documentation,
/// examples, and convenient access to the locorda ecosystem.
///
/// ## Quick Start
///
/// ```dart
/// import 'package:locorda/locorda.dart';
/// import 'package:locorda_drift/locorda_drift.dart';
///
/// // Set up offline-first sync system
/// final storage = DriftStorage(path: 'app.db');
/// final sync = await LocordaSync.setup(storage: storage);
///
/// // Use your annotated models
/// final note = Note(
///   id: 'note-1',
///   title: 'My first note',
///   content: 'Offline-first with optional Solid sync!',
/// );
///
/// await sync.save(note);
/// final notes = await sync.getAll<Note>();
///
/// // Optionally connect to Solid Pod
/// final auth = SolidAuthProvider(/* config */);
/// await sync.connectToSolid(auth);
/// await sync.sync(); // Sync to pod
/// ```
///
/// ## Package Architecture
///
/// - `locorda_core` - Core sync engine and interfaces
/// - `locorda_annotations` - CRDT merge strategy annotations
/// - `locorda_drift` - SQLite storage backend
/// - `locorda_solid_auth` - Solid authentication
/// - `locorda_solid_ui` - Flutter UI components
library locorda;

// Re-export the main API from core
export 'src/config/sync_config.dart';
export 'src/locorda_sync.dart' show LocordaSync, TypedHydrationBatch;
