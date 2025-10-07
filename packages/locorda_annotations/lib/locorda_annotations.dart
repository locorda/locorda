/// CRDT merge strategy annotations for locorda code generation.
///
/// This library provides annotations to specify how properties should be merged
/// in CRDT scenarios. The annotations work with RDF mapping and are used by
/// the locorda generator to create proper merge logic.
library locorda_annotations;

export 'src/crdt_annotations.dart'
    show
        CrdtFwwRegister,
        CrdtImmutable,
        CrdtLwwRegister,
        CrdtOrSet,
        McIdentifying;
export 'src/pod_resource.dart'
    show
        PodResource,
        PodSubResource,
        PodIriStrategy,
        FragmentStrategy,
        resourceIriFactoryKey,
        resourceIriVar;
export 'src/pod_resource_ref.dart' show PodResourceRef, resourceRefFactoryKey;
