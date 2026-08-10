import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../features/duplicates/domain/duplicate_group.dart';
import '../../features/duplicates/domain/selection_strategy.dart';
import '../../features/preview/thumbnail_service.dart';
import '../../features/scanner/domain/scanned_file.dart';
import '../state/app_controller.dart';
import '../widgets/file_type_icon.dart';
import '../widgets/format.dart';

final _thumbnailService = ThumbnailService();

class ResultsScreen extends StatelessWidget {
  const ResultsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final result = controller.lastResult;
    final groups = result?.groups ?? const <DuplicateGroup>[];
    final wastedBytes = groups.fold<int>(0, (a, g) => a + g.wastedBytes);
    final duplicateFiles = groups.fold<int>(0, (a, g) => a + g.duplicateCount);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Duplicates'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: controller.backToHome),
        actions: [
          PopupMenuButton<SmartSelectionStrategy>(
            tooltip: 'Smart selection',
            icon: const Icon(Icons.auto_fix_high_outlined),
            onSelected: controller.applyStrategyToAllGroups,
            itemBuilder: (context) => const [
              PopupMenuItem(value: SmartSelectionStrategy.keepOldest, child: Text('Keep oldest')),
              PopupMenuItem(value: SmartSelectionStrategy.keepNewest, child: Text('Keep newest')),
              PopupMenuItem(value: SmartSelectionStrategy.keepShortestPath, child: Text('Keep shortest path')),
              PopupMenuItem(value: SmartSelectionStrategy.keepFirst, child: Text('Keep first')),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: groups.isEmpty
          ? _EmptyState(errors: result?.errors.length ?? 0)
          : Column(
              children: [
                _SummaryBar(
                  groupCount: groups.length,
                  duplicateFiles: duplicateFiles,
                  wastedBytes: wastedBytes,
                  errorCount: result?.errors.length ?? 0,
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: groups.length,
                    itemBuilder: (context, index) => _GroupTile(group: groups[index]),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: groups.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: FilledButton.icon(
                  onPressed: controller.selectedCount == 0 ? null : () => _confirmAndDelete(context, controller),
                  icon: Icon(controller.deleteCoordinator.usesTrash ? Icons.delete_outline : Icons.delete_forever),
                  label: Text(
                    controller.selectedCount == 0
                        ? 'Select duplicates to remove'
                        : '${controller.deleteCoordinator.usesTrash ? "Move" : "Permanently delete"} '
                            '${controller.selectedCount} files (${formatBytes(controller.selectedBytes)})',
                  ),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                ),
              ),
            ),
    );
  }

  Future<void> _confirmAndDelete(BuildContext context, AppController controller) async {
    final usesTrash = controller.deleteCoordinator.usesTrash;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(usesTrash ? 'Move to Trash?' : 'Permanently Delete?'),
        content: Text(
          usesTrash
              ? 'This will move ${controller.selectedCount} files '
                  '(${formatBytes(controller.selectedBytes)}) to the Recycle Bin / Trash. You can restore them from there.'
              : 'This platform has no Trash for these files. '
                  '${controller.selectedCount} files (${formatBytes(controller.selectedBytes)}) '
                  'will be PERMANENTLY deleted and cannot be recovered.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: usesTrash ? null : FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: Text(usesTrash ? 'Move to Trash' : 'Delete Permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final results = await controller.deleteSelected();
    final failed = results.where((r) => !r.succeeded).length;
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failed == 0
                ? 'Deleted ${results.length} files.'
                : 'Deleted ${results.length - failed} files, $failed failed.',
          ),
        ),
      );
    }
  }
}

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({
    required this.groupCount,
    required this.duplicateFiles,
    required this.wastedBytes,
    required this.errorCount,
  });

  final int groupCount;
  final int duplicateFiles;
  final int wastedBytes;
  final int errorCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Wrap(
        spacing: 24,
        runSpacing: 8,
        children: [
          _summaryItem(context, '$groupCount', 'duplicate groups'),
          _summaryItem(context, '$duplicateFiles', 'duplicate files'),
          _summaryItem(context, formatBytes(wastedBytes), 'reclaimable'),
          if (errorCount > 0) _summaryItem(context, '$errorCount', 'errors', color: scheme.error),
        ],
      ),
    );
  }

  Widget _summaryItem(BuildContext context, String value, String label, {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color)),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.errors});
  final int errors;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline, size: 56, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text('No exact duplicates found', style: Theme.of(context).textTheme.titleMedium),
          if (errors > 0) ...[
            const SizedBox(height: 8),
            Text('$errors files could not be read during the scan.', style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.group});
  final DuplicateGroup group;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final keep = controller.keepFileFor(group);

    return ExpansionTile(
      leading: FileThumbnail(
        path: keep.path,
        modifiedAt: keep.modifiedAt,
        extension: keep.extension,
        thumbnailService: _thumbnailService,
      ),
      title: Text(keep.name, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${group.files.length} copies · ${formatBytes(group.fileSize)} each · '
        '${formatBytes(group.wastedBytes)} reclaimable',
      ),
      children: [
        for (final file in group.files) _FileRow(file: file, keep: keep, group: group),
      ],
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.file, required this.keep, required this.group});
  final ScannedFile file;
  final ScannedFile keep;
  final DuplicateGroup group;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final isKeep = file == keep;
    final selected = controller.isSelectedForDeletion(file);

    return ListTile(
      contentPadding: const EdgeInsets.only(left: 32, right: 16),
      leading: isKeep
          ? Tooltip(message: 'Kept copy', child: Icon(Icons.star, color: Theme.of(context).colorScheme.primary))
          : Checkbox(value: selected, onChanged: (_) => controller.toggleFileSelected(file, keep)),
      title: Text(file.path, overflow: TextOverflow.ellipsis),
      subtitle: Text(_formatDate(file.modifiedAt)),
      trailing: isKeep
          ? null
          : TextButton(
              onPressed: () => controller.setKeepFile(group, file),
              child: const Text('Keep this'),
            ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
