# Locorda - Documentation Index

**Locorda: Sync offline-first apps using your user's remote storage**

**Version:** 0.10.0-draft
**Last Updated:** September 2025
**Status:** Documentation Index
**Authors:** Klas Kalaß

## Document Status

**IMPORTANT:** This document has been split into separate specifications for better modularity and backend independence. Please refer to the appropriate document below for current specifications.

## Document Changelog

### Version 0.10.0-draft (September 2025)
- **MAJOR ARCHITECTURAL CHANGE:** Split monolithic specification into backend-agnostic core and backend-specific implementations
- **System Generalization:** Renamed from "Solid-specific" to "locorda" (Passive Storage Collaborative RDF Sync System) supporting multiple storage backends
- **New Document Structure:**
  - [locorda-SPECIFICATION.md](locorda-SPECIFICATION.md): locorda core specification
  - [locorda-SOLID-BACKEND.md](locorda-SOLID-BACKEND.md): locorda Solid Pod implementation
  - ARCHITECTURE.md: Documentation index and navigation (this document)
- **Backend Abstraction:** Defined backend interface requirements for resource discovery, storage operations, and authentication
- **Maintained Compatibility:** All existing Solid functionality preserved in Solid backend specification
- **Future Extensibility:** Architecture now supports Google Drive, AWS S3, and other storage backends

### Previous Versions
For historical changelog entries, see git history or the individual specification documents.

## Documentation Structure

### Core Framework (Backend-Agnostic)

**[locorda-SPECIFICATION.md](locorda-SPECIFICATION.md)** - The complete locorda core specification
- 4-layer architecture: Data Resource, Merge Contract, Indexing, Sync Strategy
- CRDT algorithms and conflict resolution
- Backend abstraction interfaces
- Performance optimization through sharding
- Error handling and resilience patterns

**Target Audience:** Library implementers, distributed RDF system architects, backend developers

### Backend Implementations

**[locorda-SOLID-BACKEND.md](locorda-SOLID-BACKEND.md)** - locorda Solid Pod backend implementation
- Solid Type Index integration for discovery isolation
- Solid-OIDC authentication implementation
- HTTP-based storage with ETag optimization
- ACL/ACP access control patterns
- Pod setup and configuration workflows

**Target Audience:** Solid application developers, Pod providers

### Future Backend Specifications

Additional backend specifications may be added as implementations are developed:
- Google Drive Backend Specification
- AWS S3 Backend Specification
- Local Filesystem Backend Specification

## Quick Start Guide

1. **For Application Developers:** Start with [locorda-SPECIFICATION.md](locorda-SPECIFICATION.md) to understand the core concepts, then refer to your specific backend specification.

2. **For Library Implementers:** Read the complete [locorda-SPECIFICATION.md](locorda-SPECIFICATION.md) specification, focusing on the backend abstraction interfaces in Section 4.4.

3. **For Solid Developers:** Read [locorda-SPECIFICATION.md](locorda-SPECIFICATION.md) for foundations, then implement using [locorda-SOLID-BACKEND.md](locorda-SOLID-BACKEND.md).

