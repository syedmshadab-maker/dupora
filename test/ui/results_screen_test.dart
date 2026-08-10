import 'package:dupora/features/duplicates/domain/duplicate_group.dart';
import 'package:dupora/features/scanner/domain/scan_progress.dart';
import 'package:dupora/features/scanner/domain/scanned_file.dart';
import 'package:dupora/features/scanner/scan_engine.dart';
import 'package:dupora/ui/screens/results_screen.dart';
import 'package:dupora/ui/state/app_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

ScannedFile _file(String path, {DateTime? modified}) {
  return ScannedFile(path: path, name: path, extension: 'txt', size: 100, modifiedAt: modified ?? DateTime(2024));
}

Widget _wrap(AppController controller) {
  return ChangeNotifierProvider.value(
    value: controller,
    child: const MaterialApp(home: ResultsScreen()),
  );
}

void main() {
  testWidgets('shows the empty state when there are no duplicate groups', (tester) async {
    final controller = AppController();
    controller.lastResult = const ScanResult(groups: [], errors: [], finalProgress: ScanProgress.initial());

    await tester.pumpWidget(_wrap(controller));

    expect(find.text('No exact duplicates found'), findsOneWidget);
  });

  testWidgets('lists a duplicate group with its file count and reclaimable size', (tester) async {
    final controller = AppController();
    final oldFile = _file('C:/a/old.txt', modified: DateTime(2020));
    final newFile = _file('C:/a/new.txt', modified: DateTime(2024));
    final group = DuplicateGroup(fullHashHex: 'abc', fileSize: 100, files: [oldFile, newFile]);
    controller.lastResult = ScanResult(
      groups: [group],
      errors: const [],
      finalProgress: const ScanProgress.initial(),
    );

    await tester.pumpWidget(_wrap(controller));
    await tester.pumpAndSettle();

    expect(find.textContaining('2 copies'), findsOneWidget);
    expect(find.textContaining('100 B reclaimable'), findsOneWidget);
  });

  testWidgets('delete button is disabled until a file is selected', (tester) async {
    final controller = AppController();
    final oldFile = _file('C:/a/old.txt', modified: DateTime(2020));
    final newFile = _file('C:/a/new.txt', modified: DateTime(2024));
    final group = DuplicateGroup(fullHashHex: 'abc', fileSize: 100, files: [oldFile, newFile]);
    controller.lastResult = ScanResult(
      groups: [group],
      errors: const [],
      finalProgress: const ScanProgress.initial(),
    );
    // No default-selection pass applied (that normally happens after a real
    // scan completes via _applyDefaultSelection) - selectedCount starts at 0.

    await tester.pumpWidget(_wrap(controller));
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });
}
