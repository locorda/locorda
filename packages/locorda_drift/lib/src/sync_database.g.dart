// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_database.dart';

// ignore_for_file: type=lint
mixin _$SyncDocumentDaoMixin on DatabaseAccessor<SyncDatabase> {
  $SyncIrisTable get syncIris => attachedDatabase.syncIris;
  $SyncDocumentsTable get syncDocuments => attachedDatabase.syncDocuments;
}
mixin _$SyncPropertyChangeDaoMixin on DatabaseAccessor<SyncDatabase> {
  $SyncIrisTable get syncIris => attachedDatabase.syncIris;
  $SyncDocumentsTable get syncDocuments => attachedDatabase.syncDocuments;
  $SyncPropertyChangesTable get syncPropertyChanges =>
      attachedDatabase.syncPropertyChanges;
}

class $SyncIrisTable extends SyncIris with TableInfo<$SyncIrisTable, SyncIri> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncIrisTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _iriMeta = const VerificationMeta('iri');
  @override
  late final GeneratedColumn<String> iri = GeneratedColumn<String>(
      'iri', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));
  @override
  List<GeneratedColumn> get $columns => [id, iri];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_iris';
  @override
  VerificationContext validateIntegrity(Insertable<SyncIri> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('iri')) {
      context.handle(
          _iriMeta, iri.isAcceptableOrUnknown(data['iri']!, _iriMeta));
    } else if (isInserting) {
      context.missing(_iriMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncIri map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncIri(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      iri: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}iri'])!,
    );
  }

  @override
  $SyncIrisTable createAlias(String alias) {
    return $SyncIrisTable(attachedDatabase, alias);
  }
}

class SyncIri extends DataClass implements Insertable<SyncIri> {
  final int id;
  final String iri;
  const SyncIri({required this.id, required this.iri});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['iri'] = Variable<String>(iri);
    return map;
  }

  SyncIrisCompanion toCompanion(bool nullToAbsent) {
    return SyncIrisCompanion(
      id: Value(id),
      iri: Value(iri),
    );
  }

  factory SyncIri.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncIri(
      id: serializer.fromJson<int>(json['id']),
      iri: serializer.fromJson<String>(json['iri']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'iri': serializer.toJson<String>(iri),
    };
  }

  SyncIri copyWith({int? id, String? iri}) => SyncIri(
        id: id ?? this.id,
        iri: iri ?? this.iri,
      );
  SyncIri copyWithCompanion(SyncIrisCompanion data) {
    return SyncIri(
      id: data.id.present ? data.id.value : this.id,
      iri: data.iri.present ? data.iri.value : this.iri,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncIri(')
          ..write('id: $id, ')
          ..write('iri: $iri')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, iri);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncIri && other.id == this.id && other.iri == this.iri);
}

class SyncIrisCompanion extends UpdateCompanion<SyncIri> {
  final Value<int> id;
  final Value<String> iri;
  const SyncIrisCompanion({
    this.id = const Value.absent(),
    this.iri = const Value.absent(),
  });
  SyncIrisCompanion.insert({
    this.id = const Value.absent(),
    required String iri,
  }) : iri = Value(iri);
  static Insertable<SyncIri> custom({
    Expression<int>? id,
    Expression<String>? iri,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (iri != null) 'iri': iri,
    });
  }

  SyncIrisCompanion copyWith({Value<int>? id, Value<String>? iri}) {
    return SyncIrisCompanion(
      id: id ?? this.id,
      iri: iri ?? this.iri,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (iri.present) {
      map['iri'] = Variable<String>(iri.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncIrisCompanion(')
          ..write('id: $id, ')
          ..write('iri: $iri')
          ..write(')'))
        .toString();
  }
}

class $SyncDocumentsTable extends SyncDocuments
    with TableInfo<$SyncDocumentsTable, SyncDocument> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncDocumentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _documentIriIdMeta =
      const VerificationMeta('documentIriId');
  @override
  late final GeneratedColumn<int> documentIriId = GeneratedColumn<int>(
      'document_iri_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'UNIQUE REFERENCES sync_iris (id)'));
  static const VerificationMeta _documentContentMeta =
      const VerificationMeta('documentContent');
  @override
  late final GeneratedColumn<String> documentContent = GeneratedColumn<String>(
      'document_content', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _ourPhysicalClockMeta =
      const VerificationMeta('ourPhysicalClock');
  @override
  late final GeneratedColumn<int> ourPhysicalClock = GeneratedColumn<int>(
      'our_physical_clock', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, documentIriId, documentContent, ourPhysicalClock, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_documents';
  @override
  VerificationContext validateIntegrity(Insertable<SyncDocument> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('document_iri_id')) {
      context.handle(
          _documentIriIdMeta,
          documentIriId.isAcceptableOrUnknown(
              data['document_iri_id']!, _documentIriIdMeta));
    } else if (isInserting) {
      context.missing(_documentIriIdMeta);
    }
    if (data.containsKey('document_content')) {
      context.handle(
          _documentContentMeta,
          documentContent.isAcceptableOrUnknown(
              data['document_content']!, _documentContentMeta));
    } else if (isInserting) {
      context.missing(_documentContentMeta);
    }
    if (data.containsKey('our_physical_clock')) {
      context.handle(
          _ourPhysicalClockMeta,
          ourPhysicalClock.isAcceptableOrUnknown(
              data['our_physical_clock']!, _ourPhysicalClockMeta));
    } else if (isInserting) {
      context.missing(_ourPhysicalClockMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncDocument map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncDocument(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      documentIriId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}document_iri_id'])!,
      documentContent: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}document_content'])!,
      ourPhysicalClock: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}our_physical_clock'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $SyncDocumentsTable createAlias(String alias) {
    return $SyncDocumentsTable(attachedDatabase, alias);
  }
}

class SyncDocument extends DataClass implements Insertable<SyncDocument> {
  final int id;
  final int documentIriId;
  final String documentContent;
  final int ourPhysicalClock;
  final int updatedAt;
  const SyncDocument(
      {required this.id,
      required this.documentIriId,
      required this.documentContent,
      required this.ourPhysicalClock,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['document_iri_id'] = Variable<int>(documentIriId);
    map['document_content'] = Variable<String>(documentContent);
    map['our_physical_clock'] = Variable<int>(ourPhysicalClock);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  SyncDocumentsCompanion toCompanion(bool nullToAbsent) {
    return SyncDocumentsCompanion(
      id: Value(id),
      documentIriId: Value(documentIriId),
      documentContent: Value(documentContent),
      ourPhysicalClock: Value(ourPhysicalClock),
      updatedAt: Value(updatedAt),
    );
  }

  factory SyncDocument.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncDocument(
      id: serializer.fromJson<int>(json['id']),
      documentIriId: serializer.fromJson<int>(json['documentIriId']),
      documentContent: serializer.fromJson<String>(json['documentContent']),
      ourPhysicalClock: serializer.fromJson<int>(json['ourPhysicalClock']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'documentIriId': serializer.toJson<int>(documentIriId),
      'documentContent': serializer.toJson<String>(documentContent),
      'ourPhysicalClock': serializer.toJson<int>(ourPhysicalClock),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  SyncDocument copyWith(
          {int? id,
          int? documentIriId,
          String? documentContent,
          int? ourPhysicalClock,
          int? updatedAt}) =>
      SyncDocument(
        id: id ?? this.id,
        documentIriId: documentIriId ?? this.documentIriId,
        documentContent: documentContent ?? this.documentContent,
        ourPhysicalClock: ourPhysicalClock ?? this.ourPhysicalClock,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  SyncDocument copyWithCompanion(SyncDocumentsCompanion data) {
    return SyncDocument(
      id: data.id.present ? data.id.value : this.id,
      documentIriId: data.documentIriId.present
          ? data.documentIriId.value
          : this.documentIriId,
      documentContent: data.documentContent.present
          ? data.documentContent.value
          : this.documentContent,
      ourPhysicalClock: data.ourPhysicalClock.present
          ? data.ourPhysicalClock.value
          : this.ourPhysicalClock,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncDocument(')
          ..write('id: $id, ')
          ..write('documentIriId: $documentIriId, ')
          ..write('documentContent: $documentContent, ')
          ..write('ourPhysicalClock: $ourPhysicalClock, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, documentIriId, documentContent, ourPhysicalClock, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncDocument &&
          other.id == this.id &&
          other.documentIriId == this.documentIriId &&
          other.documentContent == this.documentContent &&
          other.ourPhysicalClock == this.ourPhysicalClock &&
          other.updatedAt == this.updatedAt);
}

class SyncDocumentsCompanion extends UpdateCompanion<SyncDocument> {
  final Value<int> id;
  final Value<int> documentIriId;
  final Value<String> documentContent;
  final Value<int> ourPhysicalClock;
  final Value<int> updatedAt;
  const SyncDocumentsCompanion({
    this.id = const Value.absent(),
    this.documentIriId = const Value.absent(),
    this.documentContent = const Value.absent(),
    this.ourPhysicalClock = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  SyncDocumentsCompanion.insert({
    this.id = const Value.absent(),
    required int documentIriId,
    required String documentContent,
    required int ourPhysicalClock,
    required int updatedAt,
  })  : documentIriId = Value(documentIriId),
        documentContent = Value(documentContent),
        ourPhysicalClock = Value(ourPhysicalClock),
        updatedAt = Value(updatedAt);
  static Insertable<SyncDocument> custom({
    Expression<int>? id,
    Expression<int>? documentIriId,
    Expression<String>? documentContent,
    Expression<int>? ourPhysicalClock,
    Expression<int>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (documentIriId != null) 'document_iri_id': documentIriId,
      if (documentContent != null) 'document_content': documentContent,
      if (ourPhysicalClock != null) 'our_physical_clock': ourPhysicalClock,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  SyncDocumentsCompanion copyWith(
      {Value<int>? id,
      Value<int>? documentIriId,
      Value<String>? documentContent,
      Value<int>? ourPhysicalClock,
      Value<int>? updatedAt}) {
    return SyncDocumentsCompanion(
      id: id ?? this.id,
      documentIriId: documentIriId ?? this.documentIriId,
      documentContent: documentContent ?? this.documentContent,
      ourPhysicalClock: ourPhysicalClock ?? this.ourPhysicalClock,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (documentIriId.present) {
      map['document_iri_id'] = Variable<int>(documentIriId.value);
    }
    if (documentContent.present) {
      map['document_content'] = Variable<String>(documentContent.value);
    }
    if (ourPhysicalClock.present) {
      map['our_physical_clock'] = Variable<int>(ourPhysicalClock.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncDocumentsCompanion(')
          ..write('id: $id, ')
          ..write('documentIriId: $documentIriId, ')
          ..write('documentContent: $documentContent, ')
          ..write('ourPhysicalClock: $ourPhysicalClock, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $SyncPropertyChangesTable extends SyncPropertyChanges
    with TableInfo<$SyncPropertyChangesTable, SyncPropertyChange> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncPropertyChangesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _documentIdMeta =
      const VerificationMeta('documentId');
  @override
  late final GeneratedColumn<int> documentId = GeneratedColumn<int>(
      'document_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES sync_documents (id)'));
  static const VerificationMeta _resourceIriIdMeta =
      const VerificationMeta('resourceIriId');
  @override
  late final GeneratedColumn<int> resourceIriId = GeneratedColumn<int>(
      'resource_iri_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES sync_iris (id)'));
  static const VerificationMeta _propertyIriIdMeta =
      const VerificationMeta('propertyIriId');
  @override
  late final GeneratedColumn<int> propertyIriId = GeneratedColumn<int>(
      'property_iri_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES sync_iris (id)'));
  static const VerificationMeta _changedAtMsMeta =
      const VerificationMeta('changedAtMs');
  @override
  late final GeneratedColumn<int> changedAtMs = GeneratedColumn<int>(
      'changed_at_ms', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _changeLogicalClockMeta =
      const VerificationMeta('changeLogicalClock');
  @override
  late final GeneratedColumn<int> changeLogicalClock = GeneratedColumn<int>(
      'change_logical_clock', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        documentId,
        resourceIriId,
        propertyIriId,
        changedAtMs,
        changeLogicalClock
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_property_changes';
  @override
  VerificationContext validateIntegrity(Insertable<SyncPropertyChange> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('document_id')) {
      context.handle(
          _documentIdMeta,
          documentId.isAcceptableOrUnknown(
              data['document_id']!, _documentIdMeta));
    } else if (isInserting) {
      context.missing(_documentIdMeta);
    }
    if (data.containsKey('resource_iri_id')) {
      context.handle(
          _resourceIriIdMeta,
          resourceIriId.isAcceptableOrUnknown(
              data['resource_iri_id']!, _resourceIriIdMeta));
    } else if (isInserting) {
      context.missing(_resourceIriIdMeta);
    }
    if (data.containsKey('property_iri_id')) {
      context.handle(
          _propertyIriIdMeta,
          propertyIriId.isAcceptableOrUnknown(
              data['property_iri_id']!, _propertyIriIdMeta));
    } else if (isInserting) {
      context.missing(_propertyIriIdMeta);
    }
    if (data.containsKey('changed_at_ms')) {
      context.handle(
          _changedAtMsMeta,
          changedAtMs.isAcceptableOrUnknown(
              data['changed_at_ms']!, _changedAtMsMeta));
    } else if (isInserting) {
      context.missing(_changedAtMsMeta);
    }
    if (data.containsKey('change_logical_clock')) {
      context.handle(
          _changeLogicalClockMeta,
          changeLogicalClock.isAcceptableOrUnknown(
              data['change_logical_clock']!, _changeLogicalClockMeta));
    } else if (isInserting) {
      context.missing(_changeLogicalClockMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey =>
      {documentId, resourceIriId, propertyIriId, changeLogicalClock};
  @override
  SyncPropertyChange map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncPropertyChange(
      documentId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}document_id'])!,
      resourceIriId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}resource_iri_id'])!,
      propertyIriId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}property_iri_id'])!,
      changedAtMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}changed_at_ms'])!,
      changeLogicalClock: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}change_logical_clock'])!,
    );
  }

  @override
  $SyncPropertyChangesTable createAlias(String alias) {
    return $SyncPropertyChangesTable(attachedDatabase, alias);
  }
}

class SyncPropertyChange extends DataClass
    implements Insertable<SyncPropertyChange> {
  final int documentId;
  final int resourceIriId;
  final int propertyIriId;
  final int changedAtMs;
  final int changeLogicalClock;
  const SyncPropertyChange(
      {required this.documentId,
      required this.resourceIriId,
      required this.propertyIriId,
      required this.changedAtMs,
      required this.changeLogicalClock});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['document_id'] = Variable<int>(documentId);
    map['resource_iri_id'] = Variable<int>(resourceIriId);
    map['property_iri_id'] = Variable<int>(propertyIriId);
    map['changed_at_ms'] = Variable<int>(changedAtMs);
    map['change_logical_clock'] = Variable<int>(changeLogicalClock);
    return map;
  }

  SyncPropertyChangesCompanion toCompanion(bool nullToAbsent) {
    return SyncPropertyChangesCompanion(
      documentId: Value(documentId),
      resourceIriId: Value(resourceIriId),
      propertyIriId: Value(propertyIriId),
      changedAtMs: Value(changedAtMs),
      changeLogicalClock: Value(changeLogicalClock),
    );
  }

  factory SyncPropertyChange.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncPropertyChange(
      documentId: serializer.fromJson<int>(json['documentId']),
      resourceIriId: serializer.fromJson<int>(json['resourceIriId']),
      propertyIriId: serializer.fromJson<int>(json['propertyIriId']),
      changedAtMs: serializer.fromJson<int>(json['changedAtMs']),
      changeLogicalClock: serializer.fromJson<int>(json['changeLogicalClock']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'documentId': serializer.toJson<int>(documentId),
      'resourceIriId': serializer.toJson<int>(resourceIriId),
      'propertyIriId': serializer.toJson<int>(propertyIriId),
      'changedAtMs': serializer.toJson<int>(changedAtMs),
      'changeLogicalClock': serializer.toJson<int>(changeLogicalClock),
    };
  }

  SyncPropertyChange copyWith(
          {int? documentId,
          int? resourceIriId,
          int? propertyIriId,
          int? changedAtMs,
          int? changeLogicalClock}) =>
      SyncPropertyChange(
        documentId: documentId ?? this.documentId,
        resourceIriId: resourceIriId ?? this.resourceIriId,
        propertyIriId: propertyIriId ?? this.propertyIriId,
        changedAtMs: changedAtMs ?? this.changedAtMs,
        changeLogicalClock: changeLogicalClock ?? this.changeLogicalClock,
      );
  SyncPropertyChange copyWithCompanion(SyncPropertyChangesCompanion data) {
    return SyncPropertyChange(
      documentId:
          data.documentId.present ? data.documentId.value : this.documentId,
      resourceIriId: data.resourceIriId.present
          ? data.resourceIriId.value
          : this.resourceIriId,
      propertyIriId: data.propertyIriId.present
          ? data.propertyIriId.value
          : this.propertyIriId,
      changedAtMs:
          data.changedAtMs.present ? data.changedAtMs.value : this.changedAtMs,
      changeLogicalClock: data.changeLogicalClock.present
          ? data.changeLogicalClock.value
          : this.changeLogicalClock,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncPropertyChange(')
          ..write('documentId: $documentId, ')
          ..write('resourceIriId: $resourceIriId, ')
          ..write('propertyIriId: $propertyIriId, ')
          ..write('changedAtMs: $changedAtMs, ')
          ..write('changeLogicalClock: $changeLogicalClock')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(documentId, resourceIriId, propertyIriId,
      changedAtMs, changeLogicalClock);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncPropertyChange &&
          other.documentId == this.documentId &&
          other.resourceIriId == this.resourceIriId &&
          other.propertyIriId == this.propertyIriId &&
          other.changedAtMs == this.changedAtMs &&
          other.changeLogicalClock == this.changeLogicalClock);
}

class SyncPropertyChangesCompanion extends UpdateCompanion<SyncPropertyChange> {
  final Value<int> documentId;
  final Value<int> resourceIriId;
  final Value<int> propertyIriId;
  final Value<int> changedAtMs;
  final Value<int> changeLogicalClock;
  final Value<int> rowid;
  const SyncPropertyChangesCompanion({
    this.documentId = const Value.absent(),
    this.resourceIriId = const Value.absent(),
    this.propertyIriId = const Value.absent(),
    this.changedAtMs = const Value.absent(),
    this.changeLogicalClock = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncPropertyChangesCompanion.insert({
    required int documentId,
    required int resourceIriId,
    required int propertyIriId,
    required int changedAtMs,
    required int changeLogicalClock,
    this.rowid = const Value.absent(),
  })  : documentId = Value(documentId),
        resourceIriId = Value(resourceIriId),
        propertyIriId = Value(propertyIriId),
        changedAtMs = Value(changedAtMs),
        changeLogicalClock = Value(changeLogicalClock);
  static Insertable<SyncPropertyChange> custom({
    Expression<int>? documentId,
    Expression<int>? resourceIriId,
    Expression<int>? propertyIriId,
    Expression<int>? changedAtMs,
    Expression<int>? changeLogicalClock,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (documentId != null) 'document_id': documentId,
      if (resourceIriId != null) 'resource_iri_id': resourceIriId,
      if (propertyIriId != null) 'property_iri_id': propertyIriId,
      if (changedAtMs != null) 'changed_at_ms': changedAtMs,
      if (changeLogicalClock != null)
        'change_logical_clock': changeLogicalClock,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncPropertyChangesCompanion copyWith(
      {Value<int>? documentId,
      Value<int>? resourceIriId,
      Value<int>? propertyIriId,
      Value<int>? changedAtMs,
      Value<int>? changeLogicalClock,
      Value<int>? rowid}) {
    return SyncPropertyChangesCompanion(
      documentId: documentId ?? this.documentId,
      resourceIriId: resourceIriId ?? this.resourceIriId,
      propertyIriId: propertyIriId ?? this.propertyIriId,
      changedAtMs: changedAtMs ?? this.changedAtMs,
      changeLogicalClock: changeLogicalClock ?? this.changeLogicalClock,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (documentId.present) {
      map['document_id'] = Variable<int>(documentId.value);
    }
    if (resourceIriId.present) {
      map['resource_iri_id'] = Variable<int>(resourceIriId.value);
    }
    if (propertyIriId.present) {
      map['property_iri_id'] = Variable<int>(propertyIriId.value);
    }
    if (changedAtMs.present) {
      map['changed_at_ms'] = Variable<int>(changedAtMs.value);
    }
    if (changeLogicalClock.present) {
      map['change_logical_clock'] = Variable<int>(changeLogicalClock.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncPropertyChangesCompanion(')
          ..write('documentId: $documentId, ')
          ..write('resourceIriId: $resourceIriId, ')
          ..write('propertyIriId: $propertyIriId, ')
          ..write('changedAtMs: $changedAtMs, ')
          ..write('changeLogicalClock: $changeLogicalClock, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$SyncDatabase extends GeneratedDatabase {
  _$SyncDatabase(QueryExecutor e) : super(e);
  $SyncDatabaseManager get managers => $SyncDatabaseManager(this);
  late final $SyncIrisTable syncIris = $SyncIrisTable(this);
  late final $SyncDocumentsTable syncDocuments = $SyncDocumentsTable(this);
  late final $SyncPropertyChangesTable syncPropertyChanges =
      $SyncPropertyChangesTable(this);
  late final SyncDocumentDao syncDocumentDao =
      SyncDocumentDao(this as SyncDatabase);
  late final SyncPropertyChangeDao syncPropertyChangeDao =
      SyncPropertyChangeDao(this as SyncDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [syncIris, syncDocuments, syncPropertyChanges];
}

typedef $$SyncIrisTableCreateCompanionBuilder = SyncIrisCompanion Function({
  Value<int> id,
  required String iri,
});
typedef $$SyncIrisTableUpdateCompanionBuilder = SyncIrisCompanion Function({
  Value<int> id,
  Value<String> iri,
});

final class $$SyncIrisTableReferences
    extends BaseReferences<_$SyncDatabase, $SyncIrisTable, SyncIri> {
  $$SyncIrisTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$SyncDocumentsTable, List<SyncDocument>>
      _syncDocumentsRefsTable(_$SyncDatabase db) =>
          MultiTypedResultKey.fromTable(db.syncDocuments,
              aliasName: $_aliasNameGenerator(
                  db.syncIris.id, db.syncDocuments.documentIriId));

  $$SyncDocumentsTableProcessedTableManager get syncDocumentsRefs {
    final manager = $$SyncDocumentsTableTableManager($_db, $_db.syncDocuments)
        .filter((f) => f.documentIriId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_syncDocumentsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$SyncPropertyChangesTable,
      List<SyncPropertyChange>> _resourceIriTable(
          _$SyncDatabase db) =>
      MultiTypedResultKey.fromTable(db.syncPropertyChanges,
          aliasName: $_aliasNameGenerator(
              db.syncIris.id, db.syncPropertyChanges.resourceIriId));

  $$SyncPropertyChangesTableProcessedTableManager get resourceIri {
    final manager = $$SyncPropertyChangesTableTableManager(
            $_db, $_db.syncPropertyChanges)
        .filter((f) => f.resourceIriId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_resourceIriTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$SyncPropertyChangesTable,
      List<SyncPropertyChange>> _propertyIriTable(
          _$SyncDatabase db) =>
      MultiTypedResultKey.fromTable(db.syncPropertyChanges,
          aliasName: $_aliasNameGenerator(
              db.syncIris.id, db.syncPropertyChanges.propertyIriId));

  $$SyncPropertyChangesTableProcessedTableManager get propertyIri {
    final manager = $$SyncPropertyChangesTableTableManager(
            $_db, $_db.syncPropertyChanges)
        .filter((f) => f.propertyIriId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_propertyIriTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$SyncIrisTableFilterComposer
    extends Composer<_$SyncDatabase, $SyncIrisTable> {
  $$SyncIrisTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get iri => $composableBuilder(
      column: $table.iri, builder: (column) => ColumnFilters(column));

  Expression<bool> syncDocumentsRefs(
      Expression<bool> Function($$SyncDocumentsTableFilterComposer f) f) {
    final $$SyncDocumentsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.syncDocuments,
        getReferencedColumn: (t) => t.documentIriId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SyncDocumentsTableFilterComposer(
              $db: $db,
              $table: $db.syncDocuments,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<bool> resourceIri(
      Expression<bool> Function($$SyncPropertyChangesTableFilterComposer f) f) {
    final $$SyncPropertyChangesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.syncPropertyChanges,
        getReferencedColumn: (t) => t.resourceIriId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SyncPropertyChangesTableFilterComposer(
              $db: $db,
              $table: $db.syncPropertyChanges,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<bool> propertyIri(
      Expression<bool> Function($$SyncPropertyChangesTableFilterComposer f) f) {
    final $$SyncPropertyChangesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.syncPropertyChanges,
        getReferencedColumn: (t) => t.propertyIriId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SyncPropertyChangesTableFilterComposer(
              $db: $db,
              $table: $db.syncPropertyChanges,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$SyncIrisTableOrderingComposer
    extends Composer<_$SyncDatabase, $SyncIrisTable> {
  $$SyncIrisTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get iri => $composableBuilder(
      column: $table.iri, builder: (column) => ColumnOrderings(column));
}

class $$SyncIrisTableAnnotationComposer
    extends Composer<_$SyncDatabase, $SyncIrisTable> {
  $$SyncIrisTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get iri =>
      $composableBuilder(column: $table.iri, builder: (column) => column);

  Expression<T> syncDocumentsRefs<T extends Object>(
      Expression<T> Function($$SyncDocumentsTableAnnotationComposer a) f) {
    final $$SyncDocumentsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.syncDocuments,
        getReferencedColumn: (t) => t.documentIriId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SyncDocumentsTableAnnotationComposer(
              $db: $db,
              $table: $db.syncDocuments,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<T> resourceIri<T extends Object>(
      Expression<T> Function($$SyncPropertyChangesTableAnnotationComposer a)
          f) {
    final $$SyncPropertyChangesTableAnnotationComposer composer =
        $composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.id,
            referencedTable: $db.syncPropertyChanges,
            getReferencedColumn: (t) => t.resourceIriId,
            builder: (joinBuilder,
                    {$addJoinBuilderToRootComposer,
                    $removeJoinBuilderFromRootComposer}) =>
                $$SyncPropertyChangesTableAnnotationComposer(
                  $db: $db,
                  $table: $db.syncPropertyChanges,
                  $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                  joinBuilder: joinBuilder,
                  $removeJoinBuilderFromRootComposer:
                      $removeJoinBuilderFromRootComposer,
                ));
    return f(composer);
  }

  Expression<T> propertyIri<T extends Object>(
      Expression<T> Function($$SyncPropertyChangesTableAnnotationComposer a)
          f) {
    final $$SyncPropertyChangesTableAnnotationComposer composer =
        $composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.id,
            referencedTable: $db.syncPropertyChanges,
            getReferencedColumn: (t) => t.propertyIriId,
            builder: (joinBuilder,
                    {$addJoinBuilderToRootComposer,
                    $removeJoinBuilderFromRootComposer}) =>
                $$SyncPropertyChangesTableAnnotationComposer(
                  $db: $db,
                  $table: $db.syncPropertyChanges,
                  $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                  joinBuilder: joinBuilder,
                  $removeJoinBuilderFromRootComposer:
                      $removeJoinBuilderFromRootComposer,
                ));
    return f(composer);
  }
}

class $$SyncIrisTableTableManager extends RootTableManager<
    _$SyncDatabase,
    $SyncIrisTable,
    SyncIri,
    $$SyncIrisTableFilterComposer,
    $$SyncIrisTableOrderingComposer,
    $$SyncIrisTableAnnotationComposer,
    $$SyncIrisTableCreateCompanionBuilder,
    $$SyncIrisTableUpdateCompanionBuilder,
    (SyncIri, $$SyncIrisTableReferences),
    SyncIri,
    PrefetchHooks Function(
        {bool syncDocumentsRefs, bool resourceIri, bool propertyIri})> {
  $$SyncIrisTableTableManager(_$SyncDatabase db, $SyncIrisTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncIrisTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncIrisTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncIrisTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> iri = const Value.absent(),
          }) =>
              SyncIrisCompanion(
            id: id,
            iri: iri,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String iri,
          }) =>
              SyncIrisCompanion.insert(
            id: id,
            iri: iri,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) =>
                  (e.readTable(table), $$SyncIrisTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: (
              {syncDocumentsRefs = false,
              resourceIri = false,
              propertyIri = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (syncDocumentsRefs) db.syncDocuments,
                if (resourceIri) db.syncPropertyChanges,
                if (propertyIri) db.syncPropertyChanges
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (syncDocumentsRefs)
                    await $_getPrefetchedData<SyncIri, $SyncIrisTable,
                            SyncDocument>(
                        currentTable: table,
                        referencedTable: $$SyncIrisTableReferences
                            ._syncDocumentsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$SyncIrisTableReferences(db, table, p0)
                                .syncDocumentsRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.documentIriId == item.id),
                        typedResults: items),
                  if (resourceIri)
                    await $_getPrefetchedData<SyncIri, $SyncIrisTable,
                            SyncPropertyChange>(
                        currentTable: table,
                        referencedTable:
                            $$SyncIrisTableReferences._resourceIriTable(db),
                        managerFromTypedResult: (p0) =>
                            $$SyncIrisTableReferences(db, table, p0)
                                .resourceIri,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.resourceIriId == item.id),
                        typedResults: items),
                  if (propertyIri)
                    await $_getPrefetchedData<SyncIri, $SyncIrisTable,
                            SyncPropertyChange>(
                        currentTable: table,
                        referencedTable:
                            $$SyncIrisTableReferences._propertyIriTable(db),
                        managerFromTypedResult: (p0) =>
                            $$SyncIrisTableReferences(db, table, p0)
                                .propertyIri,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.propertyIriId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$SyncIrisTableProcessedTableManager = ProcessedTableManager<
    _$SyncDatabase,
    $SyncIrisTable,
    SyncIri,
    $$SyncIrisTableFilterComposer,
    $$SyncIrisTableOrderingComposer,
    $$SyncIrisTableAnnotationComposer,
    $$SyncIrisTableCreateCompanionBuilder,
    $$SyncIrisTableUpdateCompanionBuilder,
    (SyncIri, $$SyncIrisTableReferences),
    SyncIri,
    PrefetchHooks Function(
        {bool syncDocumentsRefs, bool resourceIri, bool propertyIri})>;
typedef $$SyncDocumentsTableCreateCompanionBuilder = SyncDocumentsCompanion
    Function({
  Value<int> id,
  required int documentIriId,
  required String documentContent,
  required int ourPhysicalClock,
  required int updatedAt,
});
typedef $$SyncDocumentsTableUpdateCompanionBuilder = SyncDocumentsCompanion
    Function({
  Value<int> id,
  Value<int> documentIriId,
  Value<String> documentContent,
  Value<int> ourPhysicalClock,
  Value<int> updatedAt,
});

final class $$SyncDocumentsTableReferences
    extends BaseReferences<_$SyncDatabase, $SyncDocumentsTable, SyncDocument> {
  $$SyncDocumentsTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $SyncIrisTable _documentIriIdTable(_$SyncDatabase db) =>
      db.syncIris.createAlias(
          $_aliasNameGenerator(db.syncDocuments.documentIriId, db.syncIris.id));

  $$SyncIrisTableProcessedTableManager get documentIriId {
    final $_column = $_itemColumn<int>('document_iri_id')!;

    final manager = $$SyncIrisTableTableManager($_db, $_db.syncIris)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_documentIriIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static MultiTypedResultKey<$SyncPropertyChangesTable,
      List<SyncPropertyChange>> _syncPropertyChangesRefsTable(
          _$SyncDatabase db) =>
      MultiTypedResultKey.fromTable(db.syncPropertyChanges,
          aliasName: $_aliasNameGenerator(
              db.syncDocuments.id, db.syncPropertyChanges.documentId));

  $$SyncPropertyChangesTableProcessedTableManager get syncPropertyChangesRefs {
    final manager =
        $$SyncPropertyChangesTableTableManager($_db, $_db.syncPropertyChanges)
            .filter((f) => f.documentId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache =
        $_typedResult.readTableOrNull(_syncPropertyChangesRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$SyncDocumentsTableFilterComposer
    extends Composer<_$SyncDatabase, $SyncDocumentsTable> {
  $$SyncDocumentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get documentContent => $composableBuilder(
      column: $table.documentContent,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get ourPhysicalClock => $composableBuilder(
      column: $table.ourPhysicalClock,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  $$SyncIrisTableFilterComposer get documentIriId {
    final $$SyncIrisTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.documentIriId,
        referencedTable: $db.syncIris,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SyncIrisTableFilterComposer(
              $db: $db,
              $table: $db.syncIris,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<bool> syncPropertyChangesRefs(
      Expression<bool> Function($$SyncPropertyChangesTableFilterComposer f) f) {
    final $$SyncPropertyChangesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.syncPropertyChanges,
        getReferencedColumn: (t) => t.documentId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SyncPropertyChangesTableFilterComposer(
              $db: $db,
              $table: $db.syncPropertyChanges,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$SyncDocumentsTableOrderingComposer
    extends Composer<_$SyncDatabase, $SyncDocumentsTable> {
  $$SyncDocumentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get documentContent => $composableBuilder(
      column: $table.documentContent,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get ourPhysicalClock => $composableBuilder(
      column: $table.ourPhysicalClock,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  $$SyncIrisTableOrderingComposer get documentIriId {
    final $$SyncIrisTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.documentIriId,
        referencedTable: $db.syncIris,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SyncIrisTableOrderingComposer(
              $db: $db,
              $table: $db.syncIris,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$SyncDocumentsTableAnnotationComposer
    extends Composer<_$SyncDatabase, $SyncDocumentsTable> {
  $$SyncDocumentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get documentContent => $composableBuilder(
      column: $table.documentContent, builder: (column) => column);

  GeneratedColumn<int> get ourPhysicalClock => $composableBuilder(
      column: $table.ourPhysicalClock, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$SyncIrisTableAnnotationComposer get documentIriId {
    final $$SyncIrisTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.documentIriId,
        referencedTable: $db.syncIris,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SyncIrisTableAnnotationComposer(
              $db: $db,
              $table: $db.syncIris,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<T> syncPropertyChangesRefs<T extends Object>(
      Expression<T> Function($$SyncPropertyChangesTableAnnotationComposer a)
          f) {
    final $$SyncPropertyChangesTableAnnotationComposer composer =
        $composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.id,
            referencedTable: $db.syncPropertyChanges,
            getReferencedColumn: (t) => t.documentId,
            builder: (joinBuilder,
                    {$addJoinBuilderToRootComposer,
                    $removeJoinBuilderFromRootComposer}) =>
                $$SyncPropertyChangesTableAnnotationComposer(
                  $db: $db,
                  $table: $db.syncPropertyChanges,
                  $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                  joinBuilder: joinBuilder,
                  $removeJoinBuilderFromRootComposer:
                      $removeJoinBuilderFromRootComposer,
                ));
    return f(composer);
  }
}

class $$SyncDocumentsTableTableManager extends RootTableManager<
    _$SyncDatabase,
    $SyncDocumentsTable,
    SyncDocument,
    $$SyncDocumentsTableFilterComposer,
    $$SyncDocumentsTableOrderingComposer,
    $$SyncDocumentsTableAnnotationComposer,
    $$SyncDocumentsTableCreateCompanionBuilder,
    $$SyncDocumentsTableUpdateCompanionBuilder,
    (SyncDocument, $$SyncDocumentsTableReferences),
    SyncDocument,
    PrefetchHooks Function(
        {bool documentIriId, bool syncPropertyChangesRefs})> {
  $$SyncDocumentsTableTableManager(_$SyncDatabase db, $SyncDocumentsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncDocumentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncDocumentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncDocumentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> documentIriId = const Value.absent(),
            Value<String> documentContent = const Value.absent(),
            Value<int> ourPhysicalClock = const Value.absent(),
            Value<int> updatedAt = const Value.absent(),
          }) =>
              SyncDocumentsCompanion(
            id: id,
            documentIriId: documentIriId,
            documentContent: documentContent,
            ourPhysicalClock: ourPhysicalClock,
            updatedAt: updatedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int documentIriId,
            required String documentContent,
            required int ourPhysicalClock,
            required int updatedAt,
          }) =>
              SyncDocumentsCompanion.insert(
            id: id,
            documentIriId: documentIriId,
            documentContent: documentContent,
            ourPhysicalClock: ourPhysicalClock,
            updatedAt: updatedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$SyncDocumentsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: (
              {documentIriId = false, syncPropertyChangesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (syncPropertyChangesRefs) db.syncPropertyChanges
              ],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (documentIriId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.documentIriId,
                    referencedTable:
                        $$SyncDocumentsTableReferences._documentIriIdTable(db),
                    referencedColumn: $$SyncDocumentsTableReferences
                        ._documentIriIdTable(db)
                        .id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (syncPropertyChangesRefs)
                    await $_getPrefetchedData<SyncDocument, $SyncDocumentsTable,
                            SyncPropertyChange>(
                        currentTable: table,
                        referencedTable: $$SyncDocumentsTableReferences
                            ._syncPropertyChangesRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$SyncDocumentsTableReferences(db, table, p0)
                                .syncPropertyChangesRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.documentId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$SyncDocumentsTableProcessedTableManager = ProcessedTableManager<
    _$SyncDatabase,
    $SyncDocumentsTable,
    SyncDocument,
    $$SyncDocumentsTableFilterComposer,
    $$SyncDocumentsTableOrderingComposer,
    $$SyncDocumentsTableAnnotationComposer,
    $$SyncDocumentsTableCreateCompanionBuilder,
    $$SyncDocumentsTableUpdateCompanionBuilder,
    (SyncDocument, $$SyncDocumentsTableReferences),
    SyncDocument,
    PrefetchHooks Function({bool documentIriId, bool syncPropertyChangesRefs})>;
typedef $$SyncPropertyChangesTableCreateCompanionBuilder
    = SyncPropertyChangesCompanion Function({
  required int documentId,
  required int resourceIriId,
  required int propertyIriId,
  required int changedAtMs,
  required int changeLogicalClock,
  Value<int> rowid,
});
typedef $$SyncPropertyChangesTableUpdateCompanionBuilder
    = SyncPropertyChangesCompanion Function({
  Value<int> documentId,
  Value<int> resourceIriId,
  Value<int> propertyIriId,
  Value<int> changedAtMs,
  Value<int> changeLogicalClock,
  Value<int> rowid,
});

final class $$SyncPropertyChangesTableReferences extends BaseReferences<
    _$SyncDatabase, $SyncPropertyChangesTable, SyncPropertyChange> {
  $$SyncPropertyChangesTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $SyncDocumentsTable _documentIdTable(_$SyncDatabase db) =>
      db.syncDocuments.createAlias($_aliasNameGenerator(
          db.syncPropertyChanges.documentId, db.syncDocuments.id));

  $$SyncDocumentsTableProcessedTableManager get documentId {
    final $_column = $_itemColumn<int>('document_id')!;

    final manager = $$SyncDocumentsTableTableManager($_db, $_db.syncDocuments)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_documentIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static $SyncIrisTable _resourceIriIdTable(_$SyncDatabase db) =>
      db.syncIris.createAlias($_aliasNameGenerator(
          db.syncPropertyChanges.resourceIriId, db.syncIris.id));

  $$SyncIrisTableProcessedTableManager get resourceIriId {
    final $_column = $_itemColumn<int>('resource_iri_id')!;

    final manager = $$SyncIrisTableTableManager($_db, $_db.syncIris)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_resourceIriIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static $SyncIrisTable _propertyIriIdTable(_$SyncDatabase db) =>
      db.syncIris.createAlias($_aliasNameGenerator(
          db.syncPropertyChanges.propertyIriId, db.syncIris.id));

  $$SyncIrisTableProcessedTableManager get propertyIriId {
    final $_column = $_itemColumn<int>('property_iri_id')!;

    final manager = $$SyncIrisTableTableManager($_db, $_db.syncIris)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_propertyIriIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$SyncPropertyChangesTableFilterComposer
    extends Composer<_$SyncDatabase, $SyncPropertyChangesTable> {
  $$SyncPropertyChangesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get changedAtMs => $composableBuilder(
      column: $table.changedAtMs, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get changeLogicalClock => $composableBuilder(
      column: $table.changeLogicalClock,
      builder: (column) => ColumnFilters(column));

  $$SyncDocumentsTableFilterComposer get documentId {
    final $$SyncDocumentsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.documentId,
        referencedTable: $db.syncDocuments,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SyncDocumentsTableFilterComposer(
              $db: $db,
              $table: $db.syncDocuments,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$SyncIrisTableFilterComposer get resourceIriId {
    final $$SyncIrisTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.resourceIriId,
        referencedTable: $db.syncIris,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SyncIrisTableFilterComposer(
              $db: $db,
              $table: $db.syncIris,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$SyncIrisTableFilterComposer get propertyIriId {
    final $$SyncIrisTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.propertyIriId,
        referencedTable: $db.syncIris,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SyncIrisTableFilterComposer(
              $db: $db,
              $table: $db.syncIris,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$SyncPropertyChangesTableOrderingComposer
    extends Composer<_$SyncDatabase, $SyncPropertyChangesTable> {
  $$SyncPropertyChangesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get changedAtMs => $composableBuilder(
      column: $table.changedAtMs, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get changeLogicalClock => $composableBuilder(
      column: $table.changeLogicalClock,
      builder: (column) => ColumnOrderings(column));

  $$SyncDocumentsTableOrderingComposer get documentId {
    final $$SyncDocumentsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.documentId,
        referencedTable: $db.syncDocuments,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SyncDocumentsTableOrderingComposer(
              $db: $db,
              $table: $db.syncDocuments,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$SyncIrisTableOrderingComposer get resourceIriId {
    final $$SyncIrisTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.resourceIriId,
        referencedTable: $db.syncIris,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SyncIrisTableOrderingComposer(
              $db: $db,
              $table: $db.syncIris,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$SyncIrisTableOrderingComposer get propertyIriId {
    final $$SyncIrisTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.propertyIriId,
        referencedTable: $db.syncIris,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SyncIrisTableOrderingComposer(
              $db: $db,
              $table: $db.syncIris,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$SyncPropertyChangesTableAnnotationComposer
    extends Composer<_$SyncDatabase, $SyncPropertyChangesTable> {
  $$SyncPropertyChangesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get changedAtMs => $composableBuilder(
      column: $table.changedAtMs, builder: (column) => column);

  GeneratedColumn<int> get changeLogicalClock => $composableBuilder(
      column: $table.changeLogicalClock, builder: (column) => column);

  $$SyncDocumentsTableAnnotationComposer get documentId {
    final $$SyncDocumentsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.documentId,
        referencedTable: $db.syncDocuments,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SyncDocumentsTableAnnotationComposer(
              $db: $db,
              $table: $db.syncDocuments,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$SyncIrisTableAnnotationComposer get resourceIriId {
    final $$SyncIrisTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.resourceIriId,
        referencedTable: $db.syncIris,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SyncIrisTableAnnotationComposer(
              $db: $db,
              $table: $db.syncIris,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$SyncIrisTableAnnotationComposer get propertyIriId {
    final $$SyncIrisTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.propertyIriId,
        referencedTable: $db.syncIris,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SyncIrisTableAnnotationComposer(
              $db: $db,
              $table: $db.syncIris,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$SyncPropertyChangesTableTableManager extends RootTableManager<
    _$SyncDatabase,
    $SyncPropertyChangesTable,
    SyncPropertyChange,
    $$SyncPropertyChangesTableFilterComposer,
    $$SyncPropertyChangesTableOrderingComposer,
    $$SyncPropertyChangesTableAnnotationComposer,
    $$SyncPropertyChangesTableCreateCompanionBuilder,
    $$SyncPropertyChangesTableUpdateCompanionBuilder,
    (SyncPropertyChange, $$SyncPropertyChangesTableReferences),
    SyncPropertyChange,
    PrefetchHooks Function(
        {bool documentId, bool resourceIriId, bool propertyIriId})> {
  $$SyncPropertyChangesTableTableManager(
      _$SyncDatabase db, $SyncPropertyChangesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncPropertyChangesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncPropertyChangesTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncPropertyChangesTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> documentId = const Value.absent(),
            Value<int> resourceIriId = const Value.absent(),
            Value<int> propertyIriId = const Value.absent(),
            Value<int> changedAtMs = const Value.absent(),
            Value<int> changeLogicalClock = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SyncPropertyChangesCompanion(
            documentId: documentId,
            resourceIriId: resourceIriId,
            propertyIriId: propertyIriId,
            changedAtMs: changedAtMs,
            changeLogicalClock: changeLogicalClock,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required int documentId,
            required int resourceIriId,
            required int propertyIriId,
            required int changedAtMs,
            required int changeLogicalClock,
            Value<int> rowid = const Value.absent(),
          }) =>
              SyncPropertyChangesCompanion.insert(
            documentId: documentId,
            resourceIriId: resourceIriId,
            propertyIriId: propertyIriId,
            changedAtMs: changedAtMs,
            changeLogicalClock: changeLogicalClock,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$SyncPropertyChangesTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: (
              {documentId = false,
              resourceIriId = false,
              propertyIriId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (documentId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.documentId,
                    referencedTable: $$SyncPropertyChangesTableReferences
                        ._documentIdTable(db),
                    referencedColumn: $$SyncPropertyChangesTableReferences
                        ._documentIdTable(db)
                        .id,
                  ) as T;
                }
                if (resourceIriId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.resourceIriId,
                    referencedTable: $$SyncPropertyChangesTableReferences
                        ._resourceIriIdTable(db),
                    referencedColumn: $$SyncPropertyChangesTableReferences
                        ._resourceIriIdTable(db)
                        .id,
                  ) as T;
                }
                if (propertyIriId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.propertyIriId,
                    referencedTable: $$SyncPropertyChangesTableReferences
                        ._propertyIriIdTable(db),
                    referencedColumn: $$SyncPropertyChangesTableReferences
                        ._propertyIriIdTable(db)
                        .id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$SyncPropertyChangesTableProcessedTableManager = ProcessedTableManager<
    _$SyncDatabase,
    $SyncPropertyChangesTable,
    SyncPropertyChange,
    $$SyncPropertyChangesTableFilterComposer,
    $$SyncPropertyChangesTableOrderingComposer,
    $$SyncPropertyChangesTableAnnotationComposer,
    $$SyncPropertyChangesTableCreateCompanionBuilder,
    $$SyncPropertyChangesTableUpdateCompanionBuilder,
    (SyncPropertyChange, $$SyncPropertyChangesTableReferences),
    SyncPropertyChange,
    PrefetchHooks Function(
        {bool documentId, bool resourceIriId, bool propertyIriId})>;

class $SyncDatabaseManager {
  final _$SyncDatabase _db;
  $SyncDatabaseManager(this._db);
  $$SyncIrisTableTableManager get syncIris =>
      $$SyncIrisTableTableManager(_db, _db.syncIris);
  $$SyncDocumentsTableTableManager get syncDocuments =>
      $$SyncDocumentsTableTableManager(_db, _db.syncDocuments);
  $$SyncPropertyChangesTableTableManager get syncPropertyChanges =>
      $$SyncPropertyChangesTableTableManager(_db, _db.syncPropertyChanges);
}
