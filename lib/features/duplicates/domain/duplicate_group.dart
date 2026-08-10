import 'package:meta/meta.dart';

import '../../scanner/domain/scanned_file.dart';

/// A set of two or more files verified as exact duplicates: same size AND
/// same full BLAKE3 digest (see Stage 3 in `duplicate_funnel.dart`). Never
/// constructed from filename, partial-hash, or metadata similarity alone.
@immutable
class DuplicateGroup {
  DuplicateGroup({required this.fullHashHex, required this.fileSize, required List<ScannedFile> files})
      : files = List.unmodifiable(files) {
    assert(files.length >= 2, 'a duplicate group must contain at least 2 files');
  }

  final String fullHashHex;
  final int fileSize;
  final List<ScannedFile> files;

  /// Bytes that would be reclaimed by keeping exactly one copy.
  int get wastedBytes => fileSize * (files.length - 1);

  int get duplicateCount => files.length - 1;
}
