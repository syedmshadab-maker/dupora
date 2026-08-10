import '../storage/data/saf_bridge.dart';
import 'safe_delete_service.dart';

/// Android has no universal SAF "trash" - only `DocumentsContract.deleteDocument`,
/// which is permanent. The UI must warn clearly before calling this (see
/// project spec's "If trash is unavailable: Warn clearly before permanent
/// deletion").
///
/// For Android-sourced scans, [ScannedFile.path] holds the SAF document
/// URI string (there is generally no accessible raw filesystem path for
/// SAF-tree content), so [deleteFile] treats its `path` argument as a
/// `content://` URI, not a filesystem path.
///
/// NOTE: device-unverified, see `SafChannel.kt` / BUILD.md.
class AndroidDeleter implements PlatformDeleter {
  AndroidDeleter({SafBridge? safBridge}) : _saf = safBridge ?? SafBridge();

  final SafBridge _saf;

  @override
  bool get hasTrash => false;

  @override
  Future<void> deleteFile(String path) async {
    final ok = await _saf.deleteDocument(path);
    if (!ok) {
      throw StateError('DocumentsContract.deleteDocument failed for $path');
    }
  }
}
