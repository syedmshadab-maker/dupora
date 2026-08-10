// Stress test against the REAL compiled application: thousands of files,
// many duplicate groups, real concurrent hashing via the bounded worker
// pool, and real memory measurements (ProcessInfo.currentRss - this test
// runs inside the actual dupora.exe process, so this is the app's own
// memory use, not an estimate). Numbers are printed, not just asserted,
// so they can be read directly rather than taken on faith - see the test
// output and PERFORMANCE.md for what was actually measured on this
// machine.
//
// Scale note: this generates thousands of files, not millions - "if the
// current machine permits it" was scoped to what a single dev VM can do
// in a CI-reasonable amount of time. See PERFORMANCE.md for exactly what
// this does and does not demonstrate about larger-scale performance.

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
  int maxSteps = 900, // 180s ceiling for the stress scans
}) async {
  for (var i = 0; i < maxSteps; i++) {
    if (condition()) return;
    await tester.pump(step);
  }
  throw _TimeoutException(
    'condition not met within ${maxSteps * step.inMilliseconds}ms',
  );
}

const int _totalFiles = 5000;
const int _duplicateGroupCount = 400;
const int _filesPerGroup = 10; // 400 * 10 = 4000 duplicate files
// remaining 1000 files are unique

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'stress: thousands of files, many duplicate groups, memory, cancellation, repeated scans',
    (tester) async {
      final root = await Directory.systemTemp.createTemp('dupora_stress_');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });

      final genStopwatch = Stopwatch()..start();
      var written = 0;
      for (var g = 0; g < _duplicateGroupCount; g++) {
        final content = 'duplicate-group-$g-' * 20; // a few hundred bytes
        for (var i = 0; i < _filesPerGroup; i++) {
          File('${root.path}\\dup_${g}_$i.txt').writeAsStringSync(content);
          written++;
        }
      }
      final uniqueCount = _totalFiles - (_duplicateGroupCount * _filesPerGroup);
      for (var i = 0; i < uniqueCount; i++) {
        File(
          '${root.path}\\unique_$i.txt',
        ).writeAsStringSync('unique-file-content-$i-${'x' * (i % 200)}');
        written++;
      }
      genStopwatch.stop();
      // ignore: avoid_print
      print(
        '[STRESS] generated $written files in ${genStopwatch.elapsedMilliseconds}ms',
      );

      await tester.pumpWidget(const DuporaBootstrap());
      await _pumpUntil(
        tester,
        () => find.byType(Scaffold).evaluate().isNotEmpty,
      );
      await tester.pump(const Duration(seconds: 2));

      final context = tester.element(find.byType(Scaffold).first);
      final controller = context.read<AppController>();

      final rssBefore = ProcessInfo.currentRss;

      // --- First scan: cold, everything gets hashed ---
      controller.addCustomFolder(root.path);
      await tester.pumpAndSettle();
      final scan1 = Stopwatch()..start();
      await tester.tap(find.textContaining('Start Scan'));
      await tester.pump();

      var peakRss = rssBefore;
      while (controller.screen != AppScreen.results) {
        await tester.pump(const Duration(milliseconds: 200));
        final rss = ProcessInfo.currentRss;
        if (rss > peakRss) peakRss = rss;
      }
      scan1.stop();

      final result1 = controller.lastResult!;
      // ignore: avoid_print
      print(
        '[STRESS] first scan: ${result1.groups.length} groups, '
        '${result1.finalProgress.totalFiles} files discovered, '
        '${scan1.elapsedMilliseconds}ms wall clock, '
        '${(scan1.elapsedMilliseconds > 0 ? (result1.finalProgress.totalFiles * 1000 / scan1.elapsedMilliseconds) : 0).toStringAsFixed(0)} files/sec average',
      );
      // ignore: avoid_print
      print(
        '[STRESS] memory: ${(rssBefore / 1024 / 1024).toStringAsFixed(1)}MB before -> '
        '${(peakRss / 1024 / 1024).toStringAsFixed(1)}MB peak during scan '
        '(+${((peakRss - rssBefore) / 1024 / 1024).toStringAsFixed(1)}MB)',
      );

      expect(result1.finalProgress.phase, ScanPhase.completed);
      expect(
        result1.groups.length,
        _duplicateGroupCount,
        reason:
            'every generated duplicate group must be found, and only those groups',
      );
      for (final g in result1.groups) {
        expect(g.files.length, _filesPerGroup);
      }
      expect(result1.errors, isEmpty);

      // --- Repeated scan: cache should make this meaningfully faster ---
      controller.backToHome();
      await tester.pumpAndSettle();
      controller.addCustomFolder(root.path);
      await tester.pumpAndSettle();
      final scan2 = Stopwatch()..start();
      await tester.tap(find.textContaining('Start Scan'));
      await tester.pump();
      await _pumpUntil(tester, () => controller.screen == AppScreen.results);
      scan2.stop();

      final result2 = controller.lastResult!;
      expect(result2.groups.length, _duplicateGroupCount);
      // ignore: avoid_print
      print(
        '[STRESS] second (cached) scan: ${scan2.elapsedMilliseconds}ms wall clock '
        '(first scan was ${scan1.elapsedMilliseconds}ms) - '
        '${scan1.elapsedMilliseconds > 0 ? (scan1.elapsedMilliseconds / (scan2.elapsedMilliseconds == 0 ? 1 : scan2.elapsedMilliseconds)).toStringAsFixed(1) : "?"}x',
      );
      expect(
        scan2.elapsedMilliseconds,
        lessThan(scan1.elapsedMilliseconds),
        reason:
            'a fully-cached rescan of an unchanged tree must be faster than the cold scan',
      );

      // --- Cancellation under load: start a third scan, cancel almost
      // immediately, verify it actually stops rather than running to
      // completion regardless. ---
      controller.backToHome();
      await tester.pumpAndSettle();
      controller.addCustomFolder(root.path);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Start Scan'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await controller.cancelScan();
      await _pumpUntil(
        tester,
        () =>
            controller.lastProgress?.isCancelled == true ||
            controller.screen == AppScreen.results,
      );
      expect(
        controller.lastProgress?.isCancelled,
        isTrue,
        reason: 'cancellation must take effect even mid-stress-scan',
      );

      // ignore: avoid_print
      print('[STRESS] cancellation under load: OK');
    },
  );
}
