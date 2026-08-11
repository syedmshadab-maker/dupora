// Drives the REAL compiled Linux application end-to-end, specifically to
// verify the Linux native-engine packaging fix: the release bundle now
// installs libdupora_engine.so into bundle/lib/ (see linux/CMakeLists.txt)
// and dupora_native_bindings.dart resolves it there explicitly. This test
// proves that end-to-end rather than assuming it from the CMake change
// alone - real dlopen, real BLAKE3 hashing, real duplicate detection
// against files this test creates itself, real cleanup afterward.
//
// Safety: every file this test touches is created by the test itself
// inside a fresh temp directory and cleaned up afterward.

import 'dart:io';

import 'package:dupora/core/native/hash_engine.dart';
import 'package:dupora/main.dart';
import 'package:dupora/ui/screens/results_screen.dart';
import 'package:dupora/ui/state/app_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration step = const Duration(milliseconds: 200),
  int maxSteps = 150, // 30s
}) async {
  for (var i = 0; i < maxSteps; i++) {
    if (condition()) return;
    await tester.pump(step);
  }
  throw TimeoutException(
    'condition not met within ${maxSteps * step.inMilliseconds}ms',
  );
}

class TimeoutException implements Exception {
  TimeoutException(this.message);
  final String message;
  @override
  String toString() => 'TimeoutException: $message';
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Linux release bundle: native engine loads and hashes for real', (
    tester,
  ) async {
    // --- Step 1: prove the native engine loads, independent of any UI. ---
    // If bundle/lib/libdupora_engine.so were missing or unresolved, this
    // throws a StateError from DuporaNativeBindings._openLibrary()
    // immediately - no scan, no widget tree, nothing to mask it.
    final version = NativeHasher().engineVersion();
    expect(version, isNotEmpty);
    // ignore: avoid_print
    print('Dupora native engine loaded successfully. Version: $version');

    // --- Step 2: build a real, controlled dataset. ---
    final testDir = await Directory.systemTemp.createTemp('dupora_linux_it_');
    addTearDown(() async {
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    });

    final fileA = File(p.join(testDir.path, 'duplicate_a.txt'));
    final fileB = File(p.join(testDir.path, 'duplicate_b.txt'));
    final fileSameSize = File(p.join(testDir.path, 'same_size_different.txt'));
    const sharedContent = 'Dupora Linux integration test duplicate content.';
    await fileA.writeAsString(sharedContent);
    await fileB.writeAsString(sharedContent);
    // Same length as sharedContent, different bytes - must never be
    // reported as a duplicate of fileA/fileB.
    await fileSameSize.writeAsString('X' * sharedContent.length);
    expect(
      await fileSameSize.length(),
      await fileA.length(),
      reason: 'test setup invariant: same size, different content',
    );

    // --- Step 3: boot the real, fully-bundled app. ---
    await tester.pumpWidget(const DuporaBootstrap());
    await pumpUntil(tester, () => find.byType(Scaffold).evaluate().isNotEmpty);
    await tester.pump(const Duration(seconds: 2));

    final context = tester.element(find.byType(Scaffold).first);
    final controller = context.read<AppController>();

    controller.addCustomFolder(testDir.path);
    await tester.pumpAndSettle();
    expect(find.textContaining('Start Scan'), findsOneWidget);

    // --- Step 4: real scan, real Stage 0-3 pipeline, real BLAKE3 via FFI. ---
    await tester.tap(find.textContaining('Start Scan'));
    await tester.pump();
    // Don't hard-assert ScanScreen specifically: with only 3 tiny files,
    // the scan can complete faster than a single pump() on a loaded CI
    // runner can observe the mid-scan frame, going straight to results.
    // What actually matters (and is asserted below) is that scanning
    // started and the app reached a real, correct result - not that this
    // test happened to catch the transitional screen.
    // 60s budget - a loaded CI runner may be slower than a dev machine.
    await pumpUntil(
      tester,
      () => controller.screen == AppScreen.results,
      maxSteps: 300,
    );
    expect(find.byType(ResultsScreen), findsOneWidget);

    // --- Step 5: verify against known ground truth. ---
    final result = controller.lastResult;
    expect(result, isNotNull);
    expect(result!.errors, isEmpty);
    expect(
      result.groups.length,
      1,
      reason: 'exactly one duplicate group (duplicate_a/duplicate_b)',
    );
    final group = result.groups.single;
    final groupPaths = group.files.map((f) => f.path).toSet();
    expect(groupPaths, {fileA.path, fileB.path});
    for (final g in result.groups) {
      expect(
        g.files.any((f) => f.path == fileSameSize.path),
        isFalse,
        reason:
            'same-size-different-content file must never be classified as '
            'a duplicate - this only holds if the full BLAKE3 hash (not '
            'just the Stage 1 size grouping) actually ran',
      );
    }

    // ignore: avoid_print
    print(
      'Linux native-engine runtime verification passed: engine loaded, '
      'BLAKE3 hashing executed, duplicate pair correctly identified, '
      'same-size/different-content pair correctly excluded.',
    );
  });
}
