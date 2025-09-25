/// Category model for organizing notes with CRDT annotations.
library;

import 'package:rdf_core/rdf_core.dart';
import 'package:rdf_mapper_annotations/rdf_mapper_annotations.dart';
import 'package:rdf_vocabularies_schema/schema.dart';
import 'package:locorda_annotations/locorda_annotations.dart';
import '../vocabulary/personal_notes_vocab.dart';

/// A category for organizing personal notes.
///
/// Uses our custom vocabulary that properly specializes schema:CreativeWork
/// for note categorization, following ADR-0002 guidance for specific types.
///
/// Uses CRDT merge strategies:
/// - LWW-Register for name and description (last writer wins)
/// - Immutable for creation date
///
@PodResource(PersonalNotesVocab.NotesCategory)
class Category {
  /// Unique identifier for this category
  @RdfIriPart()
  final String id;

  /// Category name - last writer wins on conflicts
  @RdfProperty(SchemaCreativeWork.name)
  @CrdtLwwRegister()
  final String name;

  /// Optional description - last writer wins on conflicts
  @RdfProperty(SchemaCreativeWork.description)
  @CrdtLwwRegister()
  final String? description;

  /// Color for UI display (hex code, CSS color name, etc.)
  @RdfProperty(PersonalNotesVocab.categoryColor)
  @CrdtLwwRegister()
  final String? color;

  /// Icon for UI display (emoji, icon name, etc.)
  @RdfProperty(PersonalNotesVocab.categoryIcon)
  @CrdtLwwRegister()
  final String? icon;

  /// When this category was created
  @RdfProperty(SchemaCreativeWork.dateCreated)
  @CrdtImmutable()
  final DateTime createdAt;

  /// When this category was last modified
  @RdfProperty(SchemaCreativeWork.dateModified)
  @CrdtLwwRegister()
  final DateTime modifiedAt;

  /// Whether this category is archived (soft deleted)
  @RdfProperty(PersonalNotesVocab.archived)
  @CrdtLwwRegister()
  final bool archived;

  @RdfUnmappedTriples(globalUnmapped: true)
  final RdfGraph other;

  Category({
    required this.id,
    required this.name,
    this.description,
    this.color,
    this.icon,
    DateTime? createdAt,
    DateTime? modifiedAt,
    this.archived = false,
    RdfGraph? other,
  })  : createdAt = createdAt ?? DateTime.now(),
        modifiedAt = modifiedAt ?? DateTime.now(),
        other = other ?? RdfGraph();

  /// Create a copy of this category with updated fields
  Category copyWith({
    String? id,
    String? name,
    String? description,
    String? color,
    String? icon,
    DateTime? createdAt,
    DateTime? modifiedAt,
    bool? archived,
  }) {
    return Category(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      color: color ?? this.color,
      icon: icon ?? this.icon,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      archived: archived ?? this.archived,
      other: other,
    );
  }

  @override
  String toString() {
    return 'Category(id: $id, name: $name)';
  }
}
