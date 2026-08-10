import 'package:flutter/services.dart';

import '../../../core/native/hash_engine.dart';
import '../../../core/native/status_code.dart';

class SafDocument {
  const SafDocument({
    required this.documentId,
    required this.documentUri,
    required this.name,
    required this.mimeType,
    required this.isDirectory,
    required this.size,
    required this.lastModified,
  });

  final String documentId;
  final String documentUri;
  final String name;
  final String? mimeType;
  final bool isDirectory;
  final int size;
  final DateTime lastModified;

  factory SafDocument.fromMap(Map<Object?, Object?> map) {
    return SafDocument(
      documentId: map['documentId'] as String,
      documentUri: map['documentUri'] as String,
      name: map['name'] as String? ?? '',
      mimeType: map['mimeType'] as String?,
      isDirectory: map['isDirectory'] as bool? ?? false,
      size: (map['size'] as num?)?.toInt() ?? 0,
      lastModified: DateTime.fromMillisecondsSinceEpoch(
        (map['lastModified'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}

/// Dart-side bridge to `android/.../SafChannel.kt`. See that file for the
/// device-unverified caveat - this class is written against the documented
/// MethodChannel contract but has not been exercised on real hardware.
class SafBridge {
  static const MethodChannel _channel = MethodChannel('com.dupora/saf');
  static const int _chunkSize = 256 * 1024;

  Future<({String treeUri, String displayName})?> pickDirectory() async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'pickDirectory',
    );
    if (result == null) return null;
    return (
      treeUri: result['treeUri'] as String,
      displayName: result['displayName'] as String,
    );
  }

  Future<List<String>> listPersistedTrees() async {
    final result = await _channel.invokeListMethod<Map<Object?, Object?>>(
      'listPersistedTrees',
    );
    return result?.map((m) => m['treeUri'] as String).toList() ?? const [];
  }

  Future<void> releaseTree(String treeUri) {
    return _channel.invokeMethod('releaseTree', {'treeUri': treeUri});
  }

  Future<List<SafDocument>> listChildren(
    String treeUri, {
    String? parentDocumentId,
  }) async {
    final result = await _channel.invokeListMethod<Map<Object?, Object?>>(
      'listChildren',
      {'treeUri': treeUri, 'parentDocumentId': parentDocumentId},
    );
    return result?.map(SafDocument.fromMap).toList() ?? const [];
  }

  Future<bool> deleteDocument(String documentUri) async {
    final result = await _channel.invokeMethod<bool>('deleteDocument', {
      'documentUri': documentUri,
    });
    return result ?? false;
  }

  /// Streams a SAF document's bytes through the platform channel and feeds
  /// them into the native Rust BLAKE3 engine via [IncrementalHasher], so
  /// the hash computation itself still happens in Rust even though the
  /// bytes originate from Android's `ContentResolver` rather than a path
  /// Rust could open directly.
  Future<HashOutcome> hashDocument(
    String documentUri, {
    void Function(int bytesProcessed)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final handle = await _channel.invokeMethod<int>('openStream', {
      'documentUri': documentUri,
    });
    if (handle == null) {
      throw StateError('Failed to open SAF stream for $documentUri');
    }
    final hasher = IncrementalHasher();
    var processed = 0;
    try {
      while (true) {
        if (isCancelled?.call() ?? false) {
          hasher.abort();
          return HashOutcome(NativeStatus.cancelled, Uint8List(0));
        }
        final chunk = await _channel.invokeMethod<Uint8List>('readChunk', {
          'handle': handle,
          'size': _chunkSize,
        });
        if (chunk == null || chunk.isEmpty) break;
        hasher.update(chunk);
        processed += chunk.length;
        onProgress?.call(processed);
      }
      return hasher.finalizeHash();
    } finally {
      await _channel.invokeMethod('closeStream', {'handle': handle});
    }
  }
}
