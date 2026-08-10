import 'dart:io' show Platform;

import 'package:drift/drift.dart';

import '../scanner/domain/scanned_file.dart';
import 'hash_cache_database.dart';

/// Bump when the hashing scheme changes (e.g. a different fingerprint
/// window size) so old cache rows are treated as stale rather than
/// misapplied.
const int kHashAlgoVersion = 1;

class CachedHashes {
  const CachedHashes({this.partialHashHex, this.fullHashHex});
  final String? partialHashHex;
  final String? fullHashHex;
}

/// Wraps [HashCacheDatabase] with the validity rule from the project spec:
/// "A cached hash is valid only when the file identity/state still
/// matches." A mismatch on size, mtime, device, or algorithm version
/// invalidates (deletes) the row automatically rather than returning stale
/// data.
class HashCacheRepository {
  HashCacheRepository(this._db);

  final HashCacheDatabase _db;

  Future<CachedHashes?> lookup(ScannedFile file) async {
    final row = await (_db.select(
      _db.hashCacheEntries,
    )..where((t) => t.path.equals(file.path))).getSingleOrNull();
    if (row == null) return null;

    final identityMatches =
        row.size == file.size &&
        row.modifiedMillis == file.modifiedAt.millisecondsSinceEpoch &&
        row.algoVersion == kHashAlgoVersion &&
        (row.deviceId == null ||
            file.deviceId == null ||
            row.deviceId == file.deviceId);

    if (!identityMatches) {
      await invalidate(file.path);
      return null;
    }
    return CachedHashes(
      partialHashHex: row.partialHash,
      fullHashHex: row.fullHash,
    );
  }

  Future<void> storePartial(ScannedFile file, String partialHex) async {
    await _db
        .into(_db.hashCacheEntries)
        .insertOnConflictUpdate(
          HashCacheEntriesCompanion.insert(
            path: file.path,
            size: file.size,
            modifiedMillis: file.modifiedAt.millisecondsSinceEpoch,
            deviceId: Value(file.deviceId),
            algoVersion: kHashAlgoVersion,
            partialHash: Value(partialHex),
          ),
        );
  }

  Future<void> storeFull(
    ScannedFile file,
    String partialHex,
    String fullHex,
  ) async {
    await _db
        .into(_db.hashCacheEntries)
        .insertOnConflictUpdate(
          HashCacheEntriesCompanion.insert(
            path: file.path,
            size: file.size,
            modifiedMillis: file.modifiedAt.millisecondsSinceEpoch,
            deviceId: Value(file.deviceId),
            algoVersion: kHashAlgoVersion,
            partialHash: Value(partialHex),
            fullHash: Value(fullHex),
          ),
        );
  }

  Future<void> invalidate(String path) async {
    await (_db.delete(
      _db.hashCacheEntries,
    )..where((t) => t.path.equals(path))).go();
  }

  Future<int> entryCount() async {
    final rows = await _db.select(_db.hashCacheEntries).get();
    return rows.length;
  }

  /// Deletes cache rows for files that no longer exist under any of
  /// [scannedRoots] - i.e. files that were deleted (or moved away) since
  /// they were last cached. Without this, a cache row for a deleted file
  /// is never looked up again (nothing will ever ask about that exact
  /// path), so it would otherwise sit in the database forever, growing
  /// without bound across repeated scans of a tree that has files added
  /// and removed over time. [presentPaths] is every path Stage 0
  /// discovery actually found in this scan.
  ///
  /// Only rows under [scannedRoots] are considered - a row for a path
  /// outside what was just scanned says nothing about whether that file
  /// still exists, so it's left alone.
  ///
  /// Fetches the whole cache table and filters in Dart rather than a SQL
  /// prefix match per root; simpler, and fine for the realistic cache
  /// sizes this app produces (tens of thousands of rows, pruned once per
  /// scan, not per file). Revisit with a proper `WHERE path LIKE ?` if
  /// that ever stops being true.
  Future<int> pruneMissing(
    List<String> scannedRoots,
    Set<String> presentPaths,
  ) async {
    if (scannedRoots.isEmpty) return 0;
    final normalizedRoots = scannedRoots.map(_withTrailingSeparator).toList();

    final allRows = await _db.select(_db.hashCacheEntries).get();
    final toDelete = <String>[];
    for (final row in allRows) {
      if (presentPaths.contains(row.path)) continue;
      final underScannedRoot = normalizedRoots.any(
        (root) => row.path.startsWith(root),
      );
      if (underScannedRoot) toDelete.add(row.path);
    }
    if (toDelete.isEmpty) return 0;

    await _db.batch((batch) {
      batch.deleteWhere(_db.hashCacheEntries, (t) => t.path.isIn(toDelete));
    });
    return toDelete.length;
  }

  static String _withTrailingSeparator(String root) {
    return root.endsWith(Platform.pathSeparator)
        ? root
        : '$root${Platform.pathSeparator}';
  }
}
