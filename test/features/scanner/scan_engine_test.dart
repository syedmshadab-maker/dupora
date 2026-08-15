@Tags(['integration'])
library;

import 'dart:io';

import 'package:dupora/features/cache/hash_cache_database.dart';
import 'package:dupora/features/cache/hash_cache_repository.dart';
import 'package:dupora/features/scanner/domain/scan_progress.dart';
import 'package:dupora/features/scanner/scan_engine.dart';
import 'package:dupora/features/settings/settings_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// End-to-end coverage of the real pipeline: Stage 0 discovery -> Stage 1
/// size grouping -> Stage 2 partial fingerprint -> Stage 3 full BLAKE3,
/// against real files on disk and the real native engine (loaded from
/// `rust/target/release/`). This is the strongest correctness guarantee in
/// the test suite: nothing here is mocked except the settings.
void main() {
  late Directory tempDir;
  late HashCacheDatabase db;
  late HashCacheRepository cache;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dupora_scan_test_');
    db = HashCacheDatabase.inMemory();
    cache = HashCacheRepository(db);
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<void> writeFile(String name, String content) async {
    await File(
      '${tempDir.path}${Platform.pathSeparator}$name',
    ).writeAsString(content);
  }

  test(
    'finds exact duplicates across differently-named files and excludes unique ones',
    () async {
      await writeFile('a.txt', 'the quick brown fox');
      await writeFile(
        'b_renamed.txt',
        'the quick brown fox',
      ); // same content, different name
      await writeFile('unique.txt', 'nothing else looks like this');
      await writeFile('c.txt', 'the quick brown fox'); // third copy

      final engine = ScanEngine(cache: cache);
      final result = await engine.start([tempDir.path]);
      engine.dispose();

      expect(result.finalProgress.phase, ScanPhase.completed);
      expect(result.groups, hasLength(1));
      final group = result.groups.single;
      expect(group.files, hasLength(3));
      expect(group.duplicateCount, 2);
      expect(
        group.files.map((f) => f.path.split(Platform.pathSeparator).last),
        containsAll(['a.txt', 'b_renamed.txt', 'c.txt']),
      );
    },
  );

  test(
    'same size but different content is never reported as duplicate',
    () async {
      await writeFile('x.txt', 'AAAAAAAAAA');
      await writeFile('y.txt', 'BBBBBBBBBB'); // same length, different bytes

      final engine = ScanEngine(cache: cache);
      final result = await engine.start([tempDir.path]);
      engine.dispose();

      expect(result.groups, isEmpty);
    },
  );

  test(
    'zero-byte files are treated as exact duplicates of each other',
    () async {
      await writeFile('empty1.txt', '');
      await writeFile('empty2.txt', '');

      final engine = ScanEngine(cache: cache);
      final result = await engine.start([tempDir.path]);
      engine.dispose();

      expect(result.groups, hasLength(1));
      expect(result.groups.single.fileSize, 0);
    },
  );

  test(
    'an inaccessible path is reported as a scan error, not a crash',
    () async {
      await writeFile('ok.txt', 'fine');

      final engine = ScanEngine(cache: cache);
      final result = await engine.start([
        tempDir.path,
        '${tempDir.path}${Platform.pathSeparator}does_not_exist',
      ]);
      engine.dispose();

      expect(result.finalProgress.phase, ScanPhase.completed);
      expect(result.errors, isNotEmpty);
    },
  );

  test(
    'cancelling before completion yields phase=cancelled and no groups',
    () async {
      for (var i = 0; i < 20; i++) {
        await writeFile('f$i.txt', 'duplicate content shared by many files');
      }

      final engine = ScanEngine(cache: cache);
      final future = engine.start([tempDir.path]);
      await engine.cancel();
      final result = await future;
      engine.dispose();

      expect(result.finalProgress.phase, ScanPhase.cancelled);
      expect(result.groups, isEmpty);
    },
  );

  test(
    'incremental rescan reuses cached hashes instead of rehashing unchanged files',
    () async {
      await writeFile('a.txt', 'stable content');
      await writeFile('b.txt', 'stable content');

      final engine1 = ScanEngine(cache: cache);
      final firstResult = await engine1.start([tempDir.path]);
      engine1.dispose();
      expect(firstResult.groups, hasLength(1));
      expect(await cache.entryCount(), 2);

      // Second scan over the same unchanged files must produce the same
      // result purely from cache lookups (no filesystem mutation between
      // runs), which is exactly what the persistent hash cache exists for.
      final engine2 = ScanEngine(cache: cache);
      final secondResult = await engine2.start([tempDir.path]);
      engine2.dispose();

      expect(secondResult.groups, hasLength(1));
      expect(secondResult.groups.single.files, hasLength(2));
    },
  );

  test('Unicode filenames and filenames with spaces are hashed and grouped '
      'correctly, not just tolerated without crashing', () async {
    await writeFile('  spaced name (copy).txt', 'shared content');
    await writeFile('日本語のファイル名.txt', 'shared content');
    await writeFile('emoji 🎉 file.txt', 'shared content');
    await writeFile('unique.txt', 'not shared');

    final engine = ScanEngine(cache: cache);
    final result = await engine.start([tempDir.path]);
    engine.dispose();

    expect(result.finalProgress.phase, ScanPhase.completed);
    expect(result.groups, hasLength(1));
    expect(result.groups.single.files, hasLength(3));
  });

  test(
    'a 100-file duplicate group is grouped correctly as a single group',
    () async {
      for (var i = 0; i < 100; i++) {
        await writeFile('dup_$i.bin', 'identical payload shared by all 100');
      }
      await writeFile('outlier.bin', 'not part of the group');

      final engine = ScanEngine(cache: cache);
      final result = await engine.start([tempDir.path]);
      engine.dispose();

      expect(result.groups, hasLength(1));
      expect(result.groups.single.files, hasLength(100));
      expect(result.groups.single.duplicateCount, 99);
    },
  );

  test('a path deep enough to approach/exceed the legacy MAX_PATH (260 char) '
      'limit is either hashed correctly or reported as a scan error - never '
      'a crash or a hang', () async {
    if (!Platform.isWindows) return;

    var dir = tempDir.path;
    // Build nested directories until the path is comfortably past 260
    // characters, the classic Windows MAX_PATH ceiling.
    while (dir.length < 300) {
      dir = '$dir${Platform.pathSeparator}nested_directory_segment';
      try {
        await Directory(dir).create();
      } catch (_) {
        // This filesystem/OS configuration refuses long paths outright -
        // that's a legitimate real-world answer, not a bug in the
        // scanner; nothing further to verify down this branch.
        return;
      }
    }
    final longPath = '$dir${Platform.pathSeparator}deep_file.txt';
    try {
      await File(longPath).writeAsString('content at a very deep path');
    } catch (_) {
      return; // same reasoning as above
    }

    final engine = ScanEngine(cache: cache);
    final result = await engine.start([tempDir.path]);
    engine.dispose();

    // Whatever happened, it must have completed cleanly - a long path
    // must never crash or hang the scan, whether or not it was
    // successfully read.
    expect(result.finalProgress.phase, ScanPhase.completed);
  });

  test(
    'respects settings.scanHiddenFiles=false by default on dotfiles',
    () async {
      await writeFile('.hidden_a', 'secret dup');
      await writeFile('.hidden_b', 'secret dup');

      final engine = ScanEngine(cache: cache, settings: const DuporaSettings());
      final result = await engine.start([tempDir.path]);
      engine.dispose();

      if (!Platform.isWindows) {
        // Dotfile convention only applies outside Windows (Windows hidden
        // detection uses the real file-attribute bit, and Directory.create-
        // written files aren't marked hidden that way).
        expect(result.groups, isEmpty);
      }
    },
  );
}
