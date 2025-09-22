/// Key for identifying items by type and local name.
library;

import 'package:rdf_core/rdf_core.dart';

/// Key composed of a Dart Type and local name string.
///
/// Used to uniquely identify hydration streams, converters, and other
/// components that are keyed by (Type, localName) pairs.
class TypeOrIndexKey {
  final IriTerm typeIri;
  final String? indexName;

  const TypeOrIndexKey(this.typeIri, this.indexName);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TypeOrIndexKey &&
        other.typeIri == typeIri &&
        other.indexName == indexName;
  }

  @override
  int get hashCode => Object.hash(typeIri, indexName);

  @override
  String toString() => 'TypeOrIndexKey($typeIri, $indexName)';
}
