import 'dart:io';

import '../domain/storage_volume.dart';
import 'storage_detector.dart';

/// Enumerates the root volume plus everything mounted under `/Volumes`
/// (external disks, network shares, disk images) - the standard macOS
/// mount convention.
///
/// NOTE: written against documented macOS conventions and `dart:io`'s
/// `Directory.stat`/`FileStat`, but this repository was built on Windows,
/// so this class has not been exercised on real macOS hardware. See
/// BUILD.md / KNOWN LIMITATIONS.
class MacOsStorageDetector implements StorageDetector {
  @override
  Future<List<StorageVolume>> listVolumes() async {
    final volumes = <StorageVolume>[];

    final root = await _probe('/', VolumeType.fixed);
    if (root != null) volumes.add(root);

    final volumesDir = Directory('/Volumes');
    if (await volumesDir.exists()) {
      await for (final entry in volumesDir.list(followLinks: false)) {
        if (entry is! Directory) continue;
        final volume = await _probe(entry.path, VolumeType.removable);
        if (volume != null) volumes.add(volume);
      }
    }

    return volumes;
  }

  Future<StorageVolume?> _probe(String path, VolumeType fallbackType) async {
    try {
      final statfsResult = await _statfsBytes(path);
      if (statfsResult == null) return null;
      final (total, free) = statfsResult;
      return StorageVolume(
        rootPath: path,
        label: path == '/' ? 'Macintosh HD' : path.split('/').last,
        type: fallbackType,
        totalBytes: total,
        freeBytes: free,
        deviceId: path,
      );
    } catch (_) {
      return null;
    }
  }

  /// `dart:io` has no direct statfs binding; we shell out to `df -k` rather
  /// than hand-write a native `statfs(2)` FFI binding for a single numeric
  /// pair, keeping this platform's storage detector free of extra native
  /// code to compile/ship.
  Future<(int, int)?> _statfsBytes(String path) async {
    final result = await Process.run('df', ['-k', path]);
    if (result.exitCode != 0) return null;
    final lines = (result.stdout as String).trim().split('\n');
    if (lines.length < 2) return null;
    final fields = lines.last.trim().split(RegExp(r'\s+'));
    if (fields.length < 4) return null;
    final totalKb = int.tryParse(fields[1]);
    final availKb = int.tryParse(fields[3]);
    if (totalKb == null || availKb == null) return null;
    return (totalKb * 1024, availKb * 1024);
  }
}
