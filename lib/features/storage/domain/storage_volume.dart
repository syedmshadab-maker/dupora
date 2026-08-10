import 'package:meta/meta.dart';

enum VolumeType { fixed, removable, network, cdRom, ramDisk, unknown }

@immutable
class StorageVolume {
  const StorageVolume({
    required this.rootPath,
    required this.label,
    required this.type,
    required this.totalBytes,
    required this.freeBytes,
    this.deviceId,
  });

  /// Mount root, e.g. `C:\` on Windows, `/` or `/Volumes/Backup` on macOS,
  /// a mount point from `/proc/mounts` on Linux, or a SAF tree URI's
  /// display root on Android.
  final String rootPath;
  final String? label;
  final VolumeType type;
  final int totalBytes;
  final int freeBytes;

  /// Best-effort filesystem/device identifier, when the platform exposes
  /// one cheaply (used to disambiguate cache entries across volumes).
  final String? deviceId;

  bool get isRemovable => type == VolumeType.removable;

  int get usedBytes => (totalBytes - freeBytes).clamp(0, totalBytes);

  double get usedFraction => totalBytes == 0 ? 0 : usedBytes / totalBytes;
}
