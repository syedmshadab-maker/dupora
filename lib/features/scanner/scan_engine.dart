import 'dart:async';

import '../../core/native/hash_engine.dart';
import '../../core/native/status_code.dart';
import '../cache/hash_cache_repository.dart';
import '../duplicates/domain/duplicate_group.dart';
import '../settings/settings_model.dart';
import 'data/duplicate_funnel.dart';
import 'data/file_discovery.dart';
import 'data/hash_worker_pool.dart';
import 'domain/scan_progress.dart';
import 'domain/scanned_file.dart';

class ScanResult {
  const ScanResult({required this.groups, required this.errors, required this.finalProgress});
  final List<DuplicateGroup> groups;
  final List<ScanError> errors;
  final ScanProgress finalProgress;
}

/// Orchestrates the full pipeline: Stage 0 discovery -> Stage 1 size
/// grouping -> Stage 2 partial fingerprint -> Stage 3 full BLAKE3,
/// checking the persistent cache before any native hash call and writing
/// results back to it, broadcasting a throttled [ScanProgress] stream the
/// UI can bind to directly.
class ScanEngine {
  ScanEngine({
    required HashCacheRepository cache,
    this.settings = const DuporaSettings(),
  }) : _cache = cache;

  final HashCacheRepository _cache;
  final DuporaSettings settings;

  final _progressController = StreamController<ScanProgress>.broadcast();
  Stream<ScanProgress> get progressStream => _progressController.stream;

  CancelSignal? _cancelSignal;
  Timer? _progressTimer;
  Completer<void>? _pauseGate;

  ScanProgress _progress = const ScanProgress.initial();
  final List<ScanError> _errors = [];
  final Map<int, NativeProgressCounter> _activeStage3Progress = {};
  int _completedStage3Bytes = 0;
  DateTime _lastRateSample = DateTime.now();
  int _bytesAtLastSample = 0;
  int _filesAtLastSample = 0;

  bool get isPaused => _pauseGate != null;

  void pause() {
    if (_pauseGate == null) {
      _pauseGate = Completer<void>();
      _emit(_progress.copyWith(isPaused: true));
    }
  }

  void resume() {
    _pauseGate?.complete();
    _pauseGate = null;
    _emit(_progress.copyWith(isPaused: false));
  }

  Future<void> cancel() async {
    _cancelSignal?.cancel();
    resume(); // unblock a paused scan so it can observe cancellation and exit.
  }

  Future<void> _waitIfPaused() async {
    final gate = _pauseGate;
    if (gate != null) await gate.future;
  }

  Future<ScanResult> start(List<String> roots) async {
    _errors.clear();
    _completedStage3Bytes = 0;
    _activeStage3Progress.clear();
    final cancel = _cancelSignal = CancelSignal.create();
    final hasher = NativeHasher();
    final pool = HashWorkerPool(
      settings.maxConcurrency > 0 ? settings.maxConcurrency : hasher.recommendedWorkerCount(),
    );
    await pool.start();
    _startProgressTicker();

    try {
      // --- Stage 0: discovery ---
      _progress = _progress.copyWith(phase: ScanPhase.discovering, currentFile: null);
      _emit(_progress);

      final files = <ScannedFile>[];
      final discovery = runFileDiscovery(
        DiscoveryOptions(
          roots: roots,
          scanHiddenFiles: settings.scanHiddenFiles,
          scanSystemFiles: settings.scanSystemFiles,
          followSymlinks: settings.followSymlinks,
        ),
        cancel,
      );
      await for (final event in discovery) {
        if (event is DiscoveryBatch) {
          files.addAll(event.files);
          _errors.addAll(event.errors);
          _progress = _progress.copyWith(
            totalFiles: files.length,
            processedFiles: files.length,
            totalBytes: files.fold<int>(0, (a, f) => a + f.size),
            errorCount: _errors.length,
            currentFile: event.files.isNotEmpty ? event.files.last.path : _progress.currentFile,
          );
          _emit(_progress);
        } else if (event is DiscoveryDone) {
          if (event.cancelled) return _finishCancelled(files.length);
        }
        await _waitIfPaused();
        if (cancel.isCancelled) return _finishCancelled(files.length);
      }

      // --- Stage 1: size grouping ---
      _progress = _progress.copyWith(phase: ScanPhase.sizeGrouping);
      _emit(_progress);
      final sizeGroups = groupBySizeCandidates(files);
      final stage1Candidates = sizeGroups.values.expand((g) => g).toList();

      if (cancel.isCancelled) return _finishCancelled(files.length);

      // --- Stage 2: partial fingerprint ---
      _progress = _progress.copyWith(
        phase: ScanPhase.partialHashing,
        totalFiles: stage1Candidates.length,
        processedFiles: 0,
      );
      _emit(_progress);

      final partialHashes = <String, String>{}; // path -> hex
      var stage2Done = 0;
      var jobId = 0;
      for (final entry in sizeGroups.entries) {
        if (cancel.isCancelled) return _finishCancelled(files.length);
        await _waitIfPaused();

        final group = entry.value;
        await Future.wait(group.map((file) async {
          final cached = await _cache.lookup(file);
          String hex;
          if (cached?.partialHashHex != null) {
            hex = cached!.partialHashHex!;
          } else {
            final result = await pool.submit(HashJob(
              id: jobId++,
              path: file.path,
              kind: HashJobKind.partial,
              fileSize: file.size,
            ));
            if (!result.isOk) {
              _errors.add(ScanError(path: file.path, message: 'partial hash failed: ${result.status}', stage: 'stage2'));
              return;
            }
            hex = _hex(result.digest);
            await _cache.storePartial(file, hex);
          }
          partialHashes[file.path] = hex;
          stage2Done++;
          _progress = _progress.copyWith(processedFiles: stage2Done, currentFile: file.path);
        }));
        _emit(_progress);
      }

      // Build (size, partialHash) candidate groups.
      final stage2Groups = <String, List<ScannedFile>>{};
      for (final entry in sizeGroups.entries) {
        final bySizePartial = groupByPartialCandidates(
          entry.value,
          (f) => partialHashes[f.path] ?? '',
        );
        bySizePartial.forEach((partialHex, group) {
          stage2Groups['${entry.key}:$partialHex'] = group;
        });
      }
      final stage3Candidates = stage2Groups.values.expand((g) => g).toList();

      // --- Stage 3: full BLAKE3 ---
      final stage3TotalBytes = stage3Candidates.fold<int>(0, (a, f) => a + f.size);
      _progress = _progress.copyWith(
        phase: ScanPhase.fullHashing,
        totalFiles: stage3Candidates.length,
        processedFiles: 0,
        totalBytes: stage3TotalBytes,
        processedBytes: 0,
      );
      _emit(_progress);

      final fullHashes = <String, String>{};
      var stage3Done = 0;
      for (final entry in stage2Groups.entries) {
        if (cancel.isCancelled) return _finishCancelled(files.length);
        await _waitIfPaused();

        final group = entry.value;
        await Future.wait(group.map((file) async {
          final cached = await _cache.lookup(file);
          String hex;
          if (cached?.fullHashHex != null) {
            hex = cached!.fullHashHex!;
            _completedStage3Bytes += file.size;
          } else {
            final progressCounter = NativeProgressCounter.create();
            final id = jobId++;
            _activeStage3Progress[id] = progressCounter;
            final result = await pool.submit(HashJob(
              id: id,
              path: file.path,
              kind: HashJobKind.full,
              fileSize: file.size,
              progressAddress: progressCounter.rawAddress,
              cancelAddress: cancel.rawAddress,
            ));
            _activeStage3Progress.remove(id);
            progressCounter.dispose();

            if (!result.isOk) {
              if (result.status != NativeStatus.cancelled) {
                _errors.add(ScanError(path: file.path, message: 'full hash failed: ${result.status}', stage: 'stage3'));
              }
              return;
            }
            hex = _hex(result.digest);
            final partialHex = partialHashes[file.path] ?? '';
            await _cache.storeFull(file, partialHex, hex);
            _completedStage3Bytes += file.size;
          }
          fullHashes[file.path] = hex;
          stage3Done++;
          _progress = _progress.copyWith(processedFiles: stage3Done, currentFile: file.path);
        }));
      }

      if (cancel.isCancelled) return _finishCancelled(files.length);

      // --- Final grouping ---
      final groups = <DuplicateGroup>[];
      for (final entry in stage2Groups.entries) {
        final size = int.parse(entry.key.split(':').first);
        groups.addAll(groupByFullHashCandidates(
          size,
          entry.value,
          (f) => fullHashes[f.path] ?? '',
        ));
      }

      final duplicateFiles = groups.fold<int>(0, (a, g) => a + g.duplicateCount);
      final duplicateBytes = groups.fold<int>(0, (a, g) => a + g.wastedBytes);

      _progress = _progress.copyWith(
        phase: ScanPhase.completed,
        duplicateFiles: duplicateFiles,
        duplicateBytes: duplicateBytes,
        errorCount: _errors.length,
        currentFile: null,
      );
      _emit(_progress);

      return ScanResult(groups: groups, errors: List.of(_errors), finalProgress: _progress);
    } finally {
      _progressTimer?.cancel();
      await pool.shutdown();
      cancel.dispose();
    }
  }

  ScanResult _finishCancelled(int filesSeen) {
    _progress = _progress.copyWith(phase: ScanPhase.cancelled, isCancelled: true, currentFile: null);
    _emit(_progress);
    return ScanResult(groups: const [], errors: List.of(_errors), finalProgress: _progress);
  }

  void _startProgressTicker() {
    _lastRateSample = DateTime.now();
    _bytesAtLastSample = 0;
    _filesAtLastSample = 0;
    _progressTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final liveBytes = _completedStage3Bytes +
          _activeStage3Progress.values.fold<int>(0, (a, c) => a + c.bytesProcessed);
      final now = DateTime.now();
      final elapsed = now.difference(_lastRateSample).inMilliseconds / 1000.0;
      if (elapsed > 0) {
        final bytesPerSecond = (liveBytes - _bytesAtLastSample) / elapsed;
        final filesPerSecond = (_progress.processedFiles - _filesAtLastSample) / elapsed;
        final remainingBytes = (_progress.totalBytes - liveBytes).clamp(0, double.infinity);
        final eta = bytesPerSecond > 1
            ? Duration(seconds: (remainingBytes / bytesPerSecond).round())
            : null;
        _progress = _progress.copyWith(
          processedBytes: liveBytes,
          bytesPerSecond: bytesPerSecond < 0 ? 0 : bytesPerSecond,
          filesPerSecond: filesPerSecond < 0 ? 0 : filesPerSecond,
          estimatedRemaining: eta,
        );
        _lastRateSample = now;
        _bytesAtLastSample = liveBytes;
        _filesAtLastSample = _progress.processedFiles;
        _emit(_progress);
      }
    });
  }

  void _emit(ScanProgress progress) {
    _progress = progress;
    if (!_progressController.isClosed) _progressController.add(_progress);
  }

  void dispose() {
    _progressTimer?.cancel();
    _progressController.close();
  }

  static String _hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
