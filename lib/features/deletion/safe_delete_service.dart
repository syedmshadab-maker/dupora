import 'dart:io';

import '../scanner/domain/scanned_file.dart';
import 'protected_locations.dart';
import 'safe_delete_android.dart';
import 'safe_delete_linux.dart';
import 'safe_delete_macos.dart';
import 'safe_delete_windows.dart';

enum DeleteOutcome {
  movedToTrash,
  permanentlyDeleted,
  skippedProtected,
  skippedAlreadyRequested,
  notFound,
  identityMismatch,
  failed,
}

class DeleteResult {
  const DeleteResult(this.path, this.outcome, {this.error});
  final String path;
  final DeleteOutcome outcome;
  final String? error;

  bool get succeeded =>
      outcome == DeleteOutcome.movedToTrash ||
      outcome == DeleteOutcome.permanentlyDeleted;
}

/// Low-level, per-platform delete execution. Never call this directly for
/// user-facing deletes - go through [SafeDeleteCoordinator], which adds the
/// pre-delete verification and protected-location/double-delete guards the
/// project spec requires.
abstract class PlatformDeleter {
  /// True if this platform has a real trash/recycle bin; false means
  /// deletion is permanent and the UI must warn clearly before proceeding.
  bool get hasTrash;

  Future<void> deleteFile(String path);

  factory PlatformDeleter.forPlatform() {
    if (Platform.isWindows) return WindowsDeleter();
    if (Platform.isMacOS) return MacOsDeleter();
    if (Platform.isLinux) return LinuxDeleter();
    if (Platform.isAndroid) return AndroidDeleter();
    throw UnsupportedError('No deleter for ${Platform.operatingSystem}');
  }
}

/// Enforces the project's "DELETE SAFETY" requirements around a
/// [PlatformDeleter]: existence/identity verification immediately before
/// the OS call, protected-location refusal, and de-duplication of
/// concurrent/duplicate delete requests for the same path.
class SafeDeleteCoordinator {
  SafeDeleteCoordinator({
    required this.protectedLocations,
    PlatformDeleter? deleter,
  }) : _deleter = deleter ?? PlatformDeleter.forPlatform();

  final ProtectedLocations protectedLocations;
  final PlatformDeleter _deleter;
  final Set<String> _inFlightOrDone = {};

  bool get usesTrash => _deleter.hasTrash;

  /// Deletes [file], refusing if it's the protected "keep" file (callers
  /// should already exclude it, but this is a hard backstop),
  /// double-submission of the same path, or if the file's on-disk size no
  /// longer matches what was recorded when duplicates were computed
  /// (someone modified it since the scan - deleting it now would not be
  /// deleting the file the user reviewed).
  Future<DeleteResult> delete(
    ScannedFile file, {
    ScannedFile? mustNotEqual,
  }) async {
    final path = file.path;

    if (mustNotEqual != null && mustNotEqual.path == path) {
      return DeleteResult(
        path,
        DeleteOutcome.skippedProtected,
        error: 'refused: this is the file marked to keep',
      );
    }
    if (protectedLocations.isProtected(path)) {
      return DeleteResult(path, DeleteOutcome.skippedProtected);
    }
    if (!_inFlightOrDone.add(path)) {
      return DeleteResult(path, DeleteOutcome.skippedAlreadyRequested);
    }

    try {
      final entity = File(path);
      if (!await entity.exists()) {
        return DeleteResult(path, DeleteOutcome.notFound);
      }
      final stat = await entity.stat();
      if (stat.size != file.size) {
        return DeleteResult(
          path,
          DeleteOutcome.identityMismatch,
          error:
              'size changed since scan (${stat.size} != ${file.size}); refusing to delete',
        );
      }
      // Belt-and-braces beyond the size check: if some other file was
      // deleted and a *different* file of the coincidentally-same size
      // was later created at this exact path (e.g. an app re-downloading
      // to the same filename), the size check alone wouldn't catch it -
      // but a fresh write essentially always changes mtime too, even when
      // the byte count happens to match. A full re-hash would be the only
      // airtight check; this is the cheap version of the same guarantee
      // the persistent cache already relies on for validity (size + mtime
      // - see HashCacheRepository).
      if (stat.modified != file.modifiedAt) {
        return DeleteResult(
          path,
          DeleteOutcome.identityMismatch,
          error:
              'modified time changed since scan (${stat.modified} != ${file.modifiedAt}); refusing to delete',
        );
      }

      await _deleter.deleteFile(path);
      return DeleteResult(
        path,
        _deleter.hasTrash
            ? DeleteOutcome.movedToTrash
            : DeleteOutcome.permanentlyDeleted,
      );
    } catch (e) {
      _inFlightOrDone.remove(path); // allow a retry after a genuine failure
      return DeleteResult(path, DeleteOutcome.failed, error: e.toString());
    }
  }

  Future<List<DeleteResult>> deleteAll(
    List<ScannedFile> files, {
    ScannedFile? mustNotEqual,
  }) async {
    final results = <DeleteResult>[];
    for (final file in files) {
      results.add(await delete(file, mustNotEqual: mustNotEqual));
    }
    return results;
  }
}
