import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../features/duplicates/domain/selection_strategy.dart';
import '../../features/settings/settings_model.dart';
import '../state/app_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final s = controller.settings;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _SectionHeader('Scanning'),
          SwitchListTile(
            title: const Text('Scan hidden files'),
            subtitle: const Text('Include dotfiles / hidden-attribute files'),
            value: s.scanHiddenFiles,
            onChanged: (v) => controller.updateSettings(s.copyWith(scanHiddenFiles: v)),
          ),
          SwitchListTile(
            title: const Text('Scan system files'),
            subtitle: const Text('Include OS-marked system files'),
            value: s.scanSystemFiles,
            onChanged: (v) => controller.updateSettings(s.copyWith(scanSystemFiles: v)),
          ),
          SwitchListTile(
            title: const Text('Follow symlinks'),
            subtitle: const Text('Off by default to avoid loops and scanning outside selected folders'),
            value: s.followSymlinks,
            onChanged: (v) => controller.updateSettings(s.copyWith(followSymlinks: v)),
          ),
          ListTile(
            title: const Text('Maximum concurrency'),
            subtitle: Text(s.maxConcurrency == 0 ? 'Automatic (based on CPU cores)' : '${s.maxConcurrency} workers'),
            trailing: SizedBox(
              width: 160,
              child: Slider(
                value: s.maxConcurrency.toDouble(),
                min: 0,
                max: 16,
                divisions: 16,
                label: s.maxConcurrency == 0 ? 'Auto' : '${s.maxConcurrency}',
                onChanged: (v) => controller.updateSettings(s.copyWith(maxConcurrency: v.round())),
              ),
            ),
          ),
          const Divider(),
          const _SectionHeader('Deletion'),
          SwitchListTile(
            title: const Text('Confirm before delete'),
            value: s.confirmBeforeDelete,
            onChanged: (v) => controller.updateSettings(s.copyWith(confirmBeforeDelete: v)),
          ),
          ListTile(
            title: const Text('Default smart-selection strategy'),
            subtitle: Text(_strategyLabel(s.defaultSelectionStrategy)),
            trailing: DropdownButton<SmartSelectionStrategy>(
              value: s.defaultSelectionStrategy,
              onChanged: (v) {
                if (v != null) controller.updateSettings(s.copyWith(defaultSelectionStrategy: v));
              },
              items: SmartSelectionStrategy.values
                  .map((v) => DropdownMenuItem(value: v, child: Text(_strategyLabel(v))))
                  .toList(),
            ),
          ),
          const Divider(),
          const _SectionHeader('Appearance'),
          ListTile(
            title: const Text('Theme'),
            trailing: SegmentedButton<DuporaThemeMode>(
              segments: const [
                ButtonSegment(value: DuporaThemeMode.system, label: Text('System')),
                ButtonSegment(value: DuporaThemeMode.light, label: Text('Light')),
                ButtonSegment(value: DuporaThemeMode.dark, label: Text('Dark')),
              ],
              selected: {s.themeMode},
              onSelectionChanged: (v) => controller.updateSettings(s.copyWith(themeMode: v.first)),
            ),
          ),
          const Divider(),
          const _SectionHeader('Protected locations'),
          for (final loc in s.userProtectedLocations)
            ListTile(
              title: Text(loc),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => controller.updateSettings(
                  s.copyWith(
                    userProtectedLocations: [...s.userProtectedLocations]..remove(loc),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Operating system, application, and database directories are always protected '
              'and cannot be removed from this list.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  String _strategyLabel(SmartSelectionStrategy s) => switch (s) {
        SmartSelectionStrategy.keepOldest => 'Keep oldest',
        SmartSelectionStrategy.keepNewest => 'Keep newest',
        SmartSelectionStrategy.keepShortestPath => 'Keep shortest path',
        SmartSelectionStrategy.keepFirst => 'Keep first',
      };
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}
