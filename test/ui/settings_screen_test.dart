import 'package:dupora/features/settings/settings_model.dart';
import 'package:dupora/ui/screens/settings_screen.dart';
import 'package:dupora/ui/state/app_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _FakeAppController extends AppController {
  int updateCount = 0;

  @override
  Future<void> updateSettings(DuporaSettings newSettings) async {
    settings = newSettings;
    updateCount++;
    notifyListeners();
  }
}

Widget _wrap(AppController controller) {
  return ChangeNotifierProvider.value(
    value: controller,
    child: const MaterialApp(home: SettingsScreen()),
  );
}

void main() {
  testWidgets('toggling "Scan hidden files" calls updateSettings with the new value', (tester) async {
    final controller = _FakeAppController();
    await tester.pumpWidget(_wrap(controller));

    expect(controller.settings.scanHiddenFiles, isFalse);

    await tester.tap(find.widgetWithText(SwitchListTile, 'Scan hidden files'));
    await tester.pumpAndSettle();

    expect(controller.updateCount, 1);
    expect(controller.settings.scanHiddenFiles, isTrue);
  });

  testWidgets('protected locations from settings are listed and removable', (tester) async {
    final controller = _FakeAppController();
    controller.settings = controller.settings.copyWith(userProtectedLocations: const ['C:\\Vault']);
    await tester.pumpWidget(_wrap(controller));

    await tester.scrollUntilVisible(find.text('C:\\Vault'), 300);
    expect(find.text('C:\\Vault'), findsOneWidget);

    await tester.scrollUntilVisible(find.byIcon(Icons.close), 300);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(controller.settings.userProtectedLocations, isEmpty);
  });
}
