import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import '../domain/storage_volume.dart';
import 'storage_detector.dart';

/// Enumerates Windows volumes (`C:\`, `D:\`, ...) via native Win32 APIs,
/// classifying fixed vs. removable/USB/external drives and reporting
/// used/free space - all required per the project's storage-detection spec.
class WindowsStorageDetector implements StorageDetector {
  @override
  Future<List<StorageVolume>> listVolumes() async {
    final volumes = <StorageVolume>[];
    final mask = GetLogicalDrives();
    if (mask == 0) return volumes;

    for (var i = 0; i < 26; i++) {
      if ((mask & (1 << i)) == 0) continue;
      final letter = String.fromCharCode('A'.codeUnitAt(0) + i);
      final root = '$letter:\\';
      final volume = _probeVolume(root);
      if (volume != null) volumes.add(volume);
    }
    return volumes;
  }

  StorageVolume? _probeVolume(String root) {
    final rootPtr = root.toNativeUtf16();
    try {
      final driveType = GetDriveType(rootPtr);
      // Skip drives with no media present (empty card readers, DVD drives
      // with no disc) rather than reporting a bogus 0-byte volume.
      if (driveType == DRIVE_NO_ROOT_DIR) return null;

      final type = switch (driveType) {
        DRIVE_REMOVABLE => VolumeType.removable,
        DRIVE_FIXED => VolumeType.fixed,
        DRIVE_REMOTE => VolumeType.network,
        DRIVE_CDROM => VolumeType.cdRom,
        DRIVE_RAMDISK => VolumeType.ramDisk,
        _ => VolumeType.unknown,
      };

      final freeAvailable = calloc<ffi.Uint64>();
      final totalBytes = calloc<ffi.Uint64>();
      final totalFree = calloc<ffi.Uint64>();
      int total = 0;
      int free = 0;
      try {
        final ok = GetDiskFreeSpaceEx(rootPtr, freeAvailable, totalBytes, totalFree);
        if (ok != 0) {
          total = totalBytes.value;
          free = totalFree.value;
        }
      } finally {
        calloc.free(freeAvailable);
        calloc.free(totalBytes);
        calloc.free(totalFree);
      }

      // A drive that couldn't be queried at all (e.g. an empty removable
      // reader) is skipped rather than shown as a confusing 0-byte volume.
      if (total == 0 && (driveType == DRIVE_REMOVABLE || driveType == DRIVE_CDROM)) {
        return null;
      }

      final label = _readVolumeLabel(rootPtr);

      return StorageVolume(
        rootPath: root,
        label: label?.isNotEmpty == true ? label : null,
        type: type,
        totalBytes: total,
        freeBytes: free,
        deviceId: root,
      );
    } finally {
      calloc.free(rootPtr);
    }
  }

  String? _readVolumeLabel(ffi.Pointer<Utf16> rootPtr) {
    final nameBuf = wsalloc(261);
    final serial = calloc<ffi.Uint32>();
    final maxComponent = calloc<ffi.Uint32>();
    final fsFlags = calloc<ffi.Uint32>();
    final fsNameBuf = wsalloc(261);
    try {
      final ok = GetVolumeInformation(
        rootPtr,
        nameBuf,
        261,
        serial,
        maxComponent,
        fsFlags,
        fsNameBuf,
        261,
      );
      if (ok == 0) return null;
      return nameBuf.toDartString();
    } finally {
      free(nameBuf);
      calloc.free(serial);
      calloc.free(maxComponent);
      calloc.free(fsFlags);
      free(fsNameBuf);
    }
  }
}
