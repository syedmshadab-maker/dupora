import 'dart:io';

import 'package:dupora/features/preview/thumbnail_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// [ThumbnailService] resolves its on-disk cache directory via
/// `path_provider`, which needs a real platform channel unavailable in a
/// plain `flutter test`. Fake it out with a real temp directory rather
/// than mocking [ThumbnailService] itself, so the disk-cache read/write
/// path under test is real.
class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.supportPath);
  final String supportPath;

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory supportDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dupora_thumb_test_');
    supportDir = await Directory.systemTemp.createTemp('dupora_thumb_support_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(supportDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
    if (await supportDir.exists()) await supportDir.delete(recursive: true);
  });

  Future<String> writeRealPng(String name, {int size = 32}) async {
    final image = img.Image(width: size, height: size);
    img.fill(image, color: img.ColorRgb8(200, 100, 50));
    final bytes = img.encodePng(image);
    final path = '${tempDir.path}${Platform.pathSeparator}$name';
    await File(path).writeAsBytes(bytes);
    return path;
  }

  test('produces a decoded thumbnail for a real image file', () async {
    final service = ThumbnailService();
    final path = await writeRealPng('real.png');

    final bytes = await service.getThumbnail(path, DateTime(2024, 1, 1));

    expect(bytes, isNotNull);
    final decoded = img.decodePng(bytes!);
    expect(decoded, isNotNull);
    expect(decoded!.width, lessThanOrEqualTo(256));
    expect(decoded.height, lessThanOrEqualTo(256));
  });

  test('a corrupt/non-image file never throws - returns null instead '
      '(a bad file among thousands must not crash the results grid)', () async {
    final service = ThumbnailService();
    final path = '${tempDir.path}${Platform.pathSeparator}corrupt.png';
    await File(path).writeAsBytes([0x00, 0x01, 0x02, 0x03, 0xFF, 0xFE]);

    final bytes = await service.getThumbnail(path, DateTime(2024, 1, 1));

    expect(bytes, isNull);
  });

  test('a missing file never throws - returns null instead', () async {
    final service = ThumbnailService();
    final path = '${tempDir.path}${Platform.pathSeparator}does_not_exist.png';

    final bytes = await service.getThumbnail(path, DateTime(2024, 1, 1));

    expect(bytes, isNull);
  });

  test(
    'a request cancelled before the decode finishes returns null and does '
    'not pollute the memory cache for a later, non-cancelled request',
    () async {
      final service = ThumbnailService();
      final path = await writeRealPng('cancel_me.png');
      final modifiedAt = DateTime(2024, 1, 1);

      final token = ThumbnailCancelToken();
      token.cancel(); // already cancelled before the request even starts

      final firstResult = await service.getThumbnail(
        path,
        modifiedAt,
        cancelToken: token,
      );
      expect(firstResult, isNull);

      // A fresh, non-cancelled request for the exact same file must still
      // succeed normally - cancellation of one caller must not corrupt
      // shared state for anyone else.
      final secondResult = await service.getThumbnail(path, modifiedAt);
      expect(secondResult, isNotNull);
    },
  );

  test(
    'the disk cache is reused on a second request for the same file',
    () async {
      final service = ThumbnailService();
      final path = await writeRealPng('cached.png');
      final modifiedAt = DateTime(2024, 1, 1);

      final first = await service.getThumbnail(path, modifiedAt);
      // A fresh service instance (empty in-memory cache) must still find
      // the same result via the on-disk cache.
      final service2 = ThumbnailService();
      final second = await service2.getThumbnail(path, modifiedAt);

      expect(first, isNotNull);
      expect(second, equals(first));
    },
  );

  test(
    'requesting far more distinct thumbnails than the memory-cache '
    'capacity never throws or degrades correctness (bounded memory)',
    () async {
      final service = ThumbnailService(memoryCacheCapacity: 2);
      final paths = <String>[];
      for (var i = 0; i < 20; i++) {
        paths.add(await writeRealPng('img$i.png'));
      }

      for (final path in paths) {
        final bytes = await service.getThumbnail(path, DateTime(2024, 1, 1));
        expect(bytes, isNotNull);
      }
    },
  );
}
