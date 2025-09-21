# Future Topics and Open Questions

This document tracks substantial topics identified for future discussion and potential implementation. Topics are organized by implementation timeline to provide clear guidance for development planning.

---

# Version 1 (v1) - Critical Requirements

These topics must be completed for v1 release. They represent essential functionality gaps that prevent production readiness.

## 1. Extended CRDT Algorithm and RDF Structure Support

**Priority**: Critical for v1 Release  
**Current Gap**: Framework focuses on basic property-level CRDTs but requires additional algorithms and RDF structure support for production readiness.

**CRDT Algorithms to Evaluate for v1**:
- **Counter algorithms (G-Counter, PN-Counter)**: For numeric aggregation and collaborative counting use cases
- **Sequence algorithms (RGA, Fractional Indexing)**: For ordered collections and collaborative text editing  
- **Advanced set and map variants (LWW-Map, OR-Map)**: For specialized dictionary use cases
- **Multi-Value Registers (MV-Register)**: For preserving concurrent writes
- **Trees**: Hierarchical data structures (taxonomies, organizational charts)

**RDF Structures to Address Before v1**:
- **rdf:List**: Position-based vs content-based conflict resolution for ordered lists
- **rdf:Seq/rdf:Bag/rdf:Alt**: Merge semantics for RDF container types
- **Complex Blank Node Graphs**: Interdependent blank nodes (building on solved context-based identification)
- **Property Paths**: Multi-hop relationships and their CRDT implications
- **Reification Chains**: Nested reified statements and metadata

**Architecture Assessment**: Current infrastructure (Hybrid Logical Clocks, blank node identification via context, merge contracts) should accommodate most extensions. Sequence algorithms may require positional metadata extensions.

**Implementation Strategy**: These should integrate within existing framework without fundamental architectural changes.

---

## 2. Framework Version Compatibility Strategy

**Priority**: Critical for v1 Release  
**Core Issue**: What happens when different versions of the framework try to collaborate in the same Pod?

**Key Decisions Needed**:
- **Installation Version Declaration**: How installations declare their framework version for compatibility checking
- **Version Mismatch Handling**: Graceful fallbacks when incompatible versions encounter each other  
- **Migration Path**: Basic strategy for evolving formats (RDF reification, index structures, merge contracts) without breaking existing collaborations

**v1 Scope**: Define minimum viable compatibility strategy - not full migration automation, but clear policies for version conflicts and a path forward for format evolution.

**Implementation Strategy**: Build on existing installation document infrastructure to add version metadata and basic compatibility checks.

---

## 3. Permanent IRI Strategy ✅ COMPLETED

**Priority**: ~~Critical for v1 Release~~ **RESOLVED**  
**Status**: Successfully implemented W3ID.org permanent identifier service integration.

**Implemented Solution**: W3ID.org Permanent Identifier Service
- **Final IRIs**: `w3id.org/solid-crdt-sync/vocab/` and `w3id.org/solid-crdt-sync/mappings/`
- **Benefits Realized**: Permanent identifiers with no maintenance burden, academic backing, designed specifically for this use case
- **External Dependency**: Managed through W3ID.org redirect service

**Completed Implementation**:
- ✅ **Vocabulary IRIs**: Permanent identifiers established for `crdt:`, `algo:`, `sync:`, `idx:`, and `mc:` vocabularies
- ✅ **Mapping IRIs**: Stable base for merge contract mappings (`core-v1.ttl`, etc.)
- ✅ **Migration Completed**: All RDF files, examples, and generated code updated to use W3ID.org IRIs
- ✅ **Documentation Updated**: Examples and specifications reflect final IRI decisions

**Related**: All vocabulary files in `vocabularies/` directory and mapping files in `mappings/` directory now use permanent W3ID.org identifiers.

---

# Version 2+ (Future Research and Enhancements)

These topics represent interesting research directions and framework improvements to explore after v1 is completed. Priority and timeline will be determined based on practical needs and research outcomes.

---

## 1. End-to-End Encryption Support

**Status**: Future Research (v2+)
**Current Limitation**: Framework provides offline-first functionality and user-controlled storage but lacks end-to-end encryption (E2EE), which is essential for true local-first privacy guarantees.

**Technical Challenge**:
Implementing E2EE while maintaining RDF semantic interoperability and CRDT merge capabilities presents several design challenges:
- **RDF Query Compatibility**: Encrypted RDF cannot be semantically queried or reasoned over
- **CRDT Merge Operations**: Conflict resolution requires access to plaintext data structures
- **Index Generation**: Sharded indices require plaintext access for semantic grouping and performance optimization
- **Cross-Application Interoperability**: Encrypted data cannot be shared between applications without key sharing

**Potential Approaches**:
1. **Hybrid Architecture**: Store encrypted application data with plaintext metadata for indexing and CRDT operations
2. **Client-Side Decryption**: Decrypt data locally for CRDT operations, re-encrypt for storage
3. **Homomorphic Operations**: Limited CRDT algorithms that support encrypted operations (research area)
4. **Layered Encryption**: Different encryption levels for different data sensitivity levels

**Related Work**:
- **[ANUSII](https://anusii.com/)** approaches to E2EE RDF data
- Academic research on encrypted CRDT operations
- **[Solid OIDC](https://solid.github.io/solid-oidc/)** integration for key management

**Architecture Impact**: E2EE support would require significant extensions to the current 4-layer architecture, particularly affecting the indexing layer and merge contract semantics.

---

## 2. Non-RDF Binary File Support

**Status**: Future Research (v2+)
**Current Limitation**: Framework focuses exclusively on RDF data synchronization but doesn't address binary files (images, documents, media) that applications often need to store and sync alongside structured data.

**Use Case Scenarios**:
- **Photo Management App**: Store image metadata as RDF while managing binary image files
- **Document Collaboration**: Sync PDF/Word documents with RDF annotations and version metadata
- **Media Applications**: Manage audio/video files with RDF-based playlists and metadata

**Technical Challenges**:
- **Binary File Versioning**: CRDTs work with structured data; binary files need different conflict resolution strategies
- **Storage Efficiency**: Large binary files require different sync strategies than small RDF documents
- **Reference Integrity**: Maintaining consistency between RDF references and binary file availability
- **Bandwidth Management**: Selective sync for large files vs always-sync for RDF metadata

**Potential Approaches**:
1. **Content-Addressed Storage**: Use hash-based addressing for immutable binary files with RDF metadata
2. **Layered Sync Strategy**: Fast RDF sync with optional binary file sync based on application needs
3. **External Storage Integration**: RDF references to files stored in specialized binary storage services
4. **Version-Controlled Files**: Git-LFS-like approach with RDF-tracked versions and metadata

**Architecture Considerations**:
- Binary files likely need separate storage patterns from RDF sharding strategies
- Application-level policies for bandwidth and storage management
- Integration with existing file storage APIs (cloud storage, CDNs)

**Related Standards**:
- **[Linked Data Platform (LDP)](https://www.w3.org/TR/ldp/)** binary resource handling
- **[IPFS](https://ipfs.io/)** content-addressing approaches
- Solid Protocol non-RDF resource management patterns

---

## 3. Multi-Pod Application Integration

**Status**: Future Research
**Current Limitation**: Framework focuses on single-Pod CRDT synchronization but doesn't address applications that need to integrate data from multiple Pods, including Pods not owned by the user.

**Use Case Scenario:**
Alice's Recipe Manager app wants to display:
- Alice's personal recipes from `https://alice.pod/data/recipes/`
- Bob's shared recipes from `https://bob.pod/data/recipes/` 
- Carol's family recipes from `https://carol.pod/data/family-recipes/`
- Community recipes from `https://community-pod.org/recipes/`

**Technical Integration Challenges:**

**Discovery and Connection Management:**
- How do applications discover relevant Pods containing related data?
- Managing authentication/authorization across multiple independent Pods
- Handling different availability and connectivity states per Pod
- Coordinating sync processes across multiple concurrent Pod connections

**Resource Identity and Semantic Relationships:**
- IRIs are globally unique (no conflicts), but semantic relationships are complex
- Cross-Pod resource references: `owl:sameAs`, `schema:isVariantOf`, custom relationships
- Determining when resources from different Pods represent the same conceptual entity
- Handling conflicting semantic assertions across Pods (Alice says X, Bob says Y about same topic)

**Index and Query Coordination:**
- Should applications create separate indices per Pod or attempt federation?
- Cross-Pod search and discovery: querying multiple Pod indices efficiently
- Handling different indexing patterns and schema versions across Pods
- Performance implications of distributed query execution

**Synchronization Architecture:**
- Managing multiple independent sync processes without interference
- Batch operations and consistency across Pod boundaries
- Handling partial failures when some Pods are unavailable
- Cache coordination and invalidation across multiple data sources

**User Experience Challenges:**
- Presenting unified views of distributed data with clear source attribution
- Handling permission differences across Pods in consistent UI
- Conflict resolution when related data from different Pods disagrees
- Offline/online state management for multiple connection states

**Schema Evolution Across Pods:**
- Different Pods may use different framework versions or merge contracts
- Handling schema compatibility in federated scenarios  
- Migration coordination when not all Pods upgrade simultaneously
- Graceful degradation when encountering incompatible schemas

**Application Architecture Patterns:**

**Federated Query Pattern:**
- Applications maintain separate sync state per Pod
- Cross-Pod queries executed as distributed operations
- UI aggregates results with clear source provenance

**Local Integration Pattern:**
- Applications sync data from multiple Pods into unified local store
- Semantic relationship resolution happens locally
- Trade-offs between storage overhead and query performance

**Hybrid Pattern:**
- Critical data synced locally, secondary data queried on-demand
- Application-specific policies for what data to integrate vs. reference

**Open Design Questions:**
- Should the framework provide multi-Pod orchestration primitives?
- How to handle semantic conflicts across Pod boundaries?
- What's the role of the framework vs. application-specific integration logic?
- Should there be standard vocabularies for cross-Pod relationships?
- How to balance performance, consistency, and user experience?

**Implementation Scope:**
This represents a major expansion beyond single-Pod CRDT synchronization into distributed application orchestration, semantic web integration, and multi-source data management. Likely requires significant framework extensions and new architectural patterns.

**Related**: Builds on all current framework concepts but extends them into distributed, multi-authority scenarios that go beyond the current single-Pod collaborative model.

## 4. Custom Tombstone Format Optimization

**Status**: Future Research  
**Current Approach**: Uses RDF Reification for semantic correctness but with significant overhead.

**Alternative Approaches**:
- **Custom Compact Format**: Define framework-specific tombstone representation

**Trade-offs to Analyze**:
- Semantic correctness vs storage efficiency
- Interoperability vs performance
- Standard RDF tooling compatibility vs custom processing requirements

**Related**: Current RDF Reification approach in CRDT-SPECIFICATION.md sections 3.2, 3.3

---

## 5. Provenance and Audit Trail Support

**Status**: Future Research  
**Problem**: Framework tracks basic causality through Hybrid Logical Clocks but doesn't provide rich provenance information for auditing and compliance needs.

**Core Questions**:
- **Provenance granularity**: Should tracking focus on installations, users, processes, or individual operations?
- **Storage trade-offs**: How much provenance overhead is acceptable for different use cases?
- **Privacy considerations**: How to balance audit requirements with user privacy?
- **Integration approach**: Should provenance extend existing causality tracking or operate separately?

**Use Cases to Consider**:
- Compliance auditing requiring detailed change history
- Debugging collaborative workflows and conflict resolution
- Business process analysis and optimization
- Trust and transparency in multi-party collaboration

**Design Considerations**:
- Different provenance standards (PROV-O, custom vocabularies) have different capabilities
- Provenance information may need different retention policies than data
- Cross-installation provenance requires coordination and trust mechanisms
- Integration with existing Hybrid Logical Clock system for consistency

**Related**: Hybrid Logical Clock mechanics in ARCHITECTURE.md Section 5.2.3 and CRDT-SPECIFICATION.md.

---

## 6. Legacy Data Import (Optional Extension)

**Status**: Future Research  
**Problem**: Framework requires new data to be CRDT-managed from creation, but many users have existing Solid data.

**Core Challenge**: How to bring existing traditional Solid data into framework management without breaking existing workflows or data integrity?

**Key Design Questions**:
- **Discovery approach**: How to identify existing resources suitable for import?
- **Data preservation**: Should imports create copies, wrappers, or migrate in-place?
- **Relationship handling**: How to maintain references between imported and existing resources?
- **User control**: What level of granular selection and rollback should be provided?
- **Schema compatibility**: How to handle traditional RDF that doesn't map cleanly to CRDT semantics?

**Potential Approaches**:
- **Wrapper strategy**: Create managed documents that reference originals
- **Migration strategy**: Convert traditional resources to CRDT format
- **Hybrid strategy**: Copy frequently-edited data, reference read-only data

**Related**: Integration with Type Index discovery patterns in ARCHITECTURE.md sections 4.4 and 6.1.

---

## 7. Proactive Access Control Integration

**Status**: Future Research  
**Problem**: Framework assumes access control is handled externally, but production systems may need proactive permission checking to improve user experience.

**Core Questions**:
- **Integration depth**: Should the framework check permissions before attempting operations, or handle failures gracefully?
- **Permission discovery**: How can applications efficiently determine what resources are accessible?
- **Sync behavior**: When encountering access restrictions, should sync skip resources, fail entirely, or provide partial results?
- **Performance trade-offs**: What's the cost of permission checking vs. handling failed operations?

**Design Considerations**:
- Multiple access control systems (WAC, ACP, custom) may need support
- Caching strategies for permission information to minimize overhead
- Graceful degradation when permissions change during sync operations
- Integration with existing error handling and retry mechanisms

**Related**: Error handling patterns in ERROR-HANDLING.md and sync workflow in ARCHITECTURE.md Chapter 7.

---

## 8. Data Validation Integration

**Status**: Future Research  
**Problem**: Framework performs CRDT merge operations without semantic validation, potentially allowing invalid data states.

**Core Questions**:
- **Validation timing**: Should validation happen before merge, after merge, or both?
- **Failure handling**: When validation fails, should operations be blocked, flagged, or logged?
- **Validation scope**: Should validation apply to individual properties, complete resources, or cross-resource relationships?
- **Performance impact**: How to balance data quality with sync performance?

**Design Considerations**:
- Different validation technologies (SHACL, custom rules, application logic) have different trade-offs
- Validation conflicts between installations may require consensus mechanisms
- Schema evolution must account for validation rule changes over time
- Integration with merge contract system for consistent validation policies

**Open Approaches**:
- Pre-merge validation to prevent invalid merges
- Post-merge validation with rollback capabilities
- Progressive validation during resource access
- Hybrid approaches with different strictness levels

**Related**: Merge contract fundamentals in ARCHITECTURE.md Section 5.2 and error handling in ERROR-HANDLING.md.

---

## 9. Private Type Index Support

**Status**: Future Research (Low Priority)  
**Current Approach**: Framework uses only the Public Type Index, making all CRDT-managed resources discoverable by other applications.

**Core Questions**:
- **Policy decisions**: Should applications default to public or private Type Index registration for CRDT resources?
- **User control**: How should users control which resource types are registered privately vs. publicly?
- **Setup UX**: Should apps suggest privacy settings during setup, or should this be a user-driven decision?
- **Discovery implications**: How do applications handle mixed public/private resource scenarios?

**Use Cases**:
- Personal data not intended for collaboration (private journals, notes)
- Development/testing resources separate from production data
- Business data requiring access control but still needing CRDT capabilities

**Design Considerations**:
- Solid provides both Public and Private Type Index documents with different access controls
- Registration in Private Type Index requires the application to have privileged access
- Migration between public/private registration may be needed as resource usage evolves
- Mixed visibility scenarios require clear policies for collaboration boundaries

**Related**: Current Public Type Index usage in ARCHITECTURE.md section 4.2


---

# Summary and Planning

## Implementation Priority Overview

**v1 Critical Requirements (2 remaining topics)**:
1. Extended CRDT Algorithm and RDF Structure Support
2. Framework Version Compatibility Strategy
3. ~~Permanent IRI Strategy~~ ✅ **COMPLETED**

**v2+ Future Research (9 topics)**:

1. End-to-End Encryption Support
2. Non-RDF Binary File Support
3. Multi-Pod Application Integration
4. Custom Tombstone Format Optimization
5. Provenance and Audit Trail Support
6. Legacy Data Import
7. Proactive Access Control Integration
8. Data Validation Integration
9. Private Type Index Support

---

## Contributing to Future Topics

When identifying new topics:
1. **Clearly describe the current limitation or opportunity**
2. **Outline potential approaches or solutions** 
3. **Identify trade-offs and risks that need discussion**
4. **Reference related sections in existing specifications**
5. **Assign appropriate version target (v1/v2/v3+)**

Topics graduate to active development when:
- Problem scope is well-defined
- Solution approaches are compared
- Implementation plan is developed
- Backwards compatibility is addressed
- Version timeline is confirmed