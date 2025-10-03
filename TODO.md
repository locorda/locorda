# TODO

## Up Next

### Priority 1: Document Persistence (Core Foundation)
- [x] Storage Layer: save documents
- [x] LocordaGraphSync: save base implementation
- [x] merge-contract: Implement loading and merging the mappings documents and make them usable via dart classes
- [x] merge-contract: In-memory caching of loaded merge contracts (LRU cache to avoid repeated expensive loading on every save)
- [x] Use data from mapping documents to build the stop-word list to correctly separate appGraph from framework data in processing of the old stored document
- [x] Implement context-identification for blank nodes 
- [x] Association of merge contract rules: if we do not find a rule, and the type is not specified, we should use type inference and look up the predicate rule within the class rules, assuming the type automatically. This is probably also a spec change proposal
- [x] We need to implement the type-specific stop traversal as well
- [x] rdf canonicalization 
- [x] fix w3id.org redirects
- [x] Create a unique identifier IRI for identified blank nodes
- [x] Do not use blank nodes for framework metadata, use fragments with #lcrd- prefix instead. Fix the corresponding FIXMEs to create predictable, hash based fragments
- [x] Setup Testing Framework similar to official RDF Canonicalization test where there is a csv/json file describing the test cases and referencing input/output files. 
- [x] Installation document is needed and installation id generating (needs to be controlled/overridden in tests though)
- [x] check hlc clock handling and creation - the hlc clock in the expected test data looks dubious
- [x] shall we keep the clock entries as blank nodes, or identify them? If we keep them as blank nodes, then they probably need to be detected and merged as ibn - but that would add extra meta data so it is rather suboptimal. I tend to think that framework data must not be blank nodes, so clock entries would become identifiable iris as well. or we need special handling - doing special handling for clock entries seems sensible anyways, right?
- [x] Implement clock hash computation
- [ ] Use the testing framework to thoroughly test LocordaGraphSync.save()
- [ ] test clock merge during save (e.g. when a foreign clock entry existed)
- [ ] Store Blank Node identifier IRI mapping in the document metadata, merging in the old data on save (?)
- [ ] Use context-identification as a base for `List<PropertyChange>` passed to storage layer instead of IriTerm for resource identification
- [ ] Storage Layer: save locorda indices
- [ ] Implement locorda index files in db and fill/update them on save
- [ ] Create tombstones on save where needed (e.g. change detection)
- [ ] What about tombstones for blank nodes?
- [ ] Implement saving/loading/merging documents with local storage persistence
  - Currently `save()` just emits hydration events without storage persistence
  - Need CRDT merging logic and actual storage operations => CRDT merging is not part of pure persistence
  - This unblocks the example app's core functionality
 
### Priority 2: SyncManager with Status Stream
- [ ] Create SyncManager with status stream and automatic sync triggering
  - Essential for user-facing sync control and feedback
  - Enables manual/automatic sync triggering
  - Foundation for all higher-level sync operations

### Priority 3: Index Processing
- [ ] Complete index creation and group subscription handling
  - Complete group subscription and index creation logic
  - Currently stubbed in `configureGroupIndexSubscription()`
  - Needed for efficient data organization and sync

### Priority 4: Backend Implementations
- [ ] Implement in-memory backend for testing and development
  - Simpler to implement than Solid backend
  - Enables testing without external dependencies
  - Good foundation for understanding backend interface

- [ ] Implement Solid backend with actual Pod storage operations
  - Most complex but enables the full vision
  - Requires Pod operations, authentication integration
  - Can reuse patterns from in-memory backend

### Priority 5: Ensure full Offline-First Support
- [ ] merge-contract: Build-time asset bundling (essential for offline-first: bundle all referenced merge contracts as assets so apps work offline from first launch)

### Priority 6: Performance & Efficiency Optimizations
- [ ] merge-contract: RdfGraphFetcher caching with etag support (HTTP best practices, benefits all RDF loading)
- [ ] merge-contract: Local database caching (persistence across app restarts)

## Later
- [ ] Final check if the spec in ARCHITECTURE.md is fully implemented

## Done
- [x] Migrate to W3ID.org permanent IRIs
- [x] Clarify: can we include localhost into the client-config.json document to support local debugging? Or should we rather not do that since it would open up our app to attacks? => better not, plus: removed linux/windows support and adviced against those platforms
- [x] Refactor: Solid should only be one possible backend - rename from solid_crdt_sync to locorda and split the spec as well
- [x] Refactor: I am thinking about adding something like LocordaGraphSync which would be similar to LocordaSync, but not based on dart objects + mapper, but on pure RdfGraph instances. The Idea is, that LocordaGraphSync should be used by LocordaSync for the actual work, so that LocordaSync itself adds the dart object conversion on top of the more basic sync service. Clarify if I want to do it now or possibly later => done
- [x] Clarify: What is the most-user-friendly way to approach http? should we simply assume that we are provided with http client, or is it best practice for a library like ours to abstract this away? Remember: http would need to be integrated with solid DPoP, is this in our control, or should we offload it to the developer? => http.Client is an interface, let users optionally provide an instance - this is common practice and other networking implementations have adapters for this interface.
