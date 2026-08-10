import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'safe_delete_service.dart';

/// Moves files to the Windows Recycle Bin via `SHFileOperationW`
/// (`FO_DELETE` + `FOF_ALLOWUNDO`), the standard, undo-capable Win32 delete
/// API - never a raw `DeleteFile`, which is permanent.
class WindowsDeleter implements PlatformDeleter {
  @override
  bool get hasTrash => true;

  @override
  Future<void> deleteFile(String path) async {
    // pFrom must be a list of null-terminated strings, itself terminated by
    // an extra trailing null (a "double-null-terminated" buffer).
    final combined = '$path\x00\x00';
    final pFrom = combined.toNativeUtf16();
    final opStruct = calloc<SHFILEOPSTRUCT>();
    try {
      opStruct.ref.hwnd = 0;
      opStruct.ref.wFunc = FO_DELETE;
      opStruct.ref.pFrom = pFrom;
      opStruct.ref.pTo = ffi.nullptr;
      opStruct.ref.fFlags = FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_SILENT | FOF_NOERRORUI;

      final result = SHFileOperation(opStruct);
      if (result != 0) {
        throw StateError('SHFileOperationW failed with code 0x${result.toRadixString(16)}');
      }
      if (opStruct.ref.fAnyOperationsAborted != 0) {
        throw StateError('Recycle Bin operation was aborted');
      }
    } finally {
      calloc.free(pFrom);
      calloc.free(opStruct);
    }
  }
}
