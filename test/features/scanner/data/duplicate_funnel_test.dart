import 'package:dupora/features/scanner/data/duplicate_funnel.dart';
import 'package:dupora/features/scanner/domain/scanned_file.dart';
import 'package:flutter_test/flutter_test.dart';

ScannedFile _file(String path, int size, {DateTime? modified}) {
  return ScannedFile(
    path: path,
    name: path,
    extension: '',
    size: size,
    modifiedAt: modified ?? DateTime(2024),
  );
}

void main() {
  group('groupBySizeCandidates', () {
    test('drops files with a unique size', () {
      final files = [_file('a', 100), _file('b', 200), _file('c', 300)];
      final groups = groupBySizeCandidates(files);
      expect(groups, isEmpty);
    });

    test('keeps groups of 2+ files sharing a size', () {
      final files = [_file('a', 100), _file('b', 100), _file('c', 200)];
      final groups = groupBySizeCandidates(files);
      expect(groups.keys, [100]);
      expect(groups[100]!.map((f) => f.path), containsAll(['a', 'b']));
    });

    test('zero-byte files are grouped like any other size', () {
      final files = [_file('a', 0), _file('b', 0)];
      final groups = groupBySizeCandidates(files);
      expect(groups[0]!.length, 2);
    });
  });

  group('groupByPartialCandidates', () {
    test('splits a size group by partial fingerprint and drops singletons', () {
      final files = [_file('a', 100), _file('b', 100), _file('c', 100)];
      final partials = {'a': 'hash1', 'b': 'hash1', 'c': 'hash2'};
      final groups = groupByPartialCandidates(files, (f) => partials[f.path]!);
      expect(groups.keys, ['hash1']);
      expect(groups['hash1']!.map((f) => f.path), containsAll(['a', 'b']));
    });
  });

  group('groupByFullHashCandidates', () {
    test('only files sharing size AND full hash become a DuplicateGroup', () {
      final files = [_file('a', 100), _file('b', 100), _file('c', 100)];
      final full = {'a': 'full1', 'b': 'full1', 'c': 'full2'};
      final groups = groupByFullHashCandidates(
        100,
        files,
        (f) => full[f.path]!,
      );
      expect(groups, hasLength(1));
      expect(groups.first.fileSize, 100);
      expect(groups.first.files.map((f) => f.path), containsAll(['a', 'b']));
    });

    test('same size + different partial-derived full hash never merges', () {
      final files = [_file('a', 100), _file('b', 100)];
      final full = {'a': 'full1', 'b': 'full2'};
      final groups = groupByFullHashCandidates(
        100,
        files,
        (f) => full[f.path]!,
      );
      expect(groups, isEmpty);
    });
  });
}
