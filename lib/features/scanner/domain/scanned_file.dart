import 'package:meta/meta.dart';

/// A file discovered during Stage 0, carrying everything later stages need
/// without ever needing to re-stat the filesystem.
@immutable
class ScannedFile {
  const ScannedFile({
    required this.path,
    required this.name,
    required this.extension,
    required this.size,
    required this.modifiedAt,
    this.deviceId,
    this.isHidden = false,
    this.isSystem = false,
  });

  final String path;
  final String name;
  final String extension;
  final int size;
  final DateTime modifiedAt;

  /// Filesystem/volume identifier, where the platform exposes one. Used to
  /// disambiguate identical (path, mtime) tuples across distinct volumes
  /// mounted at overlapping points, and to detect when a cached hash's
  /// originating device has been swapped out from under the same path.
  final String? deviceId;

  final bool isHidden;
  final bool isSystem;

  ScannedFile copyWith({int? size, DateTime? modifiedAt}) {
    return ScannedFile(
      path: path,
      name: name,
      extension: extension,
      size: size ?? this.size,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      deviceId: deviceId,
      isHidden: isHidden,
      isSystem: isSystem,
    );
  }

  @override
  bool operator ==(Object other) => other is ScannedFile && other.path == path;

  @override
  int get hashCode => path.hashCode;

  @override
  String toString() => 'ScannedFile($path, $size bytes)';
}

/// A file the scanner could not fully process, kept separate from
/// [ScannedFile] results so one bad file never aborts a scan and the user
/// can inspect failures afterward.
@immutable
class ScanError {
  const ScanError({
    required this.path,
    required this.message,
    required this.stage,
  });

  final String path;
  final String message;
  final String stage;

  @override
  String toString() => '[$stage] $path: $message';
}
