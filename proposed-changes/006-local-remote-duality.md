This is a offline/local first framework, so the IRIs that refer to content of the app,
must be considered local apps. There are multiple possible backends. 
Some backends like google drive or dropbox might have application-local mode and 
simply continue using the local IRIs. But other backends like Solid Pods which are
designed for collaboration between apps need (e.g. pod-specific) IRIs.

This needs to made clear in the specification, and it needs to be made clear 
that content-based hashes like the blank node identification or the statement iri fragments
must be computed based on the local form.

But what does that sentence mean in detail? It means, that syncing data from remote 
must substitute remote IRIs with local IRIs in a way that is absolutely stable and 
well-defined, so that all apps are resolving it to the same local IRI.


So what do we need for this mapping? How do we ensure that in a cooperative environment apps do not inadvertantly override each others content?

=> we verify now in some places that the correct local prefix is used, which we standardized to be `tag:locorda.org,2025:l:`

TODO: incorporate this into the SPEC, and define the local IRIs and the general mechanism for mapping.

