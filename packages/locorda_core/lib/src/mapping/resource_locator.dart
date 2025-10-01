import 'dart:convert';

import 'package:rdf_core/rdf_core.dart';

/// Translates between application identifiers and storage IRIs for different backends.
///
/// For example:
/// - Solid Pod implementation: Uses type index to find storage location
/// - Google Drive backend: Simple strategy to convert to/from IRIs
abstract interface class ResourceLocator {
  IriTerm toIri(IriTerm typeIri, String localId);
  String fromIri(IriTerm typeIri, IriTerm remoteIri);
}

class LocalResourceLocator implements ResourceLocator {
  static const prefix = 'tag:locorda.org,2025:l:';
  final IriTermFactory _iriTermFactory;

  LocalResourceLocator({required IriTermFactory iriTermFactory})
      : _iriTermFactory = iriTermFactory;

  @override
  IriTerm toIri(IriTerm typeIri, String localId) {
    final encodedTypeIri = base64Url.encode(utf8.encode(typeIri.value));
    final encodedLocalId = base64Url.encode(utf8.encode(localId));
    return _iriTermFactory('$prefix${encodedTypeIri}:$encodedLocalId');
  }

  @override
  String fromIri(IriTerm typeIri, IriTerm remoteIri) {
    if (!remoteIri.value.startsWith(prefix)) {
      throw ArgumentError(
          'Remote IRI ${remoteIri.value} does not belong to base IRI ${prefix}');
    }
    final encoded = remoteIri.value.substring(prefix.length);
    final [encodedTypeIri, encodedLocalId] = encoded.split(':');
    final remoteTypeIri = utf8.decode(base64Url.decode(encodedTypeIri));
    if (remoteTypeIri != typeIri.value) // just to check if valid
      throw ArgumentError(
          'Remote IRI ${remoteIri.value} does not match type IRI ${typeIri.value}');
    return utf8.decode(base64Url.decode(encodedLocalId));
  }

  static bool isLocalIri(IriTerm subjectIri) {
    return subjectIri.value.startsWith(prefix);
  }
}
