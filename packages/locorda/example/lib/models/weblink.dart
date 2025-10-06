/// Weblink model representing a web URL reference with optional metadata.
library;

import 'package:personal_notes_app/vocabulary/personal_notes_vocab.dart';
import 'package:rdf_mapper_annotations/rdf_mapper_annotations.dart';
import 'package:rdf_vocabularies_schema/schema.dart';
import 'package:locorda_annotations/locorda_annotations.dart';

/// A weblink with URL, title, and optional description.
///
/// This demonstrates classical identified blank nodes where the blank node
/// is identified by a unique property (url in this case).
///
/// Uses CRDT merge strategies:
/// - Immutable for url (identifying property, cannot change)
/// - LWW-Register for title and description (last writer wins)
///
@RdfLocalResource(
  PersonalNotesVocab.Weblink,
)
class Weblink {
  /// The URL - this is the identifying property for this blank node
  @RdfProperty(Schema.url)
  @McIdentifying()
  @CrdtImmutable()
  final String url;

  /// Optional title for the link
  @RdfProperty(Schema.name)
  @CrdtLwwRegister()
  final String? title;

  /// Optional description
  @RdfProperty(Schema.description)
  @CrdtLwwRegister()
  final String? description;

  Weblink({
    required this.url,
    this.title,
    this.description,
  });

  Weblink copyWith({
    String? url,
    String? title,
    String? description,
  }) {
    return Weblink(
      url: url ?? this.url,
      title: title ?? this.title,
      description: description ?? this.description,
    );
  }

  @override
  String toString() {
    return 'Weblink(url: $url, title: $title)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Weblink && other.url == url;
  }

  @override
  int get hashCode => url.hashCode;
}
