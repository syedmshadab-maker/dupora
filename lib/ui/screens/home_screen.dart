import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../features/storage/domain/storage_volume.dart';
import '../state/app_controller.dart';
import '../widgets/format.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dupora'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'Select locations to scan',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Choose one or more drives or folders. Only exact byte-for-byte duplicates are ever reported.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                for (final volume in controller.volumes)
                  _VolumeTile(
                    volume: volume,
                    selected: controller.selectedRoots.contains(
                      volume.rootPath,
                    ),
                    onTap: () => controller.toggleRootSelected(volume.rootPath),
                  ),
                for (final folder in controller.customFolders)
                  _FolderTile(
                    path: folder,
                    selected: controller.selectedRoots.contains(folder),
                    onTap: () => controller.toggleRootSelected(folder),
                  ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _pickFolder(context, controller),
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: const Text('Add Folder'),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: FilledButton.icon(
                onPressed: controller.selectedRoots.isEmpty
                    ? null
                    : controller.startScan,
                icon: const Icon(Icons.search),
                label: Text(
                  controller.selectedRoots.isEmpty
                      ? 'Select at least one location'
                      : 'Start Scan (${controller.selectedRoots.length} selected)',
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFolder(
    BuildContext context,
    AppController controller,
  ) async {
    if (Platform.isAndroid) {
      // Android has no raw folder-path concept; SAF tree picking is a
      // distinct flow (see SafBridge.pickDirectory) not yet wired into this
      // screen's UI. See KNOWN LIMITATIONS in README.md.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Use "Add Folder" from a storage volume on Android (SAF picker).',
          ),
        ),
      );
      return;
    }
    final path = await getDirectoryPath();
    if (path != null) controller.addCustomFolder(path);
  }
}

class _VolumeTile extends StatelessWidget {
  const _VolumeTile({
    required this.volume,
    required this.selected,
    required this.onTap,
  });

  final StorageVolume volume;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
        ),
      ),
      color: selected ? scheme.primaryContainer.withValues(alpha: 0.35) : null,
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                volume.isRemovable
                    ? Icons.usb_outlined
                    : Icons.storage_outlined,
                color: scheme.primary,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      volume.label?.isNotEmpty == true
                          ? '${volume.label} (${volume.rootPath})'
                          : volume.rootPath,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: volume.usedFraction,
                        minHeight: 6,
                        backgroundColor: scheme.surfaceContainerHighest,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${formatBytes(volume.usedBytes)} used of ${formatBytes(volume.totalBytes)} '
                      '(${formatBytes(volume.freeBytes)} free)',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Checkbox(value: selected, onChanged: (_) => onTap()),
            ],
          ),
        ),
      ),
    );
  }
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({
    required this.path,
    required this.selected,
    required this.onTap,
  });

  final String path;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
        ),
      ),
      color: selected ? scheme.primaryContainer.withValues(alpha: 0.35) : null,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        leading: Icon(Icons.folder_outlined, color: scheme.primary),
        title: Text(path, overflow: TextOverflow.ellipsis),
        trailing: Checkbox(value: selected, onChanged: (_) => onTap()),
      ),
    );
  }
}
