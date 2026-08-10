import 'package:dupora/features/cache/hash_cache_database.dart';
import 'package:dupora/features/cache/hash_cache_repository.dart';
import 'package:dupora/features/scanner/domain/scanned_file.dart';
import 'package:flutter_test/flutter_test.dart';

ScannedFile _file(String path, {int size = 100, DateTime? modified, String? deviceId}) {
  return ScannedFile(
    path: path,
    name: path,
    extension: '',
    size: size,
    modifiedAt: modified ?? DateTime(2024, 1, 1),
    deviceId: deviceId,
  );
}

void main() {
  late HashCacheDatabase db;
  late HashCacheRepository repo;

  setUp(() {
    db = HashCacheDatabase.inMemory();
    repo = HashCacheRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('lookup on an empty cache returns null', () async {
    final result = await repo.lookup(_file('a'));
    expect(result, isNull);
  });

  test('a stored full hash is returned on a matching lookup', () async {
    final file = _file('a');
    await repo.storeFull(file, 'partial123', 'full456');
    final result = await repo.lookup(file);
    expect(result?.partialHashHex, 'partial123');
    expect(result?.fullHashHex, 'full456');
  });

  test('a size change invalidates the cached entry', () async {
    final original = _file('a', size: 100);
    await repo.storeFull(original, 'p', 'f');

    final changed = _file('a', size: 200);
    final result = await repo.lookup(changed);
    expect(result, isNull);
    expect(await repo.entryCount(), 0); // invalidation deletes the row
  });

  test('an mtime change invalidates the cached entry', () async {
    final original = _file('a', modified: DateTime(2024, 1, 1));
    await repo.storeFull(original, 'p', 'f');

    final touched = _file('a', modified: DateTime(2024, 6, 1));
    final result = await repo.lookup(touched);
    expect(result, isNull);
  });

  test('a mismatched deviceId invalidates the cached entry', () async {
    final original = _file('a', deviceId: 'C:');
    await repo.storeFull(original, 'p', 'f');

    final movedVolume = _file('a', deviceId: 'D:');
    final result = await repo.lookup(movedVolume);
    expect(result, isNull);
  });

  test('a null deviceId on either side does not force invalidation', () async {
    final original = _file('a', deviceId: 'C:');
    await repo.storeFull(original, 'p', 'f');

    final unknownDevice = _file('a', deviceId: null);
    final result = await repo.lookup(unknownDevice);
    expect(result, isNotNull);
  });

  test('storePartial then storeFull upgrades the same row rather than duplicating', () async {
    final file = _file('a');
    await repo.storePartial(file, 'partialOnly');
    expect(await repo.entryCount(), 1);

    await repo.storeFull(file, 'partialOnly', 'fullHash');
    expect(await repo.entryCount(), 1);

    final result = await repo.lookup(file);
    expect(result?.fullHashHex, 'fullHash');
  });

  test('invalidate removes the row outright', () async {
    final file = _file('a');
    await repo.storeFull(file, 'p', 'f');
    await repo.invalidate(file.path);
    expect(await repo.lookup(file), isNull);
  });

  test('incremental rescan simulation: unchanged files stay cached, changed files do not', () async {
    final unchanged = _file('unchanged', modified: DateTime(2024, 1, 1));
    final changed = _file('changed', modified: DateTime(2024, 1, 1));
    await repo.storeFull(unchanged, 'p1', 'f1');
    await repo.storeFull(changed, 'p2', 'f2');

    // Second "scan": `changed` was touched since; `unchanged` was not.
    final rescanUnchanged = _file('unchanged', modified: DateTime(2024, 1, 1));
    final rescanChanged = _file('changed', modified: DateTime(2024, 2, 1));

    expect((await repo.lookup(rescanUnchanged))?.fullHashHex, 'f1');
    expect(await repo.lookup(rescanChanged), isNull);
  });
}
