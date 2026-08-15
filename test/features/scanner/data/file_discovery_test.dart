@Tags(['integration'])
library;

import 'dart:io';

import 'package:dupora/core/native/hash_engine.dart';
import 'package:dupora/features/scanner/data/file_discovery.dart';
import 'package:dupora/features/scanner/domain/scanned_file.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs Stage 0 discovery to completion and returns every file it found,
/// closing the [ReceivePort] once `DiscoveryDone` arrives (required - see
/// [runFileDiscovery]'s doc, a `ReceivePort` never completes on its own).
Future<List<ScannedFile>> discoverAll(DiscoveryOptions options) async {
  final cancel = CancelSignal.create();
  final port = runFileDiscovery(options, cancel);
  final files = <ScannedFile>[];
  await for (final event in port) {
    if (event is DiscoveryBatch) {
      files.addAll(event.files);
    } else if (event is DiscoveryDone) {
      break;
    }
  }
  port.close();
  cancel.dispose();
  return files;
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dupora_discovery_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('a directory junction inside the scanned root is not followed by '
      'default (followSymlinks=false) - a scan must not silently escape the '
      'selected root through a junction/reparse point', () async {
    if (!Platform.isWindows) return;

    final outside = Directory('${tempDir.path}${Platform.pathSeparator}outside')
      ..createSync();
    await File(
      '${outside.path}${Platform.pathSeparator}should_not_be_seen.txt',
    ).writeAsString('secret outside the scanned root');

    final root = Directory('${tempDir.path}${Platform.pathSeparator}root')
      ..createSync();
    await File(
      '${root.path}${Platform.pathSeparator}normal.txt',
    ).writeAsString('inside the scanned root');

    final junctionPath = '${root.path}${Platform.pathSeparator}escape_link';
    final mklink = await Process.run('cmd', [
      '/c',
      'mklink',
      '/J',
      junctionPath,
      outside.path,
    ]);
    if (mklink.exitCode != 0) {
      // Junction creation itself is unsupported/blocked in this
      // environment (e.g. no junction privilege) - nothing to verify.
      return;
    }

    final files = await discoverAll(DiscoveryOptions(roots: [root.path]));

    final names = files.map((f) => f.name).toList();
    expect(names, contains('normal.txt'));
    expect(
      names,
      isNot(contains('should_not_be_seen.txt')),
      reason:
          'discovery followed a junction by default and escaped the '
          'scanned root',
    );
  });

  test('a directory junction is followed when followSymlinks is explicitly '
      'enabled (opt-in escape, not a default)', () async {
    if (!Platform.isWindows) return;

    final outside = Directory(
      '${tempDir.path}${Platform.pathSeparator}outside2',
    )..createSync();
    await File(
      '${outside.path}${Platform.pathSeparator}visible_when_opted_in.txt',
    ).writeAsString('content');

    final root = Directory('${tempDir.path}${Platform.pathSeparator}root2')
      ..createSync();

    final junctionPath = '${root.path}${Platform.pathSeparator}link';
    final mklink = await Process.run('cmd', [
      '/c',
      'mklink',
      '/J',
      junctionPath,
      outside.path,
    ]);
    if (mklink.exitCode != 0) return;

    final files = await discoverAll(
      DiscoveryOptions(roots: [root.path], followSymlinks: true),
    );

    expect(files.map((f) => f.name), contains('visible_when_opted_in.txt'));
  });
}
