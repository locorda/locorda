# locorda Solid Backend Specification

**Version:** 0.10.0-draft
**Last Updated:** September 2025
**Status:** Draft Specification
**Authors:** Klas Kalaß
**Target Audience:** Library implementers integrating with Solid Pods

## Document Status

This document specifies how locorda integrates with Solid Pods as a storage backend. It covers discovery mechanisms, Type Index integration, and Solid-specific protocols that enable locorda to work within the Solid ecosystem.

This is a **draft specification** under active development. The implementation details described here are subject to change based on implementation experience and community feedback.

**Companion Document:** This specification should be read alongside [locorda-SPECIFICATION.md](locorda-SPECIFICATION.md), which covers the core framework architecture independent of any specific storage backend.

## Document Changelog

### Version 0.10.0-draft (September 2025)
- **BREAKING CHANGE:** Replace xxHash64 with MD5 for cross-platform compatibility
  - Updated hash algorithm from xxHash64 to MD5 throughout specification
  - Modified hash output format: 16 hex chars → 32 hex chars
  - Updated shard naming: `shard-mod-xxhash64-*` → `shard-mod-md5-*`
  - Changed group key safety format: `{length}_{16-char-hash}` → `{length}_{32-char-hash}`
  - Ensures JavaScript/web compatibility while maintaining deterministic hashing
- Updated vocabularies, templates, and implementation to use MD5
- All examples and documentation reflect new hash format

### Version 0.9.0-draft (September 2025)
- Initial Solid backend specification
- Discovery isolation strategy for CRDT-managed resources
- Type Index integration patterns
- Solid WebID and authentication requirements
- Pod setup and configuration procedures

---

## 1. Solid Integration Overview

### 1.1. Solid as Passive Storage

In the locorda architecture, Solid Pods serve as **passive storage backends**. This means:

- All CRDT logic resides in client-side libraries
- Pods provide simple HTTP-based read/write access to RDF documents
- No server-side coordination or conflict resolution occurs
- Authentication and authorization follow standard Solid patterns

### 1.2. Discovery Isolation Strategy

CRDT-managed resources contain synchronization metadata and follow structural conventions that traditional RDF applications don't understand, creating a risk of data corruption. The Solid backend solves this problem through discovery isolation.

CRDT-enabled applications use a modified Solid discovery approach that provides controlled access to managed resources while protecting them from incompatible applications. This isolation strategy prevents data corruption while maintaining standard Solid discoverability principles.

#### 1.2.1. The Challenge

Traditional Solid discovery would expose CRDT-managed data to all applications, risking corruption by applications that don't understand CRDT metadata or Hybrid Logical Clocks.

#### 1.2.2. The Solution

CRDT-managed resources are registered under `sync:ManagedDocument` in the Type Index rather than their semantic types (e.g., `schema:Recipe`). The semantic type is preserved via `sync:managedResourceType` property.

**Discovery Behavior:**
- **CRDT-enabled apps:** Query for `sync:ManagedDocument` where `sync:managedResourceType schema:Recipe` → Find managed resources
- **Traditional apps:** Query for `schema:Recipe` → Find nothing (managed data invisible)
- **Legacy data:** Remains discoverable through traditional registrations until explicitly migrated

This creates clean separation: compatible applications collaborate safely on managed data, while traditional apps work with unmanaged data, preventing cross-contamination.

### 1.3. Current Scope and Limitations

**Single-Pod Focus:** This backend specification is designed for CRDT synchronization within a single Solid Pod. All collaborating installations work with data stored in one Pod, with multiple users (WebIDs) able to participate through separate installations.

**Multi-Pod Integration Limitation:** Applications requiring data integration across multiple Pods (such as displaying Alice's recipes from `https://alice.pod/` alongside Bob's recipes from `https://bob.pod/`) need additional orchestration beyond this specification. While IRIs ensure global uniqueness across Pods, the challenges include:
- Discovery and connection management across multiple Pods
- Semantic relationship resolution across Pod boundaries
- Cross-Pod query coordination and performance optimization
- Multi-source synchronization architecture and user experience

**Future Evolution:** Multi-Pod application integration represents a significant architectural enhancement planned for future specification versions (v2/v3). See FUTURE-TOPICS.md Section 10 for detailed analysis of the challenges and potential approaches.

## 2. Solid Discovery Integration

### 2.1. Managed Resource Discovery Protocol

1. **Standard Discovery:** Follow WebID → Profile Document → Public Type Index ([Type Index](https://github.com/solid/type-indexes)):

**Note:** This backend specification currently uses only the **Public Type Index** for discoverability. This design choice enables inter-application collaboration and resource sharing but means all CRDT-managed resources are discoverable by other applications. See [FUTURE-TOPICS.md](FUTURE-TOPICS.md) for planned Private Type Index support.

```turtle
# In Profile Document at https://alice.podprovider.org/profile/card#me
@prefix solid: <http://www.w3.org/ns/solid/terms#> .

<#me> solid:publicTypeIndex </settings/publicTypeIndex.ttl> .
```

2. **Framework Resource Resolution:** From the Type Index, resolve `sync:ManagedDocument` registrations to data containers:

```turtle
# In Public Type Index at https://alice.podprovider.org/settings/publicTypeIndex.ttl
@prefix sync: <https://w3id.org/solid-crdt-sync/vocab/sync#> .
@prefix solid: <http://www.w3.org/ns/solid/terms#> .
@prefix schema: <https://schema.org/> .
@prefix meal: <https://example.org/vocab/meal#> .

<> a solid:TypeIndex;
   solid:hasRegistration [
      a solid:TypeRegistration;
      solid:forClass sync:ManagedDocument;
      sync:managedResourceType schema:Recipe;
      solid:instanceContainer <../data/recipes/>
   ], [
      a solid:TypeRegistration;
      solid:forClass sync:ManagedDocument;
      sync:managedResourceType meal:ShoppingListEntry;
      solid:instanceContainer <../data/shopping-entries/>
   ] .
```

3. **Specification Type Resolution:** Applications also register specification-defined types (indices and client installations) in the Type Index using the same mechanism:

```turtle
# Also in Public Type Index at https://alice.podprovider.org/settings/publicTypeIndex.ttl
@prefix idx: <https://w3id.org/solid-crdt-sync/vocab/idx#> .
@prefix crdt: <https://w3id.org/solid-crdt-sync/vocab/crdt-mechanics#> .

<> solid:hasRegistration [
      a solid:TypeRegistration;
      solid:forClass idx:FullIndex;
      idx:indexesClass schema:Recipe
      solid:instanceContainer <../indices/recipes/>;
   ], [
      a solid:TypeRegistration;
      solid:forClass idx:GroupIndexTemplate;
      idx:indexesClass meal:ShoppingListEntry
      solid:instanceContainer <../indices/shopping-entries/>;
   ], [
      a solid:TypeRegistration;
      solid:forClass sync:ManagedDocument;
      sync:managedResourceType crdt:ClientInstallation;
      solid:instanceContainer <../installations/>
   ] .
```

4. **Managed Resource Discovery:** CRDT-enabled applications query the Type Index for `sync:ManagedDocument` registrations with specific `sync:managedResourceType` values (e.g., `schema:Recipe`) and their corresponding index types (e.g., `idx:FullIndex`), enabling automatic discovery of the complete synchronization setup.

**Advantages:** Using TypeRegistration with `sync:ManagedDocument` and `sync:managedResourceType` enables managed resource discovery while protecting managed resources from incompatible applications. CRDT-enabled applications can find both data and indices through standard Solid mechanisms ([WebID Profile](https://www.w3.org/TR/webid/), [Type Index](https://github.com/solid/type-indexes)), while traditional applications remain unaware of CRDT-managed data, preventing accidental corruption.

## 3. Pod Setup and Initial Configuration

When an application first encounters a Pod, it may need to configure the Type Index and other Solid infrastructure. The framework provides standard templates for this initialization process (see [templates/README.md](../templates/README.md) for complete placeholder substitution documentation):

**Comprehensive Setup Process:**
1. Check WebID Profile Document for solid:publicTypeIndex
2. If found, query Type Index for required managed resource registrations (sync:ManagedDocument with sync:managedResourceType schema:Recipe, idx:FullIndex, crdt:ClientInstallation, etc.)
3. Collect all missing/required configuration:
   - Missing Type Index entirely
   - Missing Type Registrations for managed data types (sync:ManagedDocument)
   - Missing Type Registrations for indices
   - Missing Type Registrations for installations
4. If any configuration is missing: Display single comprehensive "Pod Setup Dialog"
5. User chooses approach:
   1. **"Automatic Setup"** - Configure Pod with standard paths automatically
   2. **"Custom Setup"** - Review and modify proposed Profile/Type Index changes before applying
6. If user cancels: Run with hardcoded default paths, warn about reduced interoperability

**Setup Dialog Design Principles:**
- **Explicit Consent:** Never modify Pod configuration without user permission
- **Progressive Disclosure:** Automatic Setup shields users from complexity, Custom Setup provides full control
- **Clear Options:** Two main paths - trust the app or customize the details
- **Graceful Fallback:** Always offer alternative approaches if user declines configuration changes

**Example Setup Flow:**
```
1. Discover missing Type Index registrations for sync:ManagedDocument with sync:managedResourceType schema:Recipe
2. Present setup dialog: "This app needs to configure CRDT-managed recipe storage in your Pod"
3. User selects "Automatic Setup"
4. App creates Type Index entries for managed recipes, recipe index, client installations
5. App proceeds with normal synchronization workflow
```

### 3.1. Retention Policy Configuration in Type Index

The framework provides configurable retention policies for tombstoned documents, with Type Index serving as the configuration location for Solid backends.

**Example Type Index Configuration:**
```turtle
# Type Index with framework-wide defaults
<> a solid:TypeIndex;
   # Framework adds these defaults if missing
   crdt:documentTombstoneRetentionPeriod "P2Y"^^xsd:duration;
   crdt:enableDocumentTombstoneCleanup true;
   crdt:propertyTombstoneRetentionPeriod "P6M"^^xsd:duration;
   crdt:enablePropertyTombstoneCleanup true;
   solid:hasRegistration [
      a solid:TypeRegistration;
      solid:forClass sync:ManagedDocument;
      sync:managedResourceType schema:Recipe;
      solid:instanceContainer <../data/recipes/>;
      # Override: Keep recipe document tombstones longer
      crdt:documentTombstoneRetentionPeriod "P3Y"^^xsd:duration;
      crdt:propertyTombstoneRetentionPeriod "P3M"^^xsd:duration
   ] .
```

**Configuration Hierarchy:**

**Framework Defaults Hierarchy:**
1. **Type Index defaults:** Cleanup properties on the Type Index document itself
2. **Type-specific overrides:** Individual registrations can override Type Index defaults
3. **User control:** Framework never overwrites existing user-configured values