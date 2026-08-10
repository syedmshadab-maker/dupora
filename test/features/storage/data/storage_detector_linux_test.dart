import 'package:dupora/features/storage/data/storage_detector_linux.dart';
import 'package:dupora/features/storage/domain/storage_volume.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LinuxStorageDetector.parseMounts', () {
    const sampleMounts = '''
proc /proc proc rw,nosuid,nodev,noexec,relatime 0 0
sysfs /sys sysfs rw,nosuid,nodev,noexec,relatime 0 0
/dev/sda2 / ext4 rw,relatime 0 0
/dev/sda1 /boot/efi vfat rw,relatime 0 0
tmpfs /run tmpfs rw,nosuid,nodev 0 0
/dev/sdb1 /media/user/Backup\\040Drive ext4 rw,nosuid,nodev,relatime 0 0
//server/share /mnt/network cifs rw,relatime 0 0
overlay / overlay rw 0 0
''';

    test('excludes virtual filesystems', () async {
      final volumes = await LinuxStorageDetector.parseMounts(
        sampleMounts,
        statFn: (path) async => (100000, 50000),
      );
      expect(volumes.any((v) => v.rootPath == '/proc'), isFalse);
      expect(volumes.any((v) => v.rootPath == '/run'), isFalse);
      expect(volumes.any((v) => v.deviceId == 'overlay'), isFalse);
    });

    test('excludes /boot/efi', () async {
      final volumes = await LinuxStorageDetector.parseMounts(
        sampleMounts,
        statFn: (path) async => (100000, 50000),
      );
      expect(volumes.any((v) => v.rootPath == '/boot/efi'), isFalse);
    });

    test('includes the root filesystem as fixed', () async {
      final volumes = await LinuxStorageDetector.parseMounts(
        sampleMounts,
        statFn: (path) async => (100000, 50000),
      );
      final root = volumes.firstWhere((v) => v.rootPath == '/');
      expect(root.type, VolumeType.fixed);
      expect(root.deviceId, '/dev/sda2');
    });

    test('unescapes octal sequences in mount points (e.g. spaces)', () async {
      final volumes = await LinuxStorageDetector.parseMounts(
        sampleMounts,
        statFn: (path) async => (100000, 50000),
      );
      expect(volumes.any((v) => v.rootPath == '/media/user/Backup Drive'), isTrue);
    });

    test('classifies /media mounts as removable', () async {
      final volumes = await LinuxStorageDetector.parseMounts(
        sampleMounts,
        statFn: (path) async => (100000, 50000),
      );
      final removable = volumes.firstWhere((v) => v.rootPath == '/media/user/Backup Drive');
      expect(removable.type, VolumeType.removable);
    });

    test('includes network shares', () async {
      final volumes = await LinuxStorageDetector.parseMounts(
        sampleMounts,
        statFn: (path) async => (100000, 50000),
      );
      expect(volumes.any((v) => v.rootPath == '/mnt/network'), isTrue);
    });

    test('drops a mount point when stat lookup fails', () async {
      final volumes = await LinuxStorageDetector.parseMounts(
        sampleMounts,
        statFn: (path) async => path == '/' ? null : (100000, 50000),
      );
      expect(volumes.any((v) => v.rootPath == '/'), isFalse);
    });
  });
}
