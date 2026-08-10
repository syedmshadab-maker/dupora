import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart' as win32;

/// Hidden/system detection. On Windows this reads real file attribute bits;
/// elsewhere "hidden" follows the Unix dotfile convention and "system" has
/// no OS-level concept, so it's always false.
class FileAttributesProbe {
  static const int _fileAttributeHidden = 0x2;
  static const int _fileAttributeSystem = 0x4;
  static const int _invalidFileAttributes = 0xFFFFFFFF;

  static ({bool isHidden, bool isSystem}) probe(String path, String name) {
    if (Platform.isWindows) {
      final ptr = path.toNativeUtf16();
      try {
        final attrs = win32.GetFileAttributes(ptr);
        if (attrs == _invalidFileAttributes) {
          return (isHidden: name.startsWith('.'), isSystem: false);
        }
        return (
          isHidden: (attrs & _fileAttributeHidden) != 0,
          isSystem: (attrs & _fileAttributeSystem) != 0,
        );
      } finally {
        calloc.free(ptr);
      }
    }
    return (isHidden: name.startsWith('.'), isSystem: false);
  }
}
