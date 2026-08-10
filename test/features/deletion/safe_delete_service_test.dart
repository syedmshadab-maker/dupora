import 'dart:io';

import 'package:dupora/features/deletion/protected_locations.dart';
import 'package:dupora/features/deletion/safe_delete_service.dart';
import 'package:dupora/features/scanner/domain/scanned_file.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeDeleter implements PlatformDeleter {
  _FakeDeleter({this.hasTrash = true, this.throwOnDelete = false});

  @override
  final bool hasTrash;
  final bool throwOnDelete;
  final List<String> deleted = [];

  @override
  Future<void> deleteFile(String path) async {
    if (throwOnDelete) {
      throw StateError('simulated platform delete failure');
    }
    deleted.add(path);
    await File(path).delete();
  }
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dupora_delete_test_');
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

  test(
    'deletes a genuine, unmodified duplicate and reports movedToTrash when a trash exists',
    () async {
      final deleter = _FakeDeleter(hasTrash: true);
      final coordinator = SafeDeleteCoordinator(
        protectedLocations: ProtectedLocations(userDefined: const []),
        deleter: deleter,
      );
      final file = await makeFile('dup.txt', 'duplicate content');

      final result = await coordinator.delete(file);

      expect(result.outcome, DeleteOutcome.movedToTrash);
      expect(result.succeeded, isTrue);
      expect(deleter.deleted, [file.path]);
      expect(await File(file.path).exists(), isFalse);
    },
  );

  test('reports permanentlyDeleted when the platform has no trash', () async {
    final deleter = _FakeDeleter(hasTrash: false);
    final coordinator = SafeDeleteCoordinator(
      protectedLocations: ProtectedLocations(userDefined: const []),
      deleter: deleter,
    );
    final file = await makeFile('dup.txt', 'duplicate content');

    final result = await coordinator.delete(file);

    expect(result.outcome, DeleteOutcome.permanentlyDeleted);
  });

  test(
    'never deletes the file designated as keep, even if selected by mistake',
    () async {
      final deleter = _FakeDeleter();
      final coordinator = SafeDeleteCoordinator(
        protectedLocations: ProtectedLocations(userDefined: const []),
        deleter: deleter,
      );
      final keep = await makeFile('keep.txt', 'content');

      final result = await coordinator.delete(keep, mustNotEqual: keep);

      expect(result.outcome, DeleteOutcome.skippedProtected);
      expect(deleter.deleted, isEmpty);
      expect(await File(keep.path).exists(), isTrue);
    },
  );

  test('never deletes a file inside a protected location', () async {
    final deleter = _FakeDeleter();
    final coordinator = SafeDeleteCoordinator(
      protectedLocations: ProtectedLocations(userDefined: [tempDir.path]),
      deleter: deleter,
    );
    final file = await makeFile('dup.txt', 'content');

    final result = await coordinator.delete(file);

    expect(result.outcome, DeleteOutcome.skippedProtected);
    expect(deleter.deleted, isEmpty);
  });

  test('refuses to delete a file that no longer exists', () async {
    final deleter = _FakeDeleter();
    final coordinator = SafeDeleteCoordinator(
      protectedLocations: ProtectedLocations(userDefined: const []),
      deleter: deleter,
    );
    final file = await makeFile('dup.txt', 'content');
    await File(file.path).delete();

    final result = await coordinator.delete(file);

    expect(result.outcome, DeleteOutcome.notFound);
  });

  test(
    'refuses to delete when the on-disk size no longer matches the scanned size '
    '(a stale scan result must not delete a different/new file at the same path)',
    () async {
      final deleter = _FakeDeleter();
      final coordinator = SafeDeleteCoordinator(
        protectedLocations: ProtectedLocations(userDefined: const []),
        deleter: deleter,
      );
      final file = await makeFile('dup.txt', 'short');
      // Simulate the path being reused by a different, larger file after the
      // scan ran but before the delete was confirmed.
      await File(
        file.path,
      ).writeAsString('this replacement content is much longer than before');

      final result = await coordinator.delete(file);

      expect(result.outcome, DeleteOutcome.identityMismatch);
      expect(deleter.deleted, isEmpty);
      expect(await File(file.path).exists(), isTrue);
    },
  );

  test(
    'refuses to delete when mtime changed even though size coincidentally matches '
    '(closes the gap a size-only check would miss)',
    () async {
      final deleter = _FakeDeleter();
      final coordinator = SafeDeleteCoordinator(
        protectedLocations: ProtectedLocations(userDefined: const []),
        deleter: deleter,
      );
      final file = await makeFile('dup.txt', 'exact-same-length!');
      // Overwrite with different content of identical length, then force the
      // mtime explicitly (rather than relying on real-clock timing, whose
      // granularity is filesystem-dependent and made this test flaky).
      await File(file.path).writeAsString('exact-same-length#');
      await File(
        file.path,
      ).setLastModified(file.modifiedAt.add(const Duration(days: 1)));

      final result = await coordinator.delete(file);

      expect(result.outcome, DeleteOutcome.identityMismatch);
      expect(deleter.deleted, isEmpty);
    },
  );

  test(
    'rejects a duplicate/concurrent delete request for the same path',
    () async {
      final deleter = _FakeDeleter();
      final coordinator = SafeDeleteCoordinator(
        protectedLocations: ProtectedLocations(userDefined: const []),
        deleter: deleter,
      );
      final file = await makeFile('dup.txt', 'content');

      final first = coordinator.delete(file);
      final second = await coordinator.delete(file);
      final firstResult = await first;

      expect(firstResult.succeeded, isTrue);
      expect(second.outcome, DeleteOutcome.skippedAlreadyRequested);
    },
  );

  test(
    'a platform delete failure is reported and allows a later retry',
    () async {
      final deleter = _FakeDeleter(throwOnDelete: true);
      final coordinator = SafeDeleteCoordinator(
        protectedLocations: ProtectedLocations(userDefined: const []),
        deleter: deleter,
      );
      final file = await makeFile('dup.txt', 'content');

      final failed = await coordinator.delete(file);
      expect(failed.outcome, DeleteOutcome.failed);
      expect(await File(file.path).exists(), isTrue);

      // The path should not be permanently stuck in the in-flight set after a
      // genuine failure: calling delete again on the *same* coordinator must
      // actually retry (and fail again, since the deleter still throws)
      // rather than short-circuiting to skippedAlreadyRequested.
      final secondAttempt = await coordinator.delete(file);
      expect(secondAttempt.outcome, DeleteOutcome.failed);
      expect(deleter.deleted, isEmpty);
    },
  );
}
