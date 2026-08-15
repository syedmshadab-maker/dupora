import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'safe_delete_service.dart';

/// Win32 `GetLastError` codes, used only to classify a diagnostic probe
/// after a delete has already failed (see [WindowsDeleter._diagnose]) -
/// not decoded from `SHFileOperationW`'s own return value, which uses a
/// separate, legacy `DE_*` code space that isn't reliable to interpret
/// from a fixed table.
const int _errorSharingViolation = 32;
const int _errorLockViolation = 33;
const int _errorAccessDenied = 5;

/// Thrown by [WindowsDeleter.deleteFile] when the target file is open/in
/// use by another process, distinguishing it from a generic failure.
class RecycleBinLockedException implements Exception {
  RecycleBinLockedException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Thrown by [WindowsDeleter.deleteFile] when the OS reports access denied,
/// distinguishing it from a generic failure.
class RecycleBinPermissionDeniedException implements Exception {
  RecycleBinPermissionDeniedException(this.message);
  final String message;
  @override
  String toString() => message;
}

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
      opStruct.ref.fFlags =
          FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_SILENT | FOF_NOERRORUI;

      final result = SHFileOperation(opStruct);
      final aborted = opStruct.ref.fAnyOperationsAborted != 0;
      if (result == 0 && !aborted) return;

      await _diagnoseAndThrow(path, result, aborted);
    } finally {
      calloc.free(pFrom);
      calloc.free(opStruct);
    }
  }

  /// `SHFileOperationW` failed or was aborted; probe *why* using
  /// well-documented Win32 error codes (via a short-lived exclusive-open
  /// attempt) so the caller can tell a locked file and a permissions
  /// problem apart from a generic failure - required so a batch delete can
  /// report e.g. "99 succeeded, 1 locked" rather than one opaque failure
  /// count.
  Future<Never> _diagnoseAndThrow(
    String path,
    int shResult,
    bool aborted,
  ) async {
    try {
      final probe = await File(path).open(mode: FileMode.append);
      await probe.close();
    } on FileSystemException catch (e) {
      final code = e.osError?.errorCode;
      if (code == _errorSharingViolation || code == _errorLockViolation) {
        throw RecycleBinLockedException(
          'file is open/locked by another process '
          '(SHFileOperationW code 0x${shResult.toRadixString(16)})',
        );
      }
      if (code == _errorAccessDenied) {
        throw RecycleBinPermissionDeniedException(
          'access denied '
          '(SHFileOperationW code 0x${shResult.toRadixString(16)})',
        );
      }
    } catch (_) {
      // Diagnostic probe failed in some other way (e.g. the file vanished
      // between the earlier existence check and now) - fall through to the
      // generic failure below rather than reporting a misleading category.
    }
    throw StateError(
      aborted
          ? 'Recycle Bin operation was aborted'
          : 'SHFileOperationW failed with code 0x${shResult.toRadixString(16)}',
    );
  }
}
