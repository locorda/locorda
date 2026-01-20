import 'package:locorda_rdf_mapper_annotations/annotations.dart';

/// Template-based IRI for standardized identifiers
@RdfIri('urn:isbn:{value}')
class ISBN {
  @RdfIriPart() // 'value' is inferred from property name
  final String value;

  ISBN(this.value);
  // Serialized as: urn:isbn:9780261102217
}

/// Direct value as IRI (no template)
@RdfIri()
class AbsoluteUri {
  @RdfIriPart()
  final String uri;

  AbsoluteUri(this.uri);
  // Uses the value directly as IRI: 'https://example.org/resource/123'
}

/// Multi-part IRI with context variables
@RdfIri('{+baseUri}/collections/{collection}/{item}')
class CollectionItem {
  @RdfIriPart('collection')
  final String collection;

  @RdfIriPart('item')
  final String item;

  CollectionItem(this.collection, this.item);
  // With baseUri='https://api.example.org':
  // → https://api.example.org/collections/books/item-123
}
