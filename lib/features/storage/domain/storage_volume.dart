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

  /// Drive root, e.g. `C:\`.
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
