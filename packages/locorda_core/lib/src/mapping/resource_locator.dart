import 'dart:convert';

import 'package:rdf_core/rdf_core.dart';

/// Translates between application identifiers and storage IRIs for different backends.
///
/// For example:
/// - Solid Pod implementation: Uses type index to find storage location
/// - Google Drive backend: Simple strategy to convert to/from IRIs
abstract interface class ResourceLocator {
  /// Convert local ID and optional fragment to resource IRI.
  ///
  IriTerm toIri(ResourceIdentifier identifier);

  /// Extract local ID and fragment from resource IRI.
  ///
  /// Returns a record with the localId and optional fragment.
  ResourceIdentifier fromIri(IriTerm typeIri, IriTerm resourceIri);
}

final class ResourceIdentifier {
  final IriTerm typeIri;
  final String id;
  final String? fragment;

  ResourceIdentifier(this.typeIri, this.id, String fragment)
      : assert(fragment.isNotEmpty),
        fragment = fragment;
  ResourceIdentifier.document(this.typeIri, this.id) : fragment = null;
}

class LocalResourceLocator implements ResourceLocator {
  static const prefix = 'tag:locorda.org,2025:l:';
  final IriTermFactory _iriTermFactory;

  LocalResourceLocator({required IriTermFactory iriTermFactory})
      : _iriTermFactory = iriTermFactory;

  @override
  IriTerm toIri(ResourceIdentifier identifier) {
    final encodedTypeIri =
        base64Url.encode(utf8.encode(identifier.typeIri.value));
    final encodedLocalId = base64Url.encode(utf8.encode(identifier.id));
    return _iriTermFactory(
        '$prefix${encodedTypeIri}:$encodedLocalId${identifier.fragment != null ? '#${identifier.fragment}' : ''}');
  }

  @override
  ResourceIdentifier fromIri(IriTerm typeIri, IriTerm resourceIri) {
    // Split off fragment if present
    final iriValue = resourceIri.value;
    final fragmentIndex = iriValue.indexOf('#');
    final documentIriValue =
        fragmentIndex >= 0 ? iriValue.substring(0, fragmentIndex) : iriValue;
    final fragment =
        fragmentIndex >= 0 ? iriValue.substring(fragmentIndex + 1) : null;

    if (!documentIriValue.startsWith(prefix)) {
      throw ArgumentError(
          'Resource IRI ${resourceIri.value} does not belong to base IRI $prefix');
    }

    final encoded = documentIriValue.substring(prefix.length);
    final [encodedTypeIri, encodedLocalId] = encoded.split(':');
    final remoteTypeIri = utf8.decode(base64Url.decode(encodedTypeIri));

    if (remoteTypeIri != typeIri.value) {
      throw ArgumentError(
          'Resource IRI ${resourceIri.value} with type ${remoteTypeIri} does not match type IRI ${typeIri.value}');
    }

    final localId = utf8.decode(base64Url.decode(encodedLocalId));
    if (fragment == null) {
      return ResourceIdentifier.document(typeIri, localId);
    }
    return ResourceIdentifier(typeIri, localId, fragment);
  }

  ResourceIdentifier fromIriNoType(IriTerm resourceIri) {
    // Split off fragment if present
    final iriValue = resourceIri.value;
    final fragmentIndex = iriValue.indexOf('#');
    final documentIriValue =
        fragmentIndex >= 0 ? iriValue.substring(0, fragmentIndex) : iriValue;
    final fragment =
        fragmentIndex >= 0 ? iriValue.substring(fragmentIndex + 1) : null;

    if (!documentIriValue.startsWith(prefix)) {
      throw ArgumentError(
          'Resource IRI ${resourceIri.value} does not belong to base IRI $prefix');
    }

    final encoded = documentIriValue.substring(prefix.length);
    final [encodedTypeIri, encodedLocalId] = encoded.split(':');
    final remoteTypeIri =
        IriTerm.validated(utf8.decode(base64Url.decode(encodedTypeIri)));

    final localId = utf8.decode(base64Url.decode(encodedLocalId));
    if (fragment == null) {
      return ResourceIdentifier.document(remoteTypeIri, localId);
    }
    return ResourceIdentifier(remoteTypeIri, localId, fragment);
  }

  static bool isLocalIri(IriTerm subjectIri) {
    return subjectIri.value.startsWith(prefix);
  }
}
