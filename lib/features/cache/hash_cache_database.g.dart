// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'hash_cache_database.dart';

// ignore_for_file: type=lint
class $HashCacheEntriesTable extends HashCacheEntries
    with TableInfo<$HashCacheEntriesTable, HashCacheEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HashCacheEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeMeta = const VerificationMeta('size');
  @override
  late final GeneratedColumn<int> size = GeneratedColumn<int>(
    'size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modifiedMillisMeta = const VerificationMeta(
    'modifiedMillis',
  );
  @override
  late final GeneratedColumn<int> modifiedMillis = GeneratedColumn<int>(
    'modified_millis',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _algoVersionMeta = const VerificationMeta(
    'algoVersion',
  );
  @override
  late final GeneratedColumn<int> algoVersion = GeneratedColumn<int>(
    'algo_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _partialHashMeta = const VerificationMeta(
    'partialHash',
  );
  @override
  late final GeneratedColumn<String> partialHash = GeneratedColumn<String>(
    'partial_hash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fullHashMeta = const VerificationMeta(
    'fullHash',
  );
  @override
  late final GeneratedColumn<String> fullHash = GeneratedColumn<String>(
    'full_hash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    path,
    size,
    modifiedMillis,
    deviceId,
    algoVersion,
    partialHash,
    fullHash,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'hash_cache_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<HashCacheEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('size')) {
      context.handle(
        _sizeMeta,
        size.isAcceptableOrUnknown(data['size']!, _sizeMeta),
      );
    } else if (isInserting) {
      context.missing(_sizeMeta);
    }
    if (data.containsKey('modified_millis')) {
      context.handle(
        _modifiedMillisMeta,
        modifiedMillis.isAcceptableOrUnknown(
          data['modified_millis']!,
          _modifiedMillisMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_modifiedMillisMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    }
    if (data.containsKey('algo_version')) {
      context.handle(
        _algoVersionMeta,
        algoVersion.isAcceptableOrUnknown(
          data['algo_version']!,
          _algoVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_algoVersionMeta);
    }
    if (data.containsKey('partial_hash')) {
      context.handle(
        _partialHashMeta,
        partialHash.isAcceptableOrUnknown(
          data['partial_hash']!,
          _partialHashMeta,
        ),
      );
    }
    if (data.containsKey('full_hash')) {
      context.handle(
        _fullHashMeta,
        fullHash.isAcceptableOrUnknown(data['full_hash']!, _fullHashMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {path};
  @override
  HashCacheEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HashCacheEntry(
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      size: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size'],
      )!,
      modifiedMillis: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}modified_millis'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      ),
      algoVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}algo_version'],
      )!,
      partialHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}partial_hash'],
      ),
      fullHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}full_hash'],
      ),
    );
  }

  @override
  $HashCacheEntriesTable createAlias(String alias) {
    return $HashCacheEntriesTable(attachedDatabase, alias);
  }
}

class HashCacheEntry extends DataClass implements Insertable<HashCacheEntry> {
  final String path;
  final int size;
  final int modifiedMillis;
  final String? deviceId;
  final int algoVersion;
  final String? partialHash;
  final String? fullHash;
  const HashCacheEntry({
    required this.path,
    required this.size,
    required this.modifiedMillis,
    this.deviceId,
    required this.algoVersion,
    this.partialHash,
    this.fullHash,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['path'] = Variable<String>(path);
    map['size'] = Variable<int>(size);
    map['modified_millis'] = Variable<int>(modifiedMillis);
    if (!nullToAbsent || deviceId != null) {
      map['device_id'] = Variable<String>(deviceId);
    }
    map['algo_version'] = Variable<int>(algoVersion);
    if (!nullToAbsent || partialHash != null) {
      map['partial_hash'] = Variable<String>(partialHash);
    }
    if (!nullToAbsent || fullHash != null) {
      map['full_hash'] = Variable<String>(fullHash);
    }
    return map;
  }

  HashCacheEntriesCompanion toCompanion(bool nullToAbsent) {
    return HashCacheEntriesCompanion(
      path: Value(path),
      size: Value(size),
      modifiedMillis: Value(modifiedMillis),
      deviceId: deviceId == null && nullToAbsent
          ? const Value.absent()
          : Value(deviceId),
      algoVersion: Value(algoVersion),
      partialHash: partialHash == null && nullToAbsent
          ? const Value.absent()
          : Value(partialHash),
      fullHash: fullHash == null && nullToAbsent
          ? const Value.absent()
          : Value(fullHash),
    );
  }

  factory HashCacheEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HashCacheEntry(
      path: serializer.fromJson<String>(json['path']),
      size: serializer.fromJson<int>(json['size']),
      modifiedMillis: serializer.fromJson<int>(json['modifiedMillis']),
      deviceId: serializer.fromJson<String?>(json['deviceId']),
      algoVersion: serializer.fromJson<int>(json['algoVersion']),
      partialHash: serializer.fromJson<String?>(json['partialHash']),
      fullHash: serializer.fromJson<String?>(json['fullHash']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'path': serializer.toJson<String>(path),
      'size': serializer.toJson<int>(size),
      'modifiedMillis': serializer.toJson<int>(modifiedMillis),
      'deviceId': serializer.toJson<String?>(deviceId),
      'algoVersion': serializer.toJson<int>(algoVersion),
      'partialHash': serializer.toJson<String?>(partialHash),
      'fullHash': serializer.toJson<String?>(fullHash),
    };
  }

  HashCacheEntry copyWith({
    String? path,
    int? size,
    int? modifiedMillis,
    Value<String?> deviceId = const Value.absent(),
    int? algoVersion,
    Value<String?> partialHash = const Value.absent(),
    Value<String?> fullHash = const Value.absent(),
  }) => HashCacheEntry(
    path: path ?? this.path,
    size: size ?? this.size,
    modifiedMillis: modifiedMillis ?? this.modifiedMillis,
    deviceId: deviceId.present ? deviceId.value : this.deviceId,
    algoVersion: algoVersion ?? this.algoVersion,
    partialHash: partialHash.present ? partialHash.value : this.partialHash,
    fullHash: fullHash.present ? fullHash.value : this.fullHash,
  );
  HashCacheEntry copyWithCompanion(HashCacheEntriesCompanion data) {
    return HashCacheEntry(
      path: data.path.present ? data.path.value : this.path,
      size: data.size.present ? data.size.value : this.size,
      modifiedMillis: data.modifiedMillis.present
          ? data.modifiedMillis.value
          : this.modifiedMillis,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      algoVersion: data.algoVersion.present
          ? data.algoVersion.value
          : this.algoVersion,
      partialHash: data.partialHash.present
          ? data.partialHash.value
          : this.partialHash,
      fullHash: data.fullHash.present ? data.fullHash.value : this.fullHash,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HashCacheEntry(')
          ..write('path: $path, ')
          ..write('size: $size, ')
          ..write('modifiedMillis: $modifiedMillis, ')
          ..write('deviceId: $deviceId, ')
          ..write('algoVersion: $algoVersion, ')
          ..write('partialHash: $partialHash, ')
          ..write('fullHash: $fullHash')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    path,
    size,
    modifiedMillis,
    deviceId,
    algoVersion,
    partialHash,
    fullHash,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HashCacheEntry &&
          other.path == this.path &&
          other.size == this.size &&
          other.modifiedMillis == this.modifiedMillis &&
          other.deviceId == this.deviceId &&
          other.algoVersion == this.algoVersion &&
          other.partialHash == this.partialHash &&
          other.fullHash == this.fullHash);
}

class HashCacheEntriesCompanion extends UpdateCompanion<HashCacheEntry> {
  final Value<String> path;
  final Value<int> size;
  final Value<int> modifiedMillis;
  final Value<String?> deviceId;
  final Value<int> algoVersion;
  final Value<String?> partialHash;
  final Value<String?> fullHash;
  final Value<int> rowid;
  const HashCacheEntriesCompanion({
    this.path = const Value.absent(),
    this.size = const Value.absent(),
    this.modifiedMillis = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.algoVersion = const Value.absent(),
    this.partialHash = const Value.absent(),
    this.fullHash = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  HashCacheEntriesCompanion.insert({
    required String path,
    required int size,
    required int modifiedMillis,
    this.deviceId = const Value.absent(),
    required int algoVersion,
    this.partialHash = const Value.absent(),
    this.fullHash = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : path = Value(path),
       size = Value(size),
       modifiedMillis = Value(modifiedMillis),
       algoVersion = Value(algoVersion);
  static Insertable<HashCacheEntry> custom({
    Expression<String>? path,
    Expression<int>? size,
    Expression<int>? modifiedMillis,
    Expression<String>? deviceId,
    Expression<int>? algoVersion,
    Expression<String>? partialHash,
    Expression<String>? fullHash,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (path != null) 'path': path,
      if (size != null) 'size': size,
      if (modifiedMillis != null) 'modified_millis': modifiedMillis,
      if (deviceId != null) 'device_id': deviceId,
      if (algoVersion != null) 'algo_version': algoVersion,
      if (partialHash != null) 'partial_hash': partialHash,
      if (fullHash != null) 'full_hash': fullHash,
      if (rowid != null) 'rowid': rowid,
    });
  }

  HashCacheEntriesCompanion copyWith({
    Value<String>? path,
    Value<int>? size,
    Value<int>? modifiedMillis,
    Value<String?>? deviceId,
    Value<int>? algoVersion,
    Value<String?>? partialHash,
    Value<String?>? fullHash,
    Value<int>? rowid,
  }) {
    return HashCacheEntriesCompanion(
      path: path ?? this.path,
      size: size ?? this.size,
      modifiedMillis: modifiedMillis ?? this.modifiedMillis,
      deviceId: deviceId ?? this.deviceId,
      algoVersion: algoVersion ?? this.algoVersion,
      partialHash: partialHash ?? this.partialHash,
      fullHash: fullHash ?? this.fullHash,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (size.present) {
      map['size'] = Variable<int>(size.value);
    }
    if (modifiedMillis.present) {
      map['modified_millis'] = Variable<int>(modifiedMillis.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (algoVersion.present) {
      map['algo_version'] = Variable<int>(algoVersion.value);
    }
    if (partialHash.present) {
      map['partial_hash'] = Variable<String>(partialHash.value);
    }
    if (fullHash.present) {
      map['full_hash'] = Variable<String>(fullHash.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HashCacheEntriesCompanion(')
          ..write('path: $path, ')
          ..write('size: $size, ')
          ..write('modifiedMillis: $modifiedMillis, ')
          ..write('deviceId: $deviceId, ')
          ..write('algoVersion: $algoVersion, ')
          ..write('partialHash: $partialHash, ')
          ..write('fullHash: $fullHash, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$HashCacheDatabase extends GeneratedDatabase {
  _$HashCacheDatabase(QueryExecutor e) : super(e);
  $HashCacheDatabaseManager get managers => $HashCacheDatabaseManager(this);
  late final $HashCacheEntriesTable hashCacheEntries = $HashCacheEntriesTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [hashCacheEntries];
}

typedef $$HashCacheEntriesTableCreateCompanionBuilder =
    HashCacheEntriesCompanion Function({
      required String path,
      required int size,
      required int modifiedMillis,
      Value<String?> deviceId,
      required int algoVersion,
      Value<String?> partialHash,
      Value<String?> fullHash,
      Value<int> rowid,
    });
typedef $$HashCacheEntriesTableUpdateCompanionBuilder =
    HashCacheEntriesCompanion Function({
      Value<String> path,
      Value<int> size,
      Value<int> modifiedMillis,
      Value<String?> deviceId,
      Value<int> algoVersion,
      Value<String?> partialHash,
      Value<String?> fullHash,
      Value<int> rowid,
    });

class $$HashCacheEntriesTableFilterComposer
    extends Composer<_$HashCacheDatabase, $HashCacheEntriesTable> {
  $$HashCacheEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get modifiedMillis => $composableBuilder(
    column: $table.modifiedMillis,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get algoVersion => $composableBuilder(
    column: $table.algoVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get partialHash => $composableBuilder(
    column: $table.partialHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fullHash => $composableBuilder(
    column: $table.fullHash,
    builder: (column) => ColumnFilters(column),
  );
}

class $$HashCacheEntriesTableOrderingComposer
    extends Composer<_$HashCacheDatabase, $HashCacheEntriesTable> {
  $$HashCacheEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get modifiedMillis => $composableBuilder(
    column: $table.modifiedMillis,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get algoVersion => $composableBuilder(
    column: $table.algoVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get partialHash => $composableBuilder(
    column: $table.partialHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fullHash => $composableBuilder(
    column: $table.fullHash,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$HashCacheEntriesTableAnnotationComposer
    extends Composer<_$HashCacheDatabase, $HashCacheEntriesTable> {
  $$HashCacheEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<int> get size =>
      $composableBuilder(column: $table.size, builder: (column) => column);

  GeneratedColumn<int> get modifiedMillis => $composableBuilder(
    column: $table.modifiedMillis,
    builder: (column) => column,
  );

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<int> get algoVersion => $composableBuilder(
    column: $table.algoVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get partialHash => $composableBuilder(
    column: $table.partialHash,
    builder: (column) => column,
  );

  GeneratedColumn<String> get fullHash =>
      $composableBuilder(column: $table.fullHash, builder: (column) => column);
}

class $$HashCacheEntriesTableTableManager
    extends
        RootTableManager<
          _$HashCacheDatabase,
          $HashCacheEntriesTable,
          HashCacheEntry,
          $$HashCacheEntriesTableFilterComposer,
          $$HashCacheEntriesTableOrderingComposer,
          $$HashCacheEntriesTableAnnotationComposer,
          $$HashCacheEntriesTableCreateCompanionBuilder,
          $$HashCacheEntriesTableUpdateCompanionBuilder,
          (
            HashCacheEntry,
            BaseReferences<
              _$HashCacheDatabase,
              $HashCacheEntriesTable,
              HashCacheEntry
            >,
          ),
          HashCacheEntry,
          PrefetchHooks Function()
        > {
  $$HashCacheEntriesTableTableManager(
    _$HashCacheDatabase db,
    $HashCacheEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HashCacheEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HashCacheEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HashCacheEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> path = const Value.absent(),
                Value<int> size = const Value.absent(),
                Value<int> modifiedMillis = const Value.absent(),
                Value<String?> deviceId = const Value.absent(),
                Value<int> algoVersion = const Value.absent(),
                Value<String?> partialHash = const Value.absent(),
                Value<String?> fullHash = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HashCacheEntriesCompanion(
                path: path,
                size: size,
                modifiedMillis: modifiedMillis,
                deviceId: deviceId,
                algoVersion: algoVersion,
                partialHash: partialHash,
                fullHash: fullHash,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String path,
                required int size,
                required int modifiedMillis,
                Value<String?> deviceId = const Value.absent(),
                required int algoVersion,
                Value<String?> partialHash = const Value.absent(),
                Value<String?> fullHash = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HashCacheEntriesCompanion.insert(
                path: path,
                size: size,
                modifiedMillis: modifiedMillis,
                deviceId: deviceId,
                algoVersion: algoVersion,
                partialHash: partialHash,
                fullHash: fullHash,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$HashCacheEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$HashCacheDatabase,
      $HashCacheEntriesTable,
      HashCacheEntry,
      $$HashCacheEntriesTableFilterComposer,
      $$HashCacheEntriesTableOrderingComposer,
      $$HashCacheEntriesTableAnnotationComposer,
      $$HashCacheEntriesTableCreateCompanionBuilder,
      $$HashCacheEntriesTableUpdateCompanionBuilder,
      (
        HashCacheEntry,
        BaseReferences<
          _$HashCacheDatabase,
          $HashCacheEntriesTable,
          HashCacheEntry
        >,
      ),
      HashCacheEntry,
      PrefetchHooks Function()
    >;

class $HashCacheDatabaseManager {
  final _$HashCacheDatabase _db;
  $HashCacheDatabaseManager(this._db);
  $$HashCacheEntriesTableTableManager get hashCacheEntries =>
      $$HashCacheEntriesTableTableManager(_db, _db.hashCacheEntries);
}
