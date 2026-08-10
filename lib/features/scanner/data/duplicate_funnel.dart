import '../../duplicates/domain/duplicate_group.dart';
import '../domain/scanned_file.dart';

/// Pure, native-call-free grouping logic for the multi-stage duplicate
/// funnel. Kept separate from [ScanEngine] orchestration so it's trivially
/// unit-testable without isolates, FFI, or a database.

/// Stage 1: group by exact file size. Files with a size no other file
/// shares are dropped here - they can never be duplicates, so they must
/// never reach Stage 2/3 hashing.
Map<int, List<ScannedFile>> groupBySizeCandidates(List<ScannedFile> files) {
  final bySize = <int, List<ScannedFile>>{};
  for (final f in files) {
    bySize.putIfAbsent(f.size, () => []).add(f);
  }
  bySize.removeWhere((_, group) => group.length < 2);
  return bySize;
}

/// Stage 2: within a size group, sub-group by partial fingerprint hex.
/// A different partial fingerprint proves the files differ (it covers real
/// file bytes), so those sub-groups are dropped - this is a correctness
/// deduction, not a heuristic: differing bytes anywhere in the head/tail
/// windows means differing full content.
Map<String, List<ScannedFile>> groupByPartialCandidates(
  List<ScannedFile> sameSizeFiles,
  String Function(ScannedFile) partialHashOf,
) {
  final byPartial = <String, List<ScannedFile>>{};
  for (final f in sameSizeFiles) {
    byPartial.putIfAbsent(partialHashOf(f), () => []).add(f);
  }
  byPartial.removeWhere((_, group) => group.length < 2);
  return byPartial;
}

/// Stage 3: within a (size, partial-hash) group, sub-group by full BLAKE3
/// digest. Only groups of 2+ files sharing size AND full digest become
/// [DuplicateGroup]s - the only condition under which this project ever
/// calls two files exact duplicates.
List<DuplicateGroup> groupByFullHashCandidates(
  int size,
  List<ScannedFile> sameSizeSamePartialFiles,
  String Function(ScannedFile) fullHashOf,
) {
  final byFull = <String, List<ScannedFile>>{};
  for (final f in sameSizeSamePartialFiles) {
    byFull.putIfAbsent(fullHashOf(f), () => []).add(f);
  }
  final groups = <DuplicateGroup>[];
  byFull.forEach((hash, files) {
    if (files.length >= 2) {
      groups.add(
        DuplicateGroup(fullHashHex: hash, fileSize: size, files: files),
      );
    }
  });
  return groups;
}
