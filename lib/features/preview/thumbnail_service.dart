import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum PreviewCategory { image, video, audio, document, pdf, archive, other }

PreviewCategory categoryForExtension(String extension) {
  final ext = extension.toLowerCase();
  const images = {'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'heic', 'tiff'};
  const videos = {'mp4', 'mov', 'avi', 'mkv', 'webm', 'flv', 'wmv'};
  const audio = {'mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a'};
  const documents = {
    'doc',
    'docx',
    'xls',
    'xlsx',
    'ppt',
    'pptx',
    'txt',
    'rtf',
    'odt',
  };
  const archives = {'zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz'};
  if (images.contains(ext)) return PreviewCategory.image;
  if (videos.contains(ext)) return PreviewCategory.video;
  if (audio.contains(ext)) return PreviewCategory.audio;
  if (ext == 'pdf') return PreviewCategory.pdf;
  if (documents.contains(ext)) return PreviewCategory.document;
  if (archives.contains(ext)) return PreviewCategory.archive;
  return PreviewCategory.other;
}

/// Generates and caches downscaled image thumbnails.
///
/// Scope note: full-fidelity video-frame and PDF-page thumbnails need a
/// decoder this project doesn't currently bundle (ffmpeg / pdfium), so
/// those categories get a static file-type icon instead of a rendered
/// preview (see [categoryForExtension] and the results-screen tile
/// widget). Image thumbnails are real, decoded via the pure-Dart `image`
/// package so behavior is identical on every platform.
class ThumbnailService {
  ThumbnailService({int memoryCacheCapacity = 200})
    : _memoryCacheCapacity = memoryCacheCapacity;

  final int _memoryCacheCapacity;
  final Map<String, Uint8List> _memoryCache = {};
  final List<String> _memoryCacheOrder = [];
  Directory? _diskCacheDir;

  static const int _thumbnailEdge = 256;

  Future<Directory> _cacheDir() async {
    final existing = _diskCacheDir;
    if (existing != null) return existing;
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'thumbnails'));
    await dir.create(recursive: true);
    _diskCacheDir = dir;
    return dir;
  }

  String _cacheKeyFor(String path, DateTime modifiedAt) {
    final digest = sha1.convert(
      '$path|${modifiedAt.millisecondsSinceEpoch}'.codeUnits,
    );
    return digest.toString();
  }

  /// Returns PNG-encoded thumbnail bytes, or null if [path] isn't an image
  /// or decoding failed (corrupt/unsupported file - never throws, so a
  /// grid of thousands of files can't crash on one bad image).
  Future<Uint8List?> getThumbnail(String path, DateTime modifiedAt) async {
    final key = _cacheKeyFor(path, modifiedAt);

    final cached = _memoryCache[key];
    if (cached != null) return cached;

    try {
      final cacheDir = await _cacheDir();
      final cacheFile = File(p.join(cacheDir.path, '$key.png'));
      if (await cacheFile.exists()) {
        final bytes = await cacheFile.readAsBytes();
        _storeInMemory(key, bytes);
        return bytes;
      }

      final bytes = await _decode(path);
      if (bytes == null) return null;
      await cacheFile.writeAsBytes(bytes);
      _storeInMemory(key, bytes);
      return bytes;
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _decode(String path) async {
    final raw = await File(path).readAsBytes();
    final decoded = img.decodeImage(raw);
    if (decoded == null) return null;
    final resized = img.copyResize(
      decoded,
      width: decoded.width >= decoded.height ? _thumbnailEdge : null,
      height: decoded.height > decoded.width ? _thumbnailEdge : null,
    );
    return Uint8List.fromList(img.encodePng(resized));
  }

  void _storeInMemory(String key, Uint8List bytes) {
    if (_memoryCache.containsKey(key)) {
      _memoryCacheOrder.remove(key);
    } else if (_memoryCache.length >= _memoryCacheCapacity) {
      final oldest = _memoryCacheOrder.removeAt(0);
      _memoryCache.remove(oldest);
    }
    _memoryCache[key] = bytes;
    _memoryCacheOrder.add(key);
  }

  Future<void> clearDiskCache() async {
    final dir = await _cacheDir();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
      await dir.create(recursive: true);
    }
    _memoryCache.clear();
    _memoryCacheOrder.clear();
  }
}

/// Decodes cached PNG bytes into a `dart:ui.Image` for painting. Kept
/// separate from [ThumbnailService] so the byte-cache logic stays testable
/// without a Flutter binding.
Future<ui.Image> decodeUiImage(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}
