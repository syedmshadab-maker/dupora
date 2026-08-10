import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/settings/settings_model.dart';
import 'screens/home_screen.dart';
import 'screens/results_screen.dart';
import 'screens/scan_screen.dart';
import 'state/app_controller.dart';

class DuporaApp extends StatelessWidget {
  const DuporaApp({super.key});

  /// Brand Electric Blue - see branding/BRAND_GUIDELINES.md.
  static const _seed = Color(0xFF0EA5FF);

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();

    final lightScheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.light,
    );
    final darkScheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
    );

    return MaterialApp(
      title: 'Dupora',
      debugShowCheckedModeBanner: false,
      themeMode: switch (controller.settings.themeMode) {
        DuporaThemeMode.system => ThemeMode.system,
        DuporaThemeMode.light => ThemeMode.light,
        DuporaThemeMode.dark => ThemeMode.dark,
      },
      theme: _buildTheme(lightScheme),
      darkTheme: _buildTheme(darkScheme),
      home: const _RootShell(),
    );
  }

  ThemeData _buildTheme(ColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
      ),
      cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
      splashFactory: InkSparkle.splashFactory,
    );
  }
}

class _RootShell extends StatelessWidget {
  const _RootShell();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    return switch (controller.screen) {
      AppScreen.home => const HomeScreen(),
      AppScreen.scanning => const ScanScreen(),
      AppScreen.results => const ResultsScreen(),
    };
  }
}
