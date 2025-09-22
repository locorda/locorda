/// Repository layer for business logic operations.
library;

import 'dart:async';
import 'package:drift/drift.dart';
import 'package:locorda/locorda.dart';
import '../models/category.dart' as models;
import '../models/note.dart' as models;
import '../models/note_index_entry.dart' as models;
import '../models/note_group_key.dart';
import 'database.dart';

/// Repository for Category business logic operations.
///
/// This layer handles business logic, model conversion between
/// Drift entities and application models, AND sync coordination.
/// Repository becomes "sync-aware storage" following add-on architecture.
class CategoryRepository {
  final CategoryDao _categoryDao;
  final LocordaSync _syncSystem;
  final HydrationSubscription _hydrationSubscription;

  static const String _resourceType = 'category';

  /// Private constructor - use [create] factory method instead
  CategoryRepository._(
    this._categoryDao,
    this._syncSystem,
    this._hydrationSubscription,
  );

  /// Create and initialize a CategoryRepository with hydration from sync storage.
  ///
  /// This factory method:
  /// 1. Sets up hydration subscription for live updates
  /// 2. Performs initial catch-up from last cursor position
  /// 3. Returns a fully initialized repository
  static Future<CategoryRepository> create(
    CategoryDao categoryDao,
    CursorDao cursorDao,
    LocordaSync syncSystem,
  ) async {
    final repository = CategoryRepository._(
        categoryDao,
        syncSystem,
        await syncSystem.hydrateStreaming<models.Category>(
          getCurrentCursor: () => cursorDao.getCursor(_resourceType),
          onUpdate: (category) => _handleCategoryUpdate(categoryDao, category),
          onDelete: (category) => _handleCategoryDelete(categoryDao, category),
          onCursorUpdate: (cursor) =>
              cursorDao.storeCursor(_resourceType, cursor),
        ));

    return repository;
  }

  /// Handle category update from sync storage
  static Future<void> _handleCategoryUpdate(
      CategoryDao categoryDao, models.Category category) async {
    final companion = _categoryToDriftCompanion(category);
    await categoryDao.insertOrUpdateCategory(companion);
  }

  /// Handle category deletion from sync storage
  static Future<void> _handleCategoryDelete(
      CategoryDao categoryDao, models.Category category) async {
    await categoryDao.deleteCategoryById(category.id);
  }

  /// Watch all categories ordered by name (non-archived only)
  Stream<List<models.Category>> getAllCategories() {
    return _categoryDao.getAllCategories().map(
        (driftCategories) => driftCategories.map(_categoryFromDrift).toList());
  }

  /// Watch all categories including archived ones, ordered by name
  Stream<List<models.Category>> getAllCategoriesIncludingArchived() {
    return _categoryDao.getAllCategoriesIncludingArchived().map(
        (driftCategories) => driftCategories.map(_categoryFromDrift).toList());
  }

  /// Get a specific category by ID
  Future<models.Category?> getCategory(String id) async {
    final driftCategory = await _categoryDao.getCategoryById(id);
    return driftCategory != null ? _categoryFromDrift(driftCategory) : null;
  }

  /// Save a category (insert or update) with sync coordination
  Future<void> saveCategory(models.Category category) async {
    // Use sync system - local storage will be updated via hydration stream
    await _syncSystem.save<models.Category>(category);
  }

  /// Archive a category (soft delete) - sets archived flag to true
  ///
  /// Soft delete - marks category as archived but keeps it referenceable.
  /// This is the recommended approach for categories since they may be
  /// referenced by external applications.
  Future<void> archiveCategory(String id) async {
    final category = await getCategory(id);
    if (category != null) {
      final archivedCategory = category.copyWith(
        archived: true,
        modifiedAt: DateTime.now(),
      );
      await saveCategory(archivedCategory);
    }
  }

  /// Dispose resources when repository is no longer needed
  void dispose() {
    _hydrationSubscription.cancel();
  }

  /// Convert Drift Category to app Category model
  models.Category _categoryFromDrift(Category drift) {
    return models.Category(
      id: drift.id,
      name: drift.name,
      description: drift.description,
      color: drift.color,
      icon: drift.icon,
      createdAt: drift.createdAt,
      modifiedAt: drift.modifiedAt,
      archived: drift.archived,
    );
  }

  /// Convert app Category model to Drift CategoriesCompanion
  static CategoriesCompanion _categoryToDriftCompanion(
      models.Category category) {
    return CategoriesCompanion(
      id: Value(category.id),
      name: Value(category.name),
      description: Value(category.description),
      color: Value(category.color),
      icon: Value(category.icon),
      createdAt: Value(category.createdAt),
      modifiedAt: Value(category.modifiedAt),
      archived: Value(category.archived),
    );
  }
}

/// Repository for Note business logic operations.
///
/// This layer handles business logic, model conversion between
/// Drift entities and application models, AND sync coordination.
/// Repository becomes "sync-aware storage" following add-on architecture.
///
/// Handles both full Note resources and lightweight NoteIndexEntry resources.
class NoteRepository {
  final NoteDao _noteDao;
  final NoteIndexEntryDao _noteIndexDao;
  final LocordaSync _syncSystem;
  final HydrationSubscription _dataHydrationSubscription;
  final HydrationSubscription _indexHydrationSubscription;

  static const String _resourceType = 'note';
  static const String _indexResourceType = 'noteIndexEntry';

  /// Private constructor - use [create] factory method instead
  NoteRepository._(
    this._noteDao,
    this._noteIndexDao,
    this._syncSystem,
    this._dataHydrationSubscription,
    this._indexHydrationSubscription,
  );

  /// Create and initialize a NoteRepository with hydration from sync storage.
  ///
  /// This factory method:
  /// 1. Sets up hydration subscriptions for both Note and NoteIndexEntry
  /// 2. Performs initial catch-up from last cursor position for both types
  /// 3. Returns a fully initialized repository
  static Future<NoteRepository> create(
    NoteDao noteDao,
    NoteIndexEntryDao noteIndexDao,
    CursorDao cursorDao,
    LocordaSync syncSystem,
  ) async {
    final repository = NoteRepository._(
        noteDao,
        noteIndexDao,
        syncSystem,
        // Data hydration for full Note resources
        await syncSystem.hydrateStreaming<models.Note>(
          getCurrentCursor: () => cursorDao.getCursor(_resourceType),
          onUpdate: (note) => _handleNoteUpdate(noteDao, note),
          onDelete: (note) => _handleNoteDelete(noteDao, note),
          onCursorUpdate: (cursor) =>
              cursorDao.storeCursor(_resourceType, cursor),
        ),
        // Index hydration for NoteIndexEntry resources
        await syncSystem.hydrateStreaming<models.NoteIndexEntry>(
          getCurrentCursor: () => cursorDao.getCursor(_indexResourceType),
          onUpdate: (noteEntry) =>
              _handleNoteIndexEntryUpdate(noteIndexDao, noteEntry),
          onDelete: (noteEntry) =>
              _handleNoteIndexEntryDelete(noteIndexDao, noteEntry),
          onCursorUpdate: (cursor) =>
              cursorDao.storeCursor(_indexResourceType, cursor),
        ));

    return repository;
  }

  /// Handle note update from sync storage
  static Future<void> _handleNoteUpdate(
      NoteDao noteDao, models.Note note) async {
    final companion = _noteToDriftCompanion(note);
    await noteDao.insertOrUpdateNote(companion);
  }

  /// Handle note deletion from sync storage
  static Future<void> _handleNoteDelete(
      NoteDao noteDao, models.Note note) async {
    await noteDao.deleteNoteById(note.id);
  }

  /// Handle note index entry update from sync storage
  static Future<void> _handleNoteIndexEntryUpdate(
      NoteIndexEntryDao noteIndexDao, models.NoteIndexEntry noteEntry) async {
    final companion = _noteIndexEntryToDriftCompanion(noteEntry);
    await noteIndexDao.insertOrUpdateNoteIndexEntry(companion);
  }

  /// Handle note index entry deletion from sync storage
  static Future<void> _handleNoteIndexEntryDelete(
      NoteIndexEntryDao noteIndexDao, models.NoteIndexEntry noteEntry) async {
    await noteIndexDao.deleteNoteIndexEntryById(noteEntry.id);
  }

  /// Get a specific note by ID
  Future<models.Note?> getNote(String id) async {
    return _syncSystem.ensure<models.Note>(id, loadFromLocal: (id) async {
      final driftNote = await _noteDao.getNoteById(id);
      return driftNote != null ? _noteFromDrift(driftNote) : null;
    });
  }

  /// Save a note (insert or update) with sync coordination
  Future<void> saveNote(models.Note note) async {
    // Use sync system - local storage will be updated via hydration stream
    await _syncSystem.save<models.Note>(note);
  }

  /// Delete a note by ID (hard deletion - entire document)
  Future<void> deleteNote(String id) async {
    final note = await getNote(id);
    if (note != null) {
      // Use sync system - local storage will be updated via hydration stream
      await _syncSystem.deleteDocument<models.Note>(id);
    }
  }

  /// Convert Drift Note to app Note model
  models.Note _noteFromDrift(Note drift) => models.Note(
        id: drift.id,
        title: drift.title,
        content: drift.content,
        tags: drift.tags, // Now properly handled by StringSetConverter
        categoryId: drift.categoryId,
        createdAt: drift.createdAt,
        modifiedAt: drift.modifiedAt,
      );

  /// Convert app Note model to Drift NotesCompanion
  static NotesCompanion _noteToDriftCompanion(models.Note note) =>
      NotesCompanion(
        id: Value(note.id),
        title: Value(note.title),
        content: Value(note.content),
        tags: Value(note.tags), // Now properly handled by StringSetConverter
        categoryId: Value(note.categoryId),
        createdAt: Value(note.createdAt),
        modifiedAt: Value(note.modifiedAt),
      );

  /// Convert Drift NoteIndexEntry to app NoteIndexEntry model
  models.NoteIndexEntry _noteIndexEntryFromDrift(NoteIndexEntry drift) =>
      models.NoteIndexEntry(
        id: drift.id,
        name: drift.name,
        dateCreated: drift.dateCreated,
        dateModified: drift.dateModified,
        keywords: drift.keywords ?? <String>{}, // Handle null with empty set
        categoryId: drift.categoryId,
      );

  /// Convert app NoteIndexEntry model to Drift NoteIndexEntriesCompanion
  static NoteIndexEntriesCompanion _noteIndexEntryToDriftCompanion(
          models.NoteIndexEntry noteEntry) =>
      NoteIndexEntriesCompanion(
        id: Value(noteEntry.id),
        name: Value(noteEntry.name),
        dateCreated: Value(noteEntry.dateCreated),
        dateModified: Value(noteEntry.dateModified),
        keywords: Value(
            noteEntry.keywords), // Now properly handled by StringSetConverter
        categoryId: Value(noteEntry.categoryId),
      );

  /// Watch all note index entries reactively
  Stream<List<models.NoteIndexEntry>> watchAllNoteIndexEntries() {
    return _noteIndexDao.watchAllNoteIndexEntries().map(
        (driftEntries) => driftEntries.map(_noteIndexEntryFromDrift).toList());
  }

  /// Configure subscription to a specific month group for note index entries
  Future<void> configureMonthGroupSubscription(
      NoteGroupKey monthKey, ItemFetchPolicy fetchPolicy) async {
    await _syncSystem.configureGroupIndexSubscription(monthKey, fetchPolicy);
  }

  /// Dispose resources when repository is no longer needed
  void dispose() {
    _dataHydrationSubscription.cancel();
    _indexHydrationSubscription.cancel();
  }
}
