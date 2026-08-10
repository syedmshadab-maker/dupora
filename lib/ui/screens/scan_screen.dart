import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../features/scanner/domain/scan_progress.dart';
import '../state/app_controller.dart';
import '../widgets/format.dart';

class ScanScreen extends StatelessWidget {
  const ScanScreen({super.key});

  String _phaseLabel(ScanPhase phase) => switch (phase) {
    ScanPhase.idle => 'Preparing…',
    ScanPhase.discovering => 'Discovering files',
    ScanPhase.sizeGrouping => 'Grouping by size',
    ScanPhase.partialHashing => 'Fingerprinting candidates',
    ScanPhase.fullHashing => 'Verifying with BLAKE3',
    ScanPhase.completed => 'Completed',
    ScanPhase.cancelled => 'Cancelled',
    ScanPhase.failed => 'Failed',
  };

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final progress = controller.lastProgress ?? const ScanProgress.initial();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Scanning')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _phaseLabel(progress.phase),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress.totalFiles == 0
                    ? null
                    : progress.fractionComplete,
                minHeight: 10,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${progress.processedFiles} / ${progress.totalFiles == 0 ? '…' : progress.totalFiles} files',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (progress.currentFile != null) ...[
              const SizedBox(height: 4),
              Text(
                progress.currentFile!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    label: 'Speed',
                    value: formatRate(progress.bytesPerSecond),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    label: 'Files/s',
                    value: progress.filesPerSecond.toStringAsFixed(1),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    label: 'ETA',
                    value: progress.estimatedRemaining == null
                        ? '—'
                        : formatDuration(progress.estimatedRemaining!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    label: 'Data scanned',
                    value:
                        '${formatBytes(progress.processedBytes)} / ${formatBytes(progress.totalBytes)}',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    label: 'Errors',
                    value: '${progress.errorCount}',
                  ),
                ),
              ],
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => progress.isPaused
                        ? controller.resumeScan()
                        : controller.pauseScan(),
                    icon: Icon(
                      progress.isPaused ? Icons.play_arrow : Icons.pause,
                    ),
                    label: Text(progress.isPaused ? 'Resume' : 'Pause'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: controller.cancelScan,
                    icon: const Icon(Icons.close),
                    label: const Text('Cancel'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}
