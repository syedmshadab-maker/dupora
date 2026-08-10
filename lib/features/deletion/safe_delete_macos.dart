import 'package:flutter/services.dart';

import 'safe_delete_service.dart';

/// Delegates to `FileManager.trashItem(at:resultingItemURL:)` via a
/// MethodChannel to native Swift (`macos/Runner/TrashChannel.swift`) - the
/// standard macOS API for a real, undo-capable Trash move.
///
/// NOTE: device/host-unverified - this repository was built on Windows, so
/// this path has not been exercised on real macOS hardware. See BUILD.md.
class MacOsDeleter implements PlatformDeleter {
  static const MethodChannel _channel = MethodChannel('com.dupora/trash');

  @override
  bool get hasTrash => true;

  @override
  Future<void> deleteFile(String path) async {
    final ok = await _channel.invokeMethod<bool>('trash', {'path': path});
    if (ok != true) {
      throw StateError('FileManager.trashItem failed for $path');
    }
  }
}
