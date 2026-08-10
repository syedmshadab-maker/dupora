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
    final row = await (_db.select(_db.hashCacheEntries)..where((t) => t.path.equals(file.path)))
        .getSingleOrNull();
    if (row == null) return null;

    final identityMatches = row.size == file.size &&
        row.modifiedMillis == file.modifiedAt.millisecondsSinceEpoch &&
        row.algoVersion == kHashAlgoVersion &&
        (row.deviceId == null || file.deviceId == null || row.deviceId == file.deviceId);

    if (!identityMatches) {
      await invalidate(file.path);
      return null;
    }
    return CachedHashes(partialHashHex: row.partialHash, fullHashHex: row.fullHash);
  }

  Future<void> storePartial(ScannedFile file, String partialHex) async {
    await _db.into(_db.hashCacheEntries).insertOnConflictUpdate(
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

  Future<void> storeFull(ScannedFile file, String partialHex, String fullHex) async {
    await _db.into(_db.hashCacheEntries).insertOnConflictUpdate(
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
    await (_db.delete(_db.hashCacheEntries)..where((t) => t.path.equals(path))).go();
  }

  Future<int> entryCount() async {
    final rows = await _db.select(_db.hashCacheEntries).get();
    return rows.length;
  }
}
