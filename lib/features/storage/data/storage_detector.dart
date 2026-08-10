import 'dart:io';

import '../domain/storage_volume.dart';
import 'storage_detector_linux.dart';
import 'storage_detector_macos.dart';
import 'storage_detector_windows.dart';

abstract class StorageDetector {
  Future<List<StorageVolume>> listVolumes();

  factory StorageDetector.forPlatform() {
    if (Platform.isWindows) return WindowsStorageDetector();
    if (Platform.isMacOS) return MacOsStorageDetector();
    if (Platform.isLinux) return LinuxStorageDetector();
    if (Platform.isAndroid) {
      throw UnsupportedError(
        'Android storage is exposed through AndroidStorageDetector (SAF-based), '
        'not the generic StorageDetector.forPlatform() path.',
      );
    }
    throw UnsupportedError('No storage detector for ${Platform.operatingSystem}');
  }
}
