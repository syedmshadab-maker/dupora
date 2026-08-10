import 'package:dupora/features/deletion/safe_delete_linux.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LinuxDeleter.buildTrashInfo', () {
    test('formats per the freedesktop.org Trash spec', () {
      final info = LinuxDeleter.buildTrashInfo(
        originalPath: '/home/user/Documents/report.pdf',
        deletionDate: DateTime(2024, 3, 5, 9, 7, 2),
      );
      expect(info, '[Trash Info]\nPath=/home/user/Documents/report.pdf\nDeletionDate=2024-03-05T09:07:02\n');
    });

    test('percent-encodes special characters in the path', () {
      final info = LinuxDeleter.buildTrashInfo(
        originalPath: '/home/user/My Documents/a b.txt',
        deletionDate: DateTime(2024, 1, 1),
      );
      expect(info, contains('Path=/home/user/My%20Documents/a%20b.txt'));
    });

    test('zero-pads single-digit date/time components', () {
      final info = LinuxDeleter.buildTrashInfo(
        originalPath: '/f',
        deletionDate: DateTime(2024, 1, 2, 3, 4, 5),
      );
      expect(info, contains('DeletionDate=2024-01-02T03:04:05'));
    });
  });
}
