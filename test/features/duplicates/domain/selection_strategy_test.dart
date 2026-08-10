import 'package:dupora/features/deletion/protected_locations.dart';
import 'package:dupora/features/duplicates/domain/duplicate_group.dart';
import 'package:dupora/features/duplicates/domain/selection_strategy.dart';
import 'package:dupora/features/scanner/domain/scanned_file.dart';
import 'package:flutter_test/flutter_test.dart';

ScannedFile _file(String path, {required DateTime modified}) {
  return ScannedFile(
    path: path,
    name: path,
    extension: '',
    size: 100,
    modifiedAt: modified,
  );
}

void main() {
  final protectedLocations = ProtectedLocations(userDefined: const []);

  group('applySmartSelection', () {
    test('keepOldest keeps the earliest modified file', () {
      final oldest = _file('old', modified: DateTime(2020));
      final newest = _file('new', modified: DateTime(2024));
      final group = DuplicateGroup(
        fullHashHex: 'h',
        fileSize: 100,
        files: [newest, oldest],
      );

      final result = applySmartSelection(
        group,
        SmartSelectionStrategy.keepOldest,
        protectedLocations,
      );
      expect(result.keep, oldest);
      expect(result.selectedForDeletion, [newest]);
    });

    test('keepNewest keeps the latest modified file', () {
      final oldest = _file('old', modified: DateTime(2020));
      final newest = _file('new', modified: DateTime(2024));
      final group = DuplicateGroup(
        fullHashHex: 'h',
        fileSize: 100,
        files: [oldest, newest],
      );

      final result = applySmartSelection(
        group,
        SmartSelectionStrategy.keepNewest,
        protectedLocations,
      );
      expect(result.keep, newest);
    });

    test('keepShortestPath keeps the file with the shortest path', () {
      final short = _file('a', modified: DateTime(2020));
      final long = _file('a/very/long/nested/path', modified: DateTime(2020));
      final group = DuplicateGroup(
        fullHashHex: 'h',
        fileSize: 100,
        files: [long, short],
      );

      final result = applySmartSelection(
        group,
        SmartSelectionStrategy.keepShortestPath,
        protectedLocations,
      );
      expect(result.keep, short);
    });

    test('the kept file is never present in selectedForDeletion', () {
      final files = [
        _file('a', modified: DateTime(2020)),
        _file('b', modified: DateTime(2021)),
        _file('c', modified: DateTime(2022)),
      ];
      final group = DuplicateGroup(
        fullHashHex: 'h',
        fileSize: 100,
        files: files,
      );
      final result = applySmartSelection(
        group,
        SmartSelectionStrategy.keepOldest,
        protectedLocations,
      );
      expect(result.selectedForDeletion, isNot(contains(result.keep)));
      expect(result.selectedForDeletion, hasLength(2));
    });

    test(
      'a protected duplicate is never selected for deletion even if not the keep file',
      () {
        final protected = ProtectedLocations(
          userDefined: const ['C:\\Protected'],
        );
        final normal = _file('C:\\Users\\me\\a.txt', modified: DateTime(2024));
        final inProtected = _file(
          'C:\\Protected\\b.txt',
          modified: DateTime(2020),
        );
        final group = DuplicateGroup(
          fullHashHex: 'h',
          fileSize: 100,
          files: [normal, inProtected],
        );

        // keepOldest would normally pick inProtected as keep (it's older) and
        // select `normal` for deletion; that case doesn't exercise the guard.
        // Force keepNewest instead so inProtected is the one that *would* be
        // selected for deletion, and verify it's filtered out.
        final result = applySmartSelection(
          group,
          SmartSelectionStrategy.keepNewest,
          protected,
        );
        expect(result.keep, normal);
        expect(result.selectedForDeletion, isEmpty);
      },
    );
  });

  group('selectAllDuplicates', () {
    test('selects everything but the keep file, honoring protection', () {
      final protected = ProtectedLocations(
        userDefined: const ['C:\\Protected'],
      );
      final keep = _file('C:\\Users\\me\\a.txt', modified: DateTime(2024));
      final normalDup = _file('C:\\Users\\me\\b.txt', modified: DateTime(2024));
      final protectedDup = _file(
        'C:\\Protected\\c.txt',
        modified: DateTime(2024),
      );
      final group = DuplicateGroup(
        fullHashHex: 'h',
        fileSize: 100,
        files: [keep, normalDup, protectedDup],
      );

      final selected = selectAllDuplicates(group, keep, protected);
      expect(selected, [normalDup]);
    });
  });
}
