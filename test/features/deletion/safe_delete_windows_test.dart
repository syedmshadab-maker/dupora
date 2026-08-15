@Tags(['integration'])
library;

import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:dupora/features/deletion/protected_locations.dart';
import 'package:dupora/features/deletion/safe_delete_service.dart';
import 'package:dupora/features/deletion/safe_delete_windows.dart';
import 'package:dupora/features/scanner/domain/scanned_file.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win32/win32.dart';

/// Real Win32 exercise of [WindowsDeleter] and the structured
/// locked/permission-denied outcomes it feeds into [SafeDeleteCoordinator]
/// - not mocked, since the whole point is proving the real
/// `SHFileOperationW` failure path is classified correctly rather than
/// crashing or reporting an opaque generic failure (Phase 2 audit item 3).
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dupora_windelete_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('an unlocked file is moved to the Recycle Bin normally', () async {
    final path = '${tempDir.path}${Platform.pathSeparator}plain.txt';
    await File(path).writeAsString('content');

    await WindowsDeleter().deleteFile(path);

    expect(await File(path).exists(), isFalse);
  });

  test('a read-only file is still moved to the Recycle Bin normally '
      '(SHFileOperationW with FOF_NOCONFIRMATION must not need an '
      'interactive read-only-delete prompt)', () async {
    final path = '${tempDir.path}${Platform.pathSeparator}readonly.txt';
    final file = File(path);
    await file.writeAsString('read-only content');
    await Process.run('attrib', ['+R', path]);

    try {
      await WindowsDeleter().deleteFile(path);
      expect(await file.exists(), isFalse);
    } finally {
      // Best-effort: if the delete above failed for some reason, don't
      // leave a read-only file behind that the tearDown's recursive
      // directory delete can't remove.
      if (await file.exists()) {
        await Process.run('attrib', ['-R', path]);
      }
    }
  });

  test('a file exclusively locked by another handle raises '
      'RecycleBinLockedException, not a generic failure', () async {
    final path = '${tempDir.path}${Platform.pathSeparator}locked.txt';
    await File(path).writeAsString('locked content');

    final pathPtr = path.toNativeUtf16();
    final handle = CreateFile(
      pathPtr,
      GENERIC_READ,
      0, // dwShareMode = 0: exclusive, no sharing at all.
      ffi.nullptr,
      OPEN_EXISTING,
      FILE_ATTRIBUTE_NORMAL,
      0,
    );
    calloc.free(pathPtr);
    expect(
      handle,
      isNot(INVALID_HANDLE_VALUE),
      reason: 'test setup: could not open an exclusive lock on the file',
    );

    try {
      await expectLater(
        WindowsDeleter().deleteFile(path),
        throwsA(isA<RecycleBinLockedException>()),
      );
      // The file must still exist - a failed/locked delete must never
      // leave the file half-deleted or gone.
      expect(await File(path).exists(), isTrue);
    } finally {
      CloseHandle(handle);
    }

    // Once released, the same path deletes normally.
    await WindowsDeleter().deleteFile(path);
    expect(await File(path).exists(), isFalse);
  });

  test('SafeDeleteCoordinator reports a locked file as DeleteOutcome.locked '
      'and continues the batch rather than throwing', () async {
    final lockedPath = '${tempDir.path}${Platform.pathSeparator}locked.txt';
    final normalPath = '${tempDir.path}${Platform.pathSeparator}normal.txt';
    await File(lockedPath).writeAsString('locked');
    await File(normalPath).writeAsString('normal');

    final lockedFile = ScannedFile(
      path: lockedPath,
      name: 'locked.txt',
      extension: 'txt',
      size: await File(lockedPath).length(),
      modifiedAt: await File(lockedPath).lastModified(),
    );
    final normalFile = ScannedFile(
      path: normalPath,
      name: 'normal.txt',
      extension: 'txt',
      size: await File(normalPath).length(),
      modifiedAt: await File(normalPath).lastModified(),
    );

    final pathPtr = lockedPath.toNativeUtf16();
    final handle = CreateFile(
      pathPtr,
      GENERIC_READ,
      0,
      ffi.nullptr,
      OPEN_EXISTING,
      FILE_ATTRIBUTE_NORMAL,
      0,
    );
    calloc.free(pathPtr);

    try {
      final coordinator = SafeDeleteCoordinator(
        protectedLocations: ProtectedLocations(userDefined: const []),
      );

      final results = await coordinator.deleteAll([lockedFile, normalFile]);

      final lockedResult = results.firstWhere((r) => r.path == lockedPath);
      final normalResult = results.firstWhere((r) => r.path == normalPath);

      expect(lockedResult.outcome, DeleteOutcome.locked);
      expect(lockedResult.succeeded, isFalse);
      // The one locked file must not have aborted the rest of the batch.
      expect(normalResult.succeeded, isTrue);
      expect(await File(lockedPath).exists(), isTrue);
      expect(await File(normalPath).exists(), isFalse);
    } finally {
      CloseHandle(handle);
    }
  });
}
