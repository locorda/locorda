# Changelog

## 0.1.0-dev

- Initial release of the locorda_worker package
- Worker architecture for running SyncEngine in separate isolate/web worker
- ProxySyncEngine for transparent main thread ↔ worker communication
- Full SyncManager support (sync triggering, auto-sync, status streaming)
- Worker plugin system for cross-thread operations (e.g., authentication)
- Platform support: Native (Dart isolates) and Web (Web Workers)
- Message protocol with JSON serialization and Turtle-encoded RDF graphs
