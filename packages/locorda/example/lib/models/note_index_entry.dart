/// Index entry for Note resources containing lightweight header properties.
///
/// Index entries are used for efficient querying and on-demand sync scenarios.
/// They contain selected properties from the full Note resource plus metadata
/// like Hybrid Logical Clock hashes for change detection.
library;

import 'package:personal_notes_app/models/note.dart';

import 'package:rdf_mapper_annotations/rdf_mapper_annotations.dart';
import 'package:rdf_vocabularies_schema/schema.dart';
import 'package:locorda_annotations/locorda_annotations.dart';
import 'package:locorda_core/locorda_core.dart';

/// Lightweight index entry for Note resources.
///
/// Contains essential properties for browsing and filtering notes without
/// loading the full note content. Used in index update streams and
/// on-demand sync scenarios.
///
/// Index entries automatically use LWW-Register for all properties by default.
/// No CRDT annotations needed - the framework handles conflict resolution.
@LcrdIndexItem()
class NoteIndexEntry {
  /// Note ID - same as the full Note resource
  @RdfProperty(IdxShardEntry.resource, iri: LcrdRootResourceRef(Note))
  final String id;

  /// Note title for display in lists
  @RdfProperty(SchemaNoteDigitalDocument.name)
  final String name;

  /// Creation date for sorting and grouping
  @RdfProperty(SchemaNoteDigitalDocument.dateCreated)
  final DateTime dateCreated;

  /// Last modification time
  @RdfProperty(SchemaNoteDigitalDocument.dateModified)
  final DateTime dateModified;

  /// Keywords/tags for filtering
  @RdfProperty(SchemaNoteDigitalDocument.keywords)
  final Set<String> keywords;

  /// Category ID for grouping
  @NoteCategoryProperty()
  final String? categoryId;

  const NoteIndexEntry({
    required this.id,
    required this.name,
    required this.dateCreated,
    required this.dateModified,
    this.keywords = const {},
    this.categoryId,
  });

  @override
  String toString() =>
      'NoteIndexEntry(id: $id, name: $name, keywords: $keywords)';
}
