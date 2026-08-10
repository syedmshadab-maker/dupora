import 'dart:io';

import '../domain/storage_volume.dart';
import 'storage_detector.dart';

/// Filesystem type prefixes never worth scanning for user files: virtual,
/// pseudo, or kernel-managed filesystems from `/proc/mounts`.
const _virtualFsTypes = {
  'proc', 'sysfs', 'devtmpfs', 'devpts', 'tmpfs', 'cgroup', 'cgroup2', 'pstore',
  'securityfs', 'debugfs', 'tracefs', 'configfs', 'fusectl', 'mqueue', 'hugetlbfs',
  'binfmt_misc', 'autofs', 'overlay', 'squashfs', 'efivarfs', 'bpf', 'rpc_pipefs',
};

/// Parses `/proc/mounts` and reports real, user-relevant filesystems
/// (internal disks, removable media under `/media` or `/run/media`,
/// network shares), skipping virtual/kernel filesystems.
///
/// NOTE: written against the standard Linux `/proc/mounts` format and
/// `statvfs`-equivalent free-space reporting via `df`, but this repository
/// was built on Windows, so this class has not been exercised on real
/// Linux hardware. See BUILD.md / KNOWN LIMITATIONS.
class LinuxStorageDetector implements StorageDetector {
  @override
  Future<List<StorageVolume>> listVolumes() async {
    final mountsFile = File('/proc/mounts');
    if (!await mountsFile.exists()) return [];
    final content = await mountsFile.readAsString();
    return parseMounts(content, statFn: _dfStats);
  }

  /// Exposed separately so the parsing logic can be unit tested with a
  /// synthetic `/proc/mounts` string and a fake stat function, without
  /// needing to run on Linux or shell out to `df`.
  static Future<List<StorageVolume>> parseMounts(
    String mountsContent, {
    required Future<(int, int)?> Function(String path) statFn,
  }) async {
    final volumes = <StorageVolume>[];
    for (final line in mountsContent.split('\n')) {
      if (line.trim().isEmpty) continue;
      final fields = line.split(' ');
      if (fields.length < 3) continue;
      final device = fields[0];
      final mountPoint = _unescapeOctal(fields[1]);
      final fsType = fields[2];

      if (_virtualFsTypes.contains(fsType)) continue;
      if (!device.startsWith('/dev/') && !device.contains(':/')) continue;
      if (mountPoint == '/boot' || mountPoint == '/boot/efi') continue;

      final stats = await statFn(mountPoint);
      if (stats == null) continue;
      final (total, free) = stats;
      if (total == 0) continue;

      final isRemovable = mountPoint.startsWith('/media/') || mountPoint.startsWith('/run/media/');
      volumes.add(StorageVolume(
        rootPath: mountPoint,
        label: mountPoint == '/' ? 'Root' : mountPoint.split('/').last,
        type: isRemovable ? VolumeType.removable : VolumeType.fixed,
        totalBytes: total,
        freeBytes: free,
        deviceId: device,
      ));
    }
    return volumes;
  }

  static String _unescapeOctal(String s) {
    return s.replaceAllMapped(RegExp(r'\\([0-7]{3})'), (m) {
      return String.fromCharCode(int.parse(m[1]!, radix: 8));
    });
  }

  static Future<(int, int)?> _dfStats(String path) async {
    try {
      final result = await Process.run('df', ['-B1', path]);
      if (result.exitCode != 0) return null;
      final lines = (result.stdout as String).trim().split('\n');
      if (lines.length < 2) return null;
      final fields = lines.last.trim().split(RegExp(r'\s+'));
      if (fields.length < 4) return null;
      final total = int.tryParse(fields[1]);
      final avail = int.tryParse(fields[3]);
      if (total == null || avail == null) return null;
      return (total, avail);
    } catch (_) {
      return null;
    }
  }
}
