import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../../../core/native/hash_engine.dart';
import '../../../core/utils/file_attributes.dart';
import '../domain/scanned_file.dart';

class DiscoveryOptions {
  const DiscoveryOptions({
    required this.roots,
    this.scanHiddenFiles = false,
    this.scanSystemFiles = false,
    this.followSymlinks = false,
  });

  final List<String> roots;
  final bool scanHiddenFiles;
  final bool scanSystemFiles;
  final bool followSymlinks;
}

/// One batch of Stage 0 results, sent periodically over the isolate's
/// [SendPort] rather than one message per file (avoiding both excessive IPC
/// overhead on huge trees and a single giant end-of-scan message).
class DiscoveryBatch {
  const DiscoveryBatch(this.files, this.errors);
  final List<ScannedFile> files;
  final List<ScanError> errors;
}

class DiscoveryDone {
  const DiscoveryDone({required this.totalFiles, required this.totalBytes, required this.cancelled});
  final int totalFiles;
  final int totalBytes;
  final bool cancelled;
}

const int _batchSize = 500;

/// Runs Stage 0 (file discovery) on a dedicated isolate so enumerating
/// millions of directory entries never blocks the UI isolate. Returns the
/// isolate's raw [ReceivePort] directly (it implements `Stream`); the
/// caller listens for [DiscoveryBatch] messages followed by one final
/// [DiscoveryDone], and **must call `.close()` on the returned port** once
/// it observes [DiscoveryDone] - a `ReceivePort` never completes its stream
/// on its own, so an `await for` loop over it would otherwise hang forever
/// even after the isolate has finished and sent its last message.
ReceivePort runFileDiscovery(DiscoveryOptions options, CancelSignal cancel) {
  final receivePort = ReceivePort();
  final init = _DiscoveryInit(
    roots: options.roots,
    scanHiddenFiles: options.scanHiddenFiles,
    scanSystemFiles: options.scanSystemFiles,
    followSymlinks: options.followSymlinks,
    cancelAddress: cancel.rawAddress,
    sendPort: receivePort.sendPort,
  );
  Isolate.spawn(_discoveryIsolateMain, init, debugName: 'dupora-discovery');
  return receivePort;
}

class _DiscoveryInit {
  _DiscoveryInit({
    required this.roots,
    required this.scanHiddenFiles,
    required this.scanSystemFiles,
    required this.followSymlinks,
    required this.cancelAddress,
    required this.sendPort,
  });

  final List<String> roots;
  final bool scanHiddenFiles;
  final bool scanSystemFiles;
  final bool followSymlinks;
  final int cancelAddress;
  final SendPort sendPort;
}

void _discoveryIsolateMain(_DiscoveryInit init) {
  final cancel = CancelSignal.fromRawAddress(init.cancelAddress);
  final visitedRealPaths = <String>{};
  final pendingFiles = <ScannedFile>[];
  final pendingErrors = <ScanError>[];
  var totalFiles = 0;
  var totalBytes = 0;
  var cancelled = false;

  void flush() {
    if (pendingFiles.isEmpty && pendingErrors.isEmpty) return;
    init.sendPort.send(DiscoveryBatch(List.of(pendingFiles), List.of(pendingErrors)));
    pendingFiles.clear();
    pendingErrors.clear();
  }

  void visitDirectory(String dirPath) {
    if (cancelled) return;
    if (cancel.isCancelled) {
      cancelled = true;
      return;
    }

    List<FileSystemEntity> entries;
    try {
      entries = Directory(dirPath).listSync(followLinks: false);
    } on FileSystemException catch (e) {
      pendingErrors.add(ScanError(path: dirPath, message: e.message, stage: 'discovery'));
      return;
    } catch (e) {
      pendingErrors.add(ScanError(path: dirPath, message: e.toString(), stage: 'discovery'));
      return;
    }

    for (final entity in entries) {
      if (cancel.isCancelled) {
        cancelled = true;
        break;
      }

      final name = p.basename(entity.path);
      FileSystemEntityType type;
      try {
        type = FileSystemEntity.typeSync(entity.path, followLinks: false);
      } catch (e) {
        pendingErrors.add(ScanError(path: entity.path, message: e.toString(), stage: 'discovery'));
        continue;
      }

      final isLink = type == FileSystemEntityType.link;
      final attrs = FileAttributesProbe.probe(entity.path, name);
      if (attrs.isHidden && !init.scanHiddenFiles) continue;
      if (attrs.isSystem && !init.scanSystemFiles) continue;

      if (isLink) {
        if (!init.followSymlinks) continue; // Default: never follow symlinks.
        String? real;
        try {
          real = Directory(entity.path).resolveSymbolicLinksSync();
        } catch (_) {
          // Broken symlink or a symlink to a file; fall through to a
          // regular stat below, which will classify it correctly.
        }
        if (real != null) {
          if (!visitedRealPaths.add(real)) continue; // Cycle guard.
          final targetType = FileSystemEntity.typeSync(real);
          if (targetType == FileSystemEntityType.directory) {
            visitDirectory(real);
            continue;
          }
        }
      }

      FileStat stat;
      try {
        stat = entity.statSync();
      } catch (e) {
        pendingErrors.add(ScanError(path: entity.path, message: e.toString(), stage: 'discovery'));
        continue;
      }

      if (stat.type == FileSystemEntityType.directory) {
        visitDirectory(entity.path);
      } else if (stat.type == FileSystemEntityType.file) {
        pendingFiles.add(
          ScannedFile(
            path: entity.path,
            name: name,
            extension: p.extension(name).replaceFirst('.', '').toLowerCase(),
            size: stat.size,
            modifiedAt: stat.modified,
            isHidden: attrs.isHidden,
            isSystem: attrs.isSystem,
          ),
        );
        totalFiles++;
        totalBytes += stat.size;
        if (pendingFiles.length >= _batchSize) flush();
      }
    }
  }

  for (final root in init.roots) {
    if (cancelled) break;
    final type = FileSystemEntity.typeSync(root, followLinks: true);
    if (type == FileSystemEntityType.directory) {
      visitDirectory(root);
    } else if (type == FileSystemEntityType.file) {
      try {
        final stat = FileStat.statSync(root);
        final name = p.basename(root);
        final attrs = FileAttributesProbe.probe(root, name);
        pendingFiles.add(
          ScannedFile(
            path: root,
            name: name,
            extension: p.extension(name).replaceFirst('.', '').toLowerCase(),
            size: stat.size,
            modifiedAt: stat.modified,
            isHidden: attrs.isHidden,
            isSystem: attrs.isSystem,
          ),
        );
        totalFiles++;
        totalBytes += stat.size;
      } catch (e) {
        pendingErrors.add(ScanError(path: root, message: e.toString(), stage: 'discovery'));
      }
    } else {
      pendingErrors.add(ScanError(path: root, message: 'not found or inaccessible', stage: 'discovery'));
    }
  }

  flush();
  init.sendPort.send(DiscoveryDone(totalFiles: totalFiles, totalBytes: totalBytes, cancelled: cancelled));
}
