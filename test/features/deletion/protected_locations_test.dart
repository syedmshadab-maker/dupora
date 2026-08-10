import 'dart:io';

import 'package:dupora/features/deletion/protected_locations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProtectedLocations', () {
    test('protects default OS roots', () {
      final locations = ProtectedLocations();
      if (Platform.isWindows) {
        expect(locations.isProtected(r'C:\Windows\System32\kernel32.dll'), isTrue);
        expect(locations.isProtected(r'C:\Users\me\Documents\report.docx'), isFalse);
      }
    });

    test('a user-added directory protects everything nested under it', () {
      final locations = ProtectedLocations(userDefined: [r'C:\MyVault']);
      expect(locations.isProtected(r'C:\MyVault\secret.txt'), isTrue);
      expect(locations.isProtected(r'C:\MyVault\nested\deep\file.txt'), isTrue);
      expect(locations.isProtected(r'C:\MyVaultDecoy\file.txt'), isFalse);
    });

    test('add/remove mutate the protected set', () {
      final locations = ProtectedLocations(userDefined: const []);
      expect(locations.isProtected(r'C:\Temp\a.txt'), isFalse);
      locations.add(r'C:\Temp');
      expect(locations.isProtected(r'C:\Temp\a.txt'), isTrue);
      locations.remove(r'C:\Temp');
      expect(locations.isProtected(r'C:\Temp\a.txt'), isFalse);
    });

    test('is not so aggressive that ordinary user folders are protected', () {
      final locations = ProtectedLocations();
      if (Platform.isWindows) {
        expect(locations.isProtected(r'D:\Photos\vacation.jpg'), isFalse);
        expect(locations.isProtected(r'C:\Users\me\Downloads\file.zip'), isFalse);
      }
    });
  });
}
