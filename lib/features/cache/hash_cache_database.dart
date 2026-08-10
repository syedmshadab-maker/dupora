import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'hash_cache_database.g.dart';

/// Persistent hash cache. One row per file, keyed by path, carrying exactly
/// the identity fields the project spec requires for cache validity:
/// size + modified timestamp + filesystem identity + hash algorithm
/// version, alongside the partial and full hashes themselves.
class HashCacheEntries extends Table {
  TextColumn get path => text()();
  IntColumn get size => integer()();
  IntColumn get modifiedMillis => integer()();
  TextColumn get deviceId => text().nullable()();
  IntColumn get algoVersion => integer()();
  TextColumn get partialHash => text().nullable()();
  TextColumn get fullHash => text().nullable()();

  @override
  Set<Column> get primaryKey => {path};
}

@DriftDatabase(tables: [HashCacheEntries])
class HashCacheDatabase extends _$HashCacheDatabase {
  HashCacheDatabase(super.executor);

  @override
  int get schemaVersion => 1;

  static Future<HashCacheDatabase> open() async {
    final dir = await getApplicationSupportDirectory();
    await Directory(dir.path).create(recursive: true);
    final file = File(p.join(dir.path, 'dupora_cache.sqlite'));
    return HashCacheDatabase(NativeDatabase.createInBackground(file));
  }

  static HashCacheDatabase openAt(File file) => HashCacheDatabase(NativeDatabase.createInBackground(file));

  static HashCacheDatabase inMemory() => HashCacheDatabase(NativeDatabase.memory());
}
