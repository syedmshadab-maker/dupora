// Drives the REAL compiled application end-to-end: real widget tree, real
// Rust BLAKE3 engine (loaded via dart:ffi from the actual bundled DLL),
// real SQLite cache, real filesystem, real platform delete API. This is
// deliberately not a widget test with fakes - it is the production-artifact
// smoke test requested for the Windows release build.
//
// Safety: every file this test touches (including the one it deletes) is
// created by the test itself inside a fresh temp directory and cleaned up
// afterward. It never selects or deletes anything outside that directory.

import 'dart:io';

import 'package:dupora/main.dart';
import 'package:dupora/ui/screens/results_screen.dart';
import 'package:dupora/ui/screens/scan_screen.dart';
import 'package:dupora/ui/state/app_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
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

  testWidgets('production build: scan, detect duplicates, delete to Recycle Bin', (
    tester,
  ) async {
    final testDir = await Directory.systemTemp.createTemp('dupora_itest_');
    addTearDown(() async {
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    });

    final fileA = File('${testDir.path}\\duplicate_a.txt');
    final fileB = File('${testDir.path}\\duplicate_b.txt');
    final fileUnique = File('${testDir.path}\\unique.txt');
    await fileA.writeAsString('Dupora integration test duplicate content.');
    await fileB.writeAsString('Dupora integration test duplicate content.');
    await fileUnique.writeAsString('This file is intentionally different.');

    // --- Boot the real app ---
    await tester.pumpWidget(const DuporaBootstrap());
    await pumpUntil(tester, () => find.byType(Scaffold).evaluate().isNotEmpty);
    // Let async init (settings, cache DB, volume enumeration) finish.
    await tester.pump(const Duration(seconds: 2));

    final context = tester.element(find.byType(Scaffold).first);
    final controller = context.read<AppController>();

    // --- Folder selection ---
    // The native OS folder-picker dialog lives outside the Flutter engine
    // and can't be driven by integration_test; we call the same method the
    // "Add Folder" button calls, exercising identical app logic.
    controller.addCustomFolder(testDir.path);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Start Scan'),
      findsOneWidget,
      reason: 'Start Scan button should be enabled once a folder is selected',
    );

    // --- Scanning: real Stage 0-3 pipeline, real BLAKE3 via dart:ffi ---
    await tester.tap(find.textContaining('Start Scan'));
    await tester.pump();
    expect(find.byType(ScanScreen), findsOneWidget);

    await pumpUntil(tester, () => controller.screen == AppScreen.results);
    expect(find.byType(ResultsScreen), findsOneWidget);

    // --- Verify duplicate detection against known ground truth ---
    final result = controller.lastResult;
    expect(result, isNotNull);
    expect(
      result!.groups.length,
      1,
      reason: 'exactly one duplicate group (duplicate_a/duplicate_b)',
    );
    final group = result.groups.single;
    expect(group.files.length, 2);
    expect(group.fileSize, greaterThan(0));
    final groupPaths = group.files.map((f) => f.path).toSet();
    expect(groupPaths, {fileA.path, fileB.path});
    // unique.txt must never appear in any duplicate group.
    for (final g in result.groups) {
      expect(g.files.any((f) => f.path == fileUnique.path), isFalse);
    }
    expect(result.errors, isEmpty);

    // --- Duplicate selection (smart selection already applied post-scan) ---
    expect(
      controller.selectedCount,
      1,
      reason:
          'exactly one of the two duplicates should be pre-selected for deletion',
    );
    final keep = controller.keepFileFor(group);
    final toDelete = group.files.firstWhere((f) => f != keep);
    expect(controller.isSelectedForDeletion(toDelete), isTrue);
    expect(controller.isSelectedForDeletion(keep), isFalse);

    // --- Recycle Bin deletion, through the real confirmation dialog ---
    await tester.tap(
      find
          .byWidgetPredicate((w) => w is FilledButton && w.onPressed != null)
          .first,
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Move to Trash?'),
      findsOneWidget,
      reason:
          'Windows has a real Recycle Bin, so the non-permanent-delete dialog must show',
    );
    await tester.tap(find.text('Move to Trash'));
    await tester.pumpAndSettle();

    // --- Verify the actual filesystem effect ---
    expect(
      await File(toDelete.path).exists(),
      isFalse,
      reason: 'deleted duplicate must be gone from its original location',
    );
    expect(
      await File(keep.path).exists(),
      isTrue,
      reason: 'the kept copy must survive',
    );
    expect(
      await fileUnique.exists(),
      isTrue,
      reason: 'the unrelated unique file must be untouched',
    );
  });

  testWidgets('production build: cancellation stops a scan cleanly', (
    tester,
  ) async {
    final testDir = await Directory.systemTemp.createTemp(
      'dupora_itest_cancel_',
    );
    addTearDown(() async {
      if (await testDir.exists()) await testDir.delete(recursive: true);
    });
    for (var i = 0; i < 25; i++) {
      await File(
        '${testDir.path}\\f$i.txt',
      ).writeAsString('shared content $i % 3 = ${i % 3}');
    }

    await tester.pumpWidget(const DuporaBootstrap());
    await pumpUntil(tester, () => find.byType(Scaffold).evaluate().isNotEmpty);
    await tester.pump(const Duration(seconds: 2));

    final context = tester.element(find.byType(Scaffold).first);
    final controller = context.read<AppController>();

    controller.addCustomFolder(testDir.path);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Start Scan'));
    await tester.pump();

    // Cancel almost immediately.
    await controller.cancelScan();
    await pumpUntil(
      tester,
      () =>
          controller.lastProgress?.isCancelled == true ||
          controller.screen == AppScreen.results,
    );

    expect(controller.lastProgress?.isCancelled, isTrue);
  });
}
