# Project Status Report

**Date**: November 10, 2025  
**Author**: Klas Kalaß  
**Project Phase**: Critical Assessment

---

## A Note to Readers

I recognize that this document reads as a critical assessment—perhaps even a rant—of the Solid Protocol and ecosystem. To Solid supporters and enthusiasts: **I genuinely admire the vision and would be delighted to be proven wrong** on the points I raise here.

This assessment reflects my honest conclusions after **approximately 6 months of intensive work** on Locorda, attempting to build production-ready offline-first sync for Solid Pods. It captures my disappointment at not finding viable solutions to the fundamental problems I encountered. 

If you're working on Solid and have insights into how these challenges can be addressed, or if the ecosystem has evolved since this writing, I'd welcome that feedback. This is not meant to discourage Solid development—it's a transparent account of one developer's experience trying to build on the platform.

---

## Executive Summary

After intensive implementation work on Locorda, I've discovered that the fundamental performance problems with Solid Pods cannot be solved through client-side optimization (offline-first architecture, CRDTs, smart indexing/sharding). The Solid Protocol has inherent limitations that make it unsuitable for applications requiring reasonable performance, and the ecosystem remains deeply immature. This document captures my critical assessment of the project's viability and future direction.

---

## Initial Hypothesis: What I Thought Would Work

When I started this project, my diagnosis of the Solid performance problem was:

**Problem**: Solid apps are slow because they query data from the pod every time  
**Solution**: Offline-first architecture with:
- Local storage and smart caching
- CRDT merge logic for conflict-free sync
- Indexed and sharded data structures
- Selective sync (only download what you need)
- Efficient index files (e.g., all recipe titles in one condensed file)

The reasoning seemed sound: by keeping data local and syncing intelligently, we could overcome network latency and reduce redundant requests.

---

## Reality Check: What I Discovered

### Performance Problems Are Fundamental, Not Fixable

**The killer metric**: Syncing a single application entity to a Solid Pod takes **approximately 1 second**.

Why?
- Each HTTP request to pods (e.g., SolidCommunity) takes ~300ms
- A complete sync operation requires **3 requests**: GET + PUT + HEAD
  - GET: Fetch current state (check for remote changes)
  - PUT: Write updated entity
  - HEAD: Retrieve new ETag (because PUT doesn't return it!)
- 300ms × 3 = ~900ms per entity, rounded to ~1 second

**This cannot be solved by Locorda**. Even if I optimize from multiple index/shard files down to 1-2 files total, the fundamental per-entity latency remains. Client-side optimization is powerless against server-side protocol design.

### Solid Protocol Limitations

The performance problem is **by design**, not implementation:

1. **No batching capability**: Unlike Google Drive (batch API) or other modern backends, Solid has no way to bundle multiple operations into a single request
   
2. **SPARQL endpoints removed from spec**: The protocol originally included server-side query capabilities, but these were removed. Applications have no way to do efficient server-side queries or filtering

3. **Linked Data philosophy optimizes for semantics, not performance**: The focus is on RDF entities and semantic interoperability, not on performant queries or updates

4. **Authentication/Authorization overhead**: DPoP tokens, ACL file checks, etc. add additional latency to every request

5. **Inherently chatty protocol**: The design pattern encourages many small requests rather than consolidated operations

**Result**: The protocol has slow individual requests **AND** no way to reduce the number of requests **AND** encourages chatty communication patterns. This is a triple-kill for performance.

### Solid Ecosystem Immaturity

Beyond protocol limitations, the entire Solid ecosystem is immature:

1. **Production-readiness**: ALL Solid pod providers explicitly label themselves as "for early adopters and developers only" - none claim production-ready status

2. **UI/UX quality**: Every Solid pod provider I've tested has terrible user interface and user experience

3. **Application interoperability**: The spec exists but isn't implemented by common pod providers
   - Apps cannot simply request authorization and receive user consent
   - Users must manually edit ACL files to grant app permissions
   - This is completely unusable for non-technical users

4. **Developer experience**: Poor documentation, inconsistent implementations, difficult debugging, limited tooling

5. **Community and momentum**: Unclear whether the ecosystem will reach maturity or remain a niche experiment

### Implications for Locorda

My client-side optimization strategy (indices, shards, selective sync) **cannot overcome protocol-level limitations**:

- Optimizing from 10 files to 2 files doesn't matter if each entity still takes 1 second
- Smart indexing can't fully compensate for lack of server-side queries
- CRDT merge efficiency is irrelevant when network latency dominates
- Offline-first helps UX but doesn't solve the sync performance problem. An initial sync of my example app with 1 note and two categories took 30 seconds!

**The core value proposition of Locorda assumes the performance problems are fixable through clever client architecture. This assumption is false for Solid Pods.**

---

## What Actually Works (Salvageable Parts)

Despite the Solid-specific problems, some parts of the project have value:

1. **CRDT architecture and implementation**: The Hybrid Logical Clock implementation, merge algorithms, and conflict resolution logic are sound and could work with other backends

2. **Offline-first architecture**: The "sync as add-on" pattern (ADR-0003) is solid and developer-friendly

3. **Repository-based hydration pattern**: Clean separation between app storage and sync metadata

4. **RDF vocabulary design**: The `crdt:`, `sync:`, `algo:`, `idx:` vocabularies are well-thought-out (though RDF itself may not be the right choice)

5. **Specification work**: Extensive architectural documentation, even if the chosen backend is problematic

6. **Dart implementation quality**: Clean code, good test coverage, idiomatic patterns

---

## Alternative Paths Forward

### Option 1: Pivot to Google Drive (or Similar Backends)

**Rationale**: Google Drive has:
- Batch API (bundle multiple operations)
- Reasonable per-request latency
- Better query capabilities
- Mature, production-ready infrastructure

**Challenges**:
- ID/Name mapping overhead (Google Drive uses IDs, apps often use names)
- Still may not achieve great performance
- Different API paradigm requires significant rework
- Google-specific lock-in (though could support multiple backends)

**Viability**: Possibly viable, but uncertain performance outcome


### Option 2: Archive Project with Lessons Learned

**Rationale**:
- Honest assessment: Solid is not ready for production end-user apps
- Performance problems are unsolvable with current protocol
- Extensive specification/implementation work, but built on wrong foundation
- Better to document learnings than continue investing in problematic approach

**Value**:
- Comprehensive documentation of what doesn't work and why
- CRDT implementation could be extracted for other uses
- Specification work valuable as cautionary tale
- Frees time/energy for more viable projects

---

## Current Thinking: Leaning Toward Archiving

**Why I'm considering stopping**:

1. **Fundamental unsolvability**: The core performance problem cannot be fixed by Locorda
2. **Ecosystem immaturity**: Solid isn't production-ready and timeline to maturity is unclear
3. **Uncertain pivot value**: Switching to Google Drive is significant work with uncertain payoff
4. **Opportunity cost**: Time spent here could go to projects with clearer value proposition
5. **Honest assessment**: I underestimated Solid's limitations and overestimated what client-side optimization could achieve

**What would be preserved**:

- Complete specification documenting the architecture
- Working Dart implementation (even if for a problematic backend)
- CRDT algorithms and patterns that could be reused
- Honest documentation of what doesn't work (valuable for others)
- Clear articulation of Solid Protocol limitations

---

## Open Questions

1. **Is there a viable use case for Solid Pods with current limitations?**
   - Maybe apps with <100 entities that sync infrequently?
   - Maybe read-heavy apps where write latency doesn't matter?

2. **Will Solid Protocol evolve to address performance?**
   - Batch operations added?
   - SPARQL endpoints return?
   - Pod providers optimize infrastructure?

3. **Is there value in a Google Drive version of Locorda?**
   - Would performance actually be acceptable?
   - Is there real demand for this capability?

4. **Could the CRDT work be spun out separately?**
   - Reusable library independent of backend choice?
   - Valuable without the full Locorda architecture?
   - But to be honest: I found CRDT to be a very small part of locorda work.

5. **What should happen to the specification work?**
   - Archive as-is with clear warnings?
   - Put work into syncing with actual implementation as the original spec was not directly implementable?
   - Transform into a "lessons learned" document?
   - Publish as cautionary tale about Solid limitations?

---

## Next Steps

**Immediate**: Complete this assessment, let thoughts settle

**Short-term**: Decide between:
1. Archive project with comprehensive documentation
2. Pivot to Google Drive backend (requires proof-of-concept first)

**Long-term**: If archiving:
- Add prominent warnings to README
- Write comprehensive "why this didn't work" documentation
- Extract any reusable components
- Move on to more viable projects

---

## Notes for Future Self (or Others)

### Key Lessons Learned

1. **Validate fundamental assumptions early**: I should have measured Solid Pod performance thoroughly before investing in extensive architecture work

2. **Protocol limitations trump client cleverness**: No amount of smart client-side optimization can overcome bad server-side protocol design

3. **Ecosystem maturity matters**: Building on immature infrastructure is high-risk, especially when you can't control or influence it

4. **Performance is a feature**: Semantic web ideals are nice, but 1-second-per-entity sync latency makes apps unusable

5. **Batching is critical**: Modern backends need batch operations; protocols without them are dead on arrival for interactive apps

### What I'd Do Differently

- Measure Solid Pod performance first, build architecture second
- Prototype with real backend before writing extensive specs
- Start with minimal viable implementation, add sophistication later
- Consider multiple backend options from the start
- Be more skeptical of "early adopter" technology claims

### Frustrations

- Wasted months on architecture that can't overcome protocol limitations
- Solid Protocol feels like theory-driven design without practical performance consideration
- Documentation gaps and inconsistencies across pod providers
- No clear path to production-readiness in Solid ecosystem
- The removed SPARQL endpoint decision seems catastrophic for app performance

### Insights

- The offline-first + CRDT approach is sound, but only valuable with a capable backend
- RDF adds significant complexity and performance cost; unclear if benefits justify it for typical apps
- "Bring your own backend" is appealing philosophically but creates integration challenges
- Developer experience matters enormously; Solid's DX is currently poor

---

**Related Documents:**
- Formal technical assessment: [ADR-0004: Project Assessment and Future Direction](packages/locorda/docs/adrs/0004-project-assessment-and-future-direction.md)
- ADR Overview: [packages/locorda/docs/adrs/README.md](packages/locorda/docs/adrs/README.md)
- Main project documentation: [README.md](README.md)
