import 'dart:io';

import '../domain/storage_volume.dart';
import 'storage_detector_windows.dart';

abstract class StorageDetector {
  Future<List<StorageVolume>> listVolumes();

  /// Windows-only today. Kept as a factory (rather than constructing
  /// [WindowsStorageDetector] directly at call sites) so a future
  /// portable-device (MTP) detector has a seam to plug into without
  /// touching callers.
  factory StorageDetector.forPlatform() {
    if (Platform.isWindows) return WindowsStorageDetector();
    throw UnsupportedError(
      'No storage detector for ${Platform.operatingSystem}',
    );
  }
}
