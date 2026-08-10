// A controlled, real-world-shaped test dataset run against the REAL
// compiled application (same integration_test approach as app_test.dart),
// covering every file scenario called out in the release-audit checklist:
// identical files under different names, identical files in different
// directories, same-size/different-content files, zero-byte files, small
// files, a large (>1 MiB, so it exercises the mmap hashing path) file pair,
// renamed duplicates, a file modified after being cached, and a genuinely
// locked/inaccessible file.
//
// Safety: everything lives inside a single fresh temp directory, deleted in
// addTearDown. Nothing outside that directory is ever touched.

import 'dart:io';

import 'package:dupora/features/scanner/domain/scan_progress.dart';
import 'package:dupora/main.dart';
import 'package:dupora/ui/state/app_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

class _TimeoutException implements Exception {
  _TimeoutException(this.message);
  final String message;
  @override
  String toString() => 'TimeoutException: $message';
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration step = const Duration(milliseconds: 200),
  int maxSteps = 300, // 60s - the large-file pair makes this scan slower
}) async {
  for (var i = 0; i < maxSteps; i++) {
    if (condition()) return;
    await tester.pump(step);
  }
  throw _TimeoutException(
    'condition not met within ${maxSteps * step.inMilliseconds}ms',
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'controlled real-world dataset: every required scenario produces the expected result',
    (tester) async {
      final root = await Directory.systemTemp.createTemp('dupora_dataset_');
      final sub1 = await Directory('${root.path}\\folderA').create();
      final sub2 = await Directory('${root.path}\\folderB').create();
      RandomAccessFile? lockedHandle;

      addTearDown(() async {
        try {
          await lockedHandle?.unlock();
          await lockedHandle?.close();
        } catch (_) {}
        if (await root.exists()) {
          try {
            await root.delete(recursive: true);
          } catch (_) {
            // The locked file may still be closing; best-effort cleanup for
            // a temp directory is acceptable here.
          }
        }
      });

      // --- 1 & 7: identical files under different names (a "renamed
      // duplicate" is indistinguishable from this at the content level) ---
      const identicalContent =
          'Identical content shared by three files - Dupora dataset test.';
      final identicalA = File('${root.path}\\identical_a.txt')
        ..writeAsStringSync(identicalContent);
      final identicalB = File('${root.path}\\identical_b_renamed.txt')
        ..writeAsStringSync(identicalContent);
      final identicalC = File('${root.path}\\identical_c_another_name.txt')
        ..writeAsStringSync(identicalContent);

      // --- 2: identical files in different directories ---
      const nestedContent =
          'Content duplicated across two different subdirectories.';
      final nestedA = File('${sub1.path}\\nested.txt')
        ..writeAsStringSync(nestedContent);
      final nestedB = File('${sub2.path}\\nested_copy.txt')
        ..writeAsStringSync(nestedContent);

      // --- 3: same size, different content (must never be grouped) ---
      final sameSizeA = File('${root.path}\\samesize_a.bin')
        ..writeAsBytesSync(List.filled(500, 0xAA));
      final sameSizeB = File('${root.path}\\samesize_b.bin')
        ..writeAsBytesSync(List.filled(500, 0xBB));

      // --- 4: zero-byte files (trivially identical to each other) ---
      final emptyA = File('${root.path}\\empty_a.dat')
        ..writeAsBytesSync(const []);
      final emptyB = File('${root.path}\\empty_b.dat')
        ..writeAsBytesSync(const []);

      // --- 5: a small unique file (must never appear in any group) ---
      final unique = File('${root.path}\\unique.txt')
        ..writeAsStringSync('Nothing else matches this file.');

      // --- 6: a large file pair (>1 MiB, exercises the mmap hashing path
      // rather than the small-file buffered path) ---
      final largeBytes = List<int>.generate(3 * 1024 * 1024, (i) => i % 256);
      final largeA = File('${root.path}\\large_a.bin')
        ..writeAsBytesSync(largeBytes);
      final largeB = File('${root.path}\\large_b.bin')
        ..writeAsBytesSync(largeBytes);

      // --- 9: a genuinely locked/inaccessible file. LockFileEx-backed locks
      // on Windows are mandatory (unlike POSIX advisory locks), so this
      // reliably blocks even a different isolate in the same process from
      // reading it. Writes the content through the same handle it locks
      // (rather than writing first and reopening with FileMode.write, which
      // would truncate the file back to empty before the lock is taken).
      //
      // Gets a same-size sibling deliberately: a file with a genuinely
      // unique size is never read at all (Stage 1 filters it out before any
      // hashing is attempted - by design, see duplicate_funnel.dart), so
      // without a size match it would never reach an actual read attempt
      // and this scenario wouldn't test anything.
      const lockedContent =
          'This file will be locked during the scan and must not be readable.';
      final lockedFile = File('${root.path}\\locked.txt');
      lockedHandle = lockedFile.openSync(mode: FileMode.write);
      lockedHandle.writeStringSync(lockedContent);
      lockedHandle.lockSync(FileLock.exclusive);
      final lockedSizeSibling = File('${root.path}\\locked_size_sibling.txt')
        ..writeAsStringSync('X' * lockedContent.length);

      // --- Boot the real app and point it at the dataset ---
      await tester.pumpWidget(const DuporaBootstrap());
      await _pumpUntil(
        tester,
        () => find.byType(Scaffold).evaluate().isNotEmpty,
      );
      await tester.pump(const Duration(seconds: 2));

      final context = tester.element(find.byType(Scaffold).first);
      final controller = context.read<AppController>();

      controller.addCustomFolder(root.path);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Start Scan'));
      await tester.pump();

      await _pumpUntil(tester, () => controller.screen == AppScreen.results);
      final result = controller.lastResult!;

      // --- Verify: locked file was reported as an error, not a crash ---
      expect(result.finalProgress.phase, ScanPhase.completed);
      expect(
        result.errors.any((e) => e.path == lockedFile.path),
        isTrue,
        reason:
            'the locked file must be reported as a scan error, not silently skipped or crash the scan',
      );

      // --- Verify: exactly the expected duplicate groups, nothing more ---
      // Expect 4 groups: {identicalA,B,C}, {nestedA,nestedB}, {emptyA,emptyB}, {largeA,largeB}.
      expect(
        result.groups.length,
        4,
        reason:
            'unexpected group count: ${result.groups.map((g) => g.files.map((f) => f.path).toList())}',
      );

      bool groupMatches(Set<String> expectedPaths) {
        return result.groups.any(
          (g) =>
              g.files.map((f) => f.path).toSet().containsAll(expectedPaths) &&
              g.files.length == expectedPaths.length,
        );
      }

      expect(
        groupMatches({identicalA.path, identicalB.path, identicalC.path}),
        isTrue,
        reason:
            'the three identically-named-content files under different names must form one group',
      );
      expect(
        groupMatches({nestedA.path, nestedB.path}),
        isTrue,
        reason:
            'identical content in two different subdirectories must form one group',
      );
      expect(
        groupMatches({emptyA.path, emptyB.path}),
        isTrue,
        reason:
            'zero-byte files must be treated as exact duplicates of each other',
      );
      expect(
        groupMatches({largeA.path, largeB.path}),
        isTrue,
        reason:
            'the >1MiB file pair (mmap hashing path) must still be correctly matched',
      );

      // --- Verify: same-size-different-content and the unique file never
      // appear together with anything ---
      for (final g in result.groups) {
        final paths = g.files.map((f) => f.path).toSet();
        expect(
          paths.contains(sameSizeA.path) && paths.contains(sameSizeB.path),
          isFalse,
          reason:
              'same-size-different-content files must never be grouped together',
        );
        expect(
          paths.contains(unique.path),
          isFalse,
          reason: 'the unique file must never appear in any group',
        );
      }

      // --- 8: modified-after-cache - release the lock, modify a file that
      // was NOT part of any duplicate pair, add a fresh duplicate of it, and
      // rescan the same root to confirm the cache correctly picks up the
      // change (this exercises real incremental-scan + cache-invalidation
      // behavior against the actual compiled app, not just the engine
      // unit tests). ---
      await lockedHandle.unlock();
      await lockedHandle.close();
      lockedHandle = null;

      unique.writeAsStringSync(
        'Nothing else matches this file.',
      ); // now has a real duplicate below
      final uniqueCopy = File('${root.path}\\unique_copy_added_later.txt')
        ..writeAsStringSync('Nothing else matches this file.');

      controller.backToHome();
      await tester.pumpAndSettle();
      controller.addCustomFolder(root.path);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Start Scan'));
      await tester.pump();
      await _pumpUntil(tester, () => controller.screen == AppScreen.results);

      final secondResult = controller.lastResult!;
      expect(
        secondResult.groups.any((g) {
          final paths = g.files.map((f) => f.path).toSet();
          return paths.contains(unique.path) && paths.contains(uniqueCopy.path);
        }),
        isTrue,
        reason:
            'a file added after the first scan must be correctly detected as a duplicate on rescan',
      );
      // The locked file is now unlocked and readable, so on rescan it should
      // no longer be an error, and should form its own (single-file, not a
      // duplicate) entry - i.e. it must not appear in result.errors anymore.
      expect(
        secondResult.errors.any((e) => e.path == lockedFile.path),
        isFalse,
        reason:
            'a file that was locked during the first scan but is readable now must not still be reported as an error',
      );
      // Same size as its sibling, but different content - must still not be
      // grouped together now that both are readable.
      expect(
        secondResult.groups.any((g) {
          final paths = g.files.map((f) => f.path).toSet();
          return paths.contains(lockedFile.path) &&
              paths.contains(lockedSizeSibling.path);
        }),
        isFalse,
        reason:
            'same-size-different-content must hold even for the file that was previously locked',
      );
    },
  );
}
