import 'package:flutter/services.dart';

import '../domain/storage_volume.dart';

/// Android storage is fundamentally SAF-tree-based rather than
/// root-volume-based (see project spec's "ANDROID SAF" section), so this
/// intentionally does not implement the shared `StorageDetector` interface:
/// callers need the SAF tree URIs, not just root paths, to actually browse
/// or hash anything. [listVolumes] is informational (for the storage-usage
/// display on the Home screen); real folder selection goes through
/// `SafBridge.pickDirectory()`.
///
/// NOTE: device-unverified, see `SafChannel.kt` / BUILD.md.
class AndroidStorageDetector {
  static const MethodChannel _channel = MethodChannel('com.dupora/storage');

  Future<List<StorageVolume>> listVolumes() async {
    final result = await _channel.invokeListMethod<Map<Object?, Object?>>('listVolumes');
    if (result == null) return const [];
    return result.map((m) {
      final isRemovable = m['isRemovable'] as bool? ?? false;
      return StorageVolume(
        rootPath: m['path'] as String? ?? '',
        label: m['label'] as String?,
        type: isRemovable ? VolumeType.removable : VolumeType.fixed,
        totalBytes: (m['totalBytes'] as num?)?.toInt() ?? 0,
        freeBytes: (m['freeBytes'] as num?)?.toInt() ?? 0,
      );
    }).toList();
  }
}
