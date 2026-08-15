import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'hash_cache_database.g.dart';

final _log = Logger('HashCacheDatabase');

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

  /// Opens the persistent cache, recovering safely from a corrupted,
  /// schema-mismatched, or otherwise unusable database file rather than
  /// letting the failure propagate out of app startup. The cache is a pure
  /// performance optimization (a second scan just re-hashes everything
  /// without it) so it must never be the reason the app - and therefore the
  /// user's access to their own files - fails to start.
  static Future<HashCacheDatabase> open() async {
    final Directory dir;
    try {
      dir = await getApplicationSupportDirectory();
      await Directory(dir.path).create(recursive: true);
    } catch (e) {
      _log.warning('Could not create/access app support directory: $e');
      return HashCacheDatabase.inMemory();
    }
    final file = File(p.join(dir.path, 'dupora_cache.sqlite'));
    return openVerified(file);
  }

  /// Opens [file] and forces a real query against it immediately, so a
  /// corrupted/incompatible database surfaces *here* - not on whatever
  /// random query happens to run first mid-scan (Drift's background
  /// connection doesn't necessarily fail synchronously at construction).
  /// On failure with [allowRecovery] set, the unusable file is moved aside
  /// and a fresh database is opened in its place (i.e. the cache is
  /// silently rebuilt); if that also fails, falls back to an in-memory
  /// database so the app is still fully usable this session, just without
  /// cache persistence across restarts.
  ///
  /// Public (rather than the file-backed constructor path directly) so
  /// tests can exercise real corruption recovery against a real file
  /// without going through [open]'s `path_provider` dependency, which
  /// needs a platform channel unavailable in plain `flutter test`.
  @visibleForTesting
  static Future<HashCacheDatabase> openVerified(
    File file, {
    bool allowRecovery = true,
  }) async {
    final db = HashCacheDatabase(NativeDatabase.createInBackground(file));
    try {
      await db.select(db.hashCacheEntries).get();
      return db;
    } catch (e) {
      await db.close();
      if (!allowRecovery) {
        _log.warning('Cache still unusable after recovery attempt: $e');
        return HashCacheDatabase.inMemory();
      }
      _log.warning('Cache database unusable, rebuilding: $e');
      try {
        if (await file.exists()) {
          final quarantined = File(
            '${file.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}',
          );
          await file.rename(quarantined.path);
        }
      } catch (renameError) {
        _log.warning('Could not quarantine corrupt cache file: $renameError');
        return HashCacheDatabase.inMemory();
      }
      return openVerified(file, allowRecovery: false);
    }
  }

  static HashCacheDatabase openAt(File file) =>
      HashCacheDatabase(NativeDatabase.createInBackground(file));

  static HashCacheDatabase inMemory() =>
      HashCacheDatabase(NativeDatabase.memory());
}
