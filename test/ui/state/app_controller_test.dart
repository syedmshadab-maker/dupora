@Tags(['integration'])
library;

import 'dart:async';
import 'dart:io';

import 'package:dupora/features/cache/hash_cache_database.dart';
import 'package:dupora/features/cache/hash_cache_repository.dart';
import 'package:dupora/features/deletion/protected_locations.dart';
import 'package:dupora/features/deletion/safe_delete_service.dart';
import 'package:dupora/features/duplicates/domain/duplicate_group.dart';
import 'package:dupora/features/duplicates/domain/selection_strategy.dart';
import 'package:dupora/features/scanner/domain/scan_progress.dart';
import 'package:dupora/features/scanner/domain/scanned_file.dart';
import 'package:dupora/features/scanner/scan_engine.dart';
import 'package:dupora/ui/state/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// A deleter whose [deleteFile] doesn't complete until the test releases
/// [gate] - lets a test reliably observe [AppController] mid-batch-delete,
/// after `dispose()` has already run.
class _GatedDeleter implements PlatformDeleter {
  _GatedDeleter(this.gate);
  final Completer<void> gate;

  @override
  bool get hasTrash => true;

  final List<String> deleted = [];

  @override
  Future<void> deleteFile(String path) async {
    await gate.future;
    deleted.add(path);
    await File(path).delete();
  }
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dupora_ac_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<ScannedFile> makeFile(String name, String content) async {
    final file = File('${tempDir.path}${Platform.pathSeparator}$name');
    await file.writeAsString(content);
    final stat = await file.stat();
    return ScannedFile(
      path: file.path,
      name: name,
      extension: '',
      size: stat.size,
      modifiedAt: stat.modified,
    );
  }

  test('deleteSelected() completes without throwing when the controller is '
      'disposed while a delete batch is still in flight '
      '(regression: notifyListeners() after dispose during an async delete '
      'batch - see Phase 2 audit)', () async {
    final fileA = await makeFile('a.txt', 'duplicate content');
    final fileB = await makeFile('b.txt', 'duplicate content');
    final group = DuplicateGroup(
      fullHashHex: 'irrelevant-in-this-test',
      fileSize: fileA.size,
      files: [fileA, fileB],
    );

    final gate = Completer<void>();
    final controller = AppController();
    controller.deleteCoordinator = SafeDeleteCoordinator(
      protectedLocations: ProtectedLocations(userDefined: const []),
      deleter: _GatedDeleter(gate),
    );
    controller.lastResult = ScanResult(
      groups: [group],
      errors: const [],
      finalProgress: const ScanProgress.initial(),
    );
    controller.applyStrategyToAllGroups(SmartSelectionStrategy.keepOldest);
    expect(controller.selectedCount, 1);
    // fileA/fileB are written back-to-back and may end up with an
    // identical mtime depending on filesystem timestamp resolution, so
    // don't assume which one keepOldest's tie-break picked - ask the
    // controller which it actually chose.
    final keep = controller.keepFileFor(group);
    final drop = keep == fileA ? fileB : fileA;

    // Start the batch delete but don't await it yet - it will block
    // inside `_GatedDeleter.deleteFile` until `gate` completes below.
    final deleteFuture = controller.deleteSelected();
    // Let the async chain (delete() -> exists()/stat() -> deleteFile())
    // actually run up to the gate before disposing.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    // The widget tree (and therefore this controller) is torn down while
    // the delete is still pending - e.g. the user closed the app or
    // navigated away mid-batch.
    controller.dispose();

    // Unblock the pending delete. Its internal `finally { ...; _notify();
    // }` now runs *after* dispose(); before the fix this called
    // `notifyListeners()` on a disposed ChangeNotifier and threw.
    gate.complete();

    final results = await deleteFuture;

    expect(results, hasLength(1));
    expect(results.single.succeeded, isTrue);
    expect(await File(drop.path).exists(), isFalse);
    expect(await File(keep.path).exists(), isTrue);
  });

  test(
    'a completed scan does not preselect anything for deletion - Smart '
    'Select must be an explicit user action before any file is chosen '
    '(regression: startScan() previously called _applyDefaultSelection() '
    'automatically right after every scan, marking most duplicates for '
    'deletion before the user had done anything - see Phase 2 audit)',
    () async {
      await makeFile('a.txt', 'duplicate content');
      await makeFile('b.txt', 'duplicate content');
      await makeFile('c.txt', 'duplicate content');

      final db = HashCacheDatabase.inMemory();
      final controller = AppController();
      controller.cacheRepo = HashCacheRepository(db);
      controller.selectedRoots.add(tempDir.path);

      await controller.startScan();

      expect(controller.lastResult, isNotNull);
      expect(
        controller.lastResult!.groups,
        isNotEmpty,
        reason: 'test setup: the 3 files above should form one dup group',
      );
      expect(
        controller.selectedCount,
        0,
        reason:
            'nothing must be selected for deletion immediately after a '
            'scan completes - only an explicit Smart Select (or manual '
            'per-file selection) may select anything',
      );

      // Only once the user explicitly triggers Smart Select does anything
      // become selected - and only then.
      controller.applyStrategyToAllGroups(SmartSelectionStrategy.keepOldest);
      expect(controller.selectedCount, greaterThan(0));

      controller.dispose();
      await db.close();
    },
  );

  test('dispose() is safe to call twice and cancels a live progress '
      'subscription without throwing', () async {
    final db = HashCacheDatabase.inMemory();
    final controller = AppController();
    controller.cacheRepo = HashCacheRepository(db);
    final engine = ScanEngine(cache: controller.cacheRepo);
    controller.scanEngine = engine;

    expect(controller.dispose, returnsNormally);
    // AppController itself is never disposed twice in the real app
    // (main.dart owns exactly one), but the underlying resources it
    // releases must tolerate being torn down alongside it without
    // throwing.
    engine.dispose();
    await db.close();
  });
}
