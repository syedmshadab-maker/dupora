import 'package:meta/meta.dart';

enum ScanPhase {
  idle,
  discovering,
  sizeGrouping,
  partialHashing,
  fullHashing,
  completed,
  cancelled,
  failed,
}

/// Strongly typed, immutable progress snapshot broadcast on the scan
/// engine's progress stream. The UI must never rebuild on every byte read;
/// the scan engine throttles emission (see `ScanEngine._progressThrottle`)
/// rather than pushing this on every internal update.
@immutable
class ScanProgress {
  const ScanProgress({
    required this.phase,
    required this.totalFiles,
    required this.processedFiles,
    required this.totalBytes,
    required this.processedBytes,
    required this.currentFile,
    required this.bytesPerSecond,
    required this.filesPerSecond,
    required this.estimatedRemaining,
    required this.duplicateFiles,
    required this.duplicateBytes,
    required this.errorCount,
    required this.isPaused,
    required this.isCancelled,
  });

  const ScanProgress.initial()
      : phase = ScanPhase.idle,
        totalFiles = 0,
        processedFiles = 0,
        totalBytes = 0,
        processedBytes = 0,
        currentFile = null,
        bytesPerSecond = 0,
        filesPerSecond = 0,
        estimatedRemaining = null,
        duplicateFiles = 0,
        duplicateBytes = 0,
        errorCount = 0,
        isPaused = false,
        isCancelled = false;

  final ScanPhase phase;
  final int totalFiles;
  final int processedFiles;
  final int totalBytes;
  final int processedBytes;
  final String? currentFile;
  final double bytesPerSecond;
  final double filesPerSecond;
  final Duration? estimatedRemaining;
  final int duplicateFiles;
  final int duplicateBytes;
  final int errorCount;
  final bool isPaused;
  final bool isCancelled;

  double get fractionComplete => totalFiles == 0 ? 0 : (processedFiles / totalFiles).clamp(0, 1);

  ScanProgress copyWith({
    ScanPhase? phase,
    int? totalFiles,
    int? processedFiles,
    int? totalBytes,
    int? processedBytes,
    String? currentFile,
    double? bytesPerSecond,
    double? filesPerSecond,
    Duration? estimatedRemaining,
    int? duplicateFiles,
    int? duplicateBytes,
    int? errorCount,
    bool? isPaused,
    bool? isCancelled,
  }) {
    return ScanProgress(
      phase: phase ?? this.phase,
      totalFiles: totalFiles ?? this.totalFiles,
      processedFiles: processedFiles ?? this.processedFiles,
      totalBytes: totalBytes ?? this.totalBytes,
      processedBytes: processedBytes ?? this.processedBytes,
      currentFile: currentFile ?? this.currentFile,
      bytesPerSecond: bytesPerSecond ?? this.bytesPerSecond,
      filesPerSecond: filesPerSecond ?? this.filesPerSecond,
      estimatedRemaining: estimatedRemaining ?? this.estimatedRemaining,
      duplicateFiles: duplicateFiles ?? this.duplicateFiles,
      duplicateBytes: duplicateBytes ?? this.duplicateBytes,
      errorCount: errorCount ?? this.errorCount,
      isPaused: isPaused ?? this.isPaused,
      isCancelled: isCancelled ?? this.isCancelled,
    );
  }
}
