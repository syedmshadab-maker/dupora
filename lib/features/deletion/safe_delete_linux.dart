import 'dart:io';

import 'package:path/path.dart' as p;

import 'safe_delete_service.dart';

/// Moves files to Trash following the freedesktop.org Trash specification.
/// Prefers shelling out to `gio trash` (GNOME's GIO, present on virtually
/// every modern Linux desktop and DE-agnostic), falling back to a manual
/// `~/.local/share/Trash` move + `.trashinfo` sidecar when `gio` isn't
/// installed (e.g. minimal window-manager-only setups).
///
/// NOTE: this repository was built on Windows, so this class has not been
/// exercised on real Linux hardware. See BUILD.md / KNOWN LIMITATIONS. The
/// freedesktop fallback logic is still unit-tested in isolation (see
/// `test/features/deletion/safe_delete_linux_test.dart`).
class LinuxDeleter implements PlatformDeleter {
  @override
  bool get hasTrash => true;

  @override
  Future<void> deleteFile(String path) async {
    if (await _tryGioTrash(path)) return;
    await moveToFreedesktopTrash(path);
  }

  Future<bool> _tryGioTrash(String path) async {
    try {
      final result = await Process.run('gio', ['trash', path]);
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  /// Exposed as a static, side-effect-isolated function of its inputs (plus
  /// injectable home/time) so the trashinfo format can be unit tested
  /// without touching the real filesystem trash location.
  static Future<void> moveToFreedesktopTrash(
    String path, {
    String? homeOverride,
    DateTime? nowOverride,
  }) async {
    final home = homeOverride ?? Platform.environment['HOME'] ?? '/root';
    final trashDir = p.join(home, '.local', 'share', 'Trash');
    final filesDir = p.join(trashDir, 'files');
    final infoDir = p.join(trashDir, 'info');
    await Directory(filesDir).create(recursive: true);
    await Directory(infoDir).create(recursive: true);

    final baseName = p.basename(path);
    var targetName = baseName;
    var counter = 1;
    while (await File(p.join(filesDir, targetName)).exists() ||
        await Directory(p.join(filesDir, targetName)).exists()) {
      targetName = '$baseName.$counter';
      counter++;
    }

    final now = nowOverride ?? DateTime.now();
    final infoContent = buildTrashInfo(originalPath: path, deletionDate: now);
    await File(p.join(infoDir, '$targetName.trashinfo')).writeAsString(infoContent);
    await File(path).rename(p.join(filesDir, targetName));
  }

  /// Pure formatting function for the `.trashinfo` sidecar, per the
  /// freedesktop.org Trash spec (`[Trash Info]` section with `Path` and
  /// `DeletionDate` keys, `Path` percent-encoded, `DeletionDate` in
  /// `YYYY-MM-DDThh:mm:ss`).
  static String buildTrashInfo({required String originalPath, required DateTime deletionDate}) {
    final encodedPath = Uri.encodeFull(originalPath);
    String two(int n) => n.toString().padLeft(2, '0');
    final iso = '${deletionDate.year}-${two(deletionDate.month)}-${two(deletionDate.day)}'
        'T${two(deletionDate.hour)}:${two(deletionDate.minute)}:${two(deletionDate.second)}';
    return '[Trash Info]\nPath=$encodedPath\nDeletionDate=$iso\n';
  }
}
