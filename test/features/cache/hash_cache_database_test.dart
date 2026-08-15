import 'dart:io';

import 'package:dupora/features/cache/hash_cache_database.dart';
import 'package:dupora/features/cache/hash_cache_repository.dart';
import 'package:dupora/features/scanner/domain/scanned_file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dupora_cachedb_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('opens normally against a fresh, non-existent file', () async {
    final file = File('${tempDir.path}${Platform.pathSeparator}cache.sqlite');
    final db = await HashCacheDatabase.openVerified(file);
    addTearDown(db.close);

    final repo = HashCacheRepository(db);
    expect(await repo.entryCount(), 0);
    expect(await file.exists(), isTrue); // a real file was created
  });

  test(
    'a corrupted cache file is quarantined and replaced with a working '
    'database rather than throwing (regression: HashCacheDatabase.open() '
    'previously had no corruption recovery at all - see Phase 2 audit)',
    () async {
      final file = File(
        '${tempDir.path}${Platform.pathSeparator}corrupt.sqlite',
      );
      // Not a SQLite file at all - guaranteed to fail whatever query Drift
      // runs against it.
      await file.writeAsBytes(List<int>.filled(4096, 0xFF));

      final db = await HashCacheDatabase.openVerified(file);
      addTearDown(db.close);

      // The recovered database must be genuinely usable, not just
      // non-throwing.
      final repo = HashCacheRepository(db);
      expect(await repo.entryCount(), 0);
      final probe = ScannedFile(
        path: 'C:\\probe.txt',
        name: 'probe.txt',
        extension: 'txt',
        size: 10,
        modifiedAt: DateTime(2024, 1, 1),
      );
      await repo.storeFull(probe, 'partial', 'full');
      expect((await repo.lookup(probe))?.fullHashHex, 'full');

      // The unusable original file must not have been silently overwritten
      // in place - it's quarantined alongside the fresh database so it
      // isn't lost for diagnostics, and a fresh cache file now exists at
      // the original path.
      final siblings = await tempDir.list().toList();
      final quarantined = siblings.where(
        (e) => e.path.contains('corrupt.sqlite.corrupt-'),
      );
      expect(quarantined, isNotEmpty);
      expect(await file.exists(), isTrue);
    },
  );

  test('falls back to an in-memory database if even the rebuilt file cannot '
      'be made usable (e.g. the containing directory is not writable)', () async {
    // A path inside a directory that doesn't exist and can't be created
    // simulates "recovery itself is impossible" without relying on
    // ACL manipulation.
    final file = File(
      '${tempDir.path}${Platform.pathSeparator}missing_dir${Platform.pathSeparator}'
      'nested${Platform.pathSeparator}cache.sqlite',
    );

    // openVerified must still return a *usable* database, never throw.
    final db = await HashCacheDatabase.openVerified(file);
    addTearDown(db.close);

    final repo = HashCacheRepository(db);
    expect(await repo.entryCount(), 0);
    final probe = ScannedFile(
      path: 'C:\\probe2.txt',
      name: 'probe2.txt',
      extension: 'txt',
      size: 5,
      modifiedAt: DateTime(2024, 1, 1),
    );
    await repo.storeFull(probe, 'p', 'f');
    expect((await repo.lookup(probe))?.fullHashHex, 'f');
  });
}
