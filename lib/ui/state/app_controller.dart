import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import '../../features/cache/hash_cache_database.dart';
import '../../features/cache/hash_cache_repository.dart';
import '../../features/deletion/protected_locations.dart';
import '../../features/deletion/safe_delete_service.dart';
import '../../features/duplicates/domain/duplicate_group.dart';
import '../../features/duplicates/domain/selection_strategy.dart';
import '../../features/scanner/domain/scan_progress.dart';
import '../../features/scanner/domain/scanned_file.dart';
import '../../features/scanner/scan_engine.dart';
import '../../features/settings/settings_model.dart';
import '../../features/settings/settings_repository.dart';
import '../../features/storage/data/storage_detector.dart';
import '../../features/storage/domain/storage_volume.dart';

enum AppScreen { home, scanning, results }

final _log = Logger('AppController');

/// Top-level application state. Deliberately a single plain
/// `ChangeNotifier` rather than many small providers: this app has one
/// primary long-lived workflow (pick folders -> scan -> review -> delete),
/// so a single controller keeps that workflow easy to follow end to end.
class AppController extends ChangeNotifier {
  AppScreen screen = AppScreen.home;
  DuporaSettings settings = const DuporaSettings();

  List<StorageVolume> volumes = [];
  final Set<String> selectedRoots = {};
  final List<String> customFolders = [];

  ScanEngine? scanEngine;
  ScanProgress? lastProgress;
  ScanResult? lastResult;
  String? lastError;

  // Eagerly constructed (not `late`) so UI code and widget tests can use
  // an [AppController] before [init] resolves - both do only cheap,
  // synchronous, I/O-free work at construction time. [init] replaces
  // [protectedLocations]/[deleteCoordinator] once real settings are loaded.
  ProtectedLocations protectedLocations = ProtectedLocations();
  SafeDeleteCoordinator deleteCoordinator = SafeDeleteCoordinator(
    protectedLocations: ProtectedLocations(),
  );
  late final HashCacheRepository cacheRepo;

  final Map<String, ScannedFile> _keepOverrides =
      {}; // group hash -> chosen keep file
  final Set<String> _selectedForDeletion = {};

  HashCacheDatabase? _db;
  final _settingsRepo = SettingsRepository();

  // Set once in [dispose]. Every callback that can resume after an `await`
  // (i.e. after the widget tree that owns this controller may already have
  // been torn down) must check this before calling [notifyListeners]
  // directly - a `ChangeNotifier` throws if notified after disposal, and
  // that throw would otherwise surface as an app crash on whatever async
  // operation happened to be in flight when the app closed (most commonly
  // a large delete batch or an in-progress scan).
  bool _disposed = false;
  StreamSubscription<ScanProgress>? _progressSubscription;

  bool isDeleting = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> init() async {
    settings = await _settingsRepo.load();
    protectedLocations = ProtectedLocations(
      userDefined: settings.userProtectedLocations,
    );
    deleteCoordinator = SafeDeleteCoordinator(
      protectedLocations: protectedLocations,
    );

    _db = await HashCacheDatabase.open();
    cacheRepo = HashCacheRepository(_db!);

    try {
      volumes = await StorageDetector.forPlatform().listVolumes();
    } catch (e) {
      lastError = 'Could not enumerate storage volumes: $e';
      _log.warning('Volume enumeration failed: $e');
    }
    _notify();
  }

  void clearError() {
    lastError = null;
    _notify();
  }

  void toggleRootSelected(String path) {
    if (!selectedRoots.remove(path)) selectedRoots.add(path);
    _notify();
  }

  void addCustomFolder(String path) {
    if (!customFolders.contains(path)) customFolders.add(path);
    selectedRoots.add(path);
    _notify();
  }

  Future<void> updateSettings(DuporaSettings newSettings) async {
    settings = newSettings;
    protectedLocations = ProtectedLocations(
      userDefined: newSettings.userProtectedLocations,
    );
    deleteCoordinator = SafeDeleteCoordinator(
      protectedLocations: protectedLocations,
    );
    await _settingsRepo.save(settings);
    _notify();
  }

  Future<void> startScan() async {
    if (selectedRoots.isEmpty) return;
    // Reentrancy guard: a double-tap on "Start Scan" before the UI rebuilds
    // onto the Scan screen could otherwise spin up two concurrent
    // ScanEngine instances (two worker pools hashing the same files, two
    // writers racing on the same cache database).
    if (screen == AppScreen.scanning) return;
    screen = AppScreen.scanning;
    lastResult = null;
    lastProgress = null;
    lastError = null;
    _keepOverrides.clear();
    _selectedForDeletion.clear();
    _notify();

    final engine = ScanEngine(cache: cacheRepo, settings: settings);
    scanEngine = engine;
    unawaited(_progressSubscription?.cancel());
    _progressSubscription = engine.progressStream.listen((p) {
      lastProgress = p;
      _notify();
    });

    try {
      final result = await engine.start(selectedRoots.toList());
      lastResult = result;
      screen = AppScreen.results;
      // Deliberately does NOT auto-select anything for deletion here.
      // `keepFileFor` still computes a "keep" candidate per group on
      // demand for the UI's star indicator, but nothing is marked for
      // deletion until the user explicitly triggers Smart Select (or
      // taps individual files) - required flow is Scan -> review ->
      // explicit Smart Select -> review -> explicit delete confirmation,
      // never Scan -> [already selected for deletion].
    } catch (e) {
      // Without this, any exception here (a database error, a worker
      // isolate failing to spawn, disk I/O failure while writing the
      // cache, etc.) would propagate uncaught out of this async callback
      // and leave the UI stuck on the Scanning screen forever - the user
      // would have no way to recover except restarting the app.
      lastError = 'Scan failed: $e';
      _log.warning('Scan failed: $e');
      screen = AppScreen.home;
    } finally {
      _notify();
    }
  }

  void pauseScan() {
    scanEngine?.pause();
    _notify();
  }

  void resumeScan() {
    scanEngine?.resume();
    _notify();
  }

  Future<void> cancelScan() async {
    await scanEngine?.cancel();
  }

  void backToHome() {
    screen = AppScreen.home;
    lastResult = null;
    lastProgress = null;
    scanEngine = null;
    _notify();
  }

  // --- Selection ---

  ScannedFile keepFileFor(DuplicateGroup group) {
    return _keepOverrides[group.fullHashHex] ??
        applySmartSelection(
          group,
          settings.defaultSelectionStrategy,
          protectedLocations,
        ).keep;
  }

  bool isSelectedForDeletion(ScannedFile file) =>
      _selectedForDeletion.contains(file.path);

  void setKeepFile(DuplicateGroup group, ScannedFile file) {
    _keepOverrides[group.fullHashHex] = file;
    _selectedForDeletion.remove(file.path);
    for (final f in group.files) {
      if (f != file) _selectedForDeletion.add(f.path);
    }
    _notify();
  }

  void toggleFileSelected(ScannedFile file, ScannedFile keep) {
    if (file == keep) return; // never allow selecting the kept file
    if (!_selectedForDeletion.remove(file.path)) {
      _selectedForDeletion.add(file.path);
    }
    _notify();
  }

  void applyStrategyToAllGroups(SmartSelectionStrategy strategy) {
    final groups = lastResult?.groups ?? const [];
    for (final group in groups) {
      final result = applySmartSelection(group, strategy, protectedLocations);
      _keepOverrides[group.fullHashHex] = result.keep;
      for (final f in group.files) {
        if (f == result.keep) {
          _selectedForDeletion.remove(f.path);
        } else if (result.selectedForDeletion.contains(f)) {
          _selectedForDeletion.add(f.path);
        } else {
          _selectedForDeletion.remove(f.path);
        }
      }
    }
    _notify();
  }

  int get selectedCount => _selectedForDeletion.length;

  int get selectedBytes {
    final groups = lastResult?.groups ?? const [];
    var total = 0;
    for (final group in groups) {
      for (final f in group.files) {
        if (_selectedForDeletion.contains(f.path)) total += f.size;
      }
    }
    return total;
  }

  /// Deletes every file currently marked for deletion, one at a time
  /// (never concurrently - see [SafeDeleteCoordinator], which is itself
  /// re-entrancy-safe per path, but a bounded/sequential batch here also
  /// keeps this app from ever opening hundreds of simultaneous native
  /// delete operations against the shell). A single file's failure never
  /// aborts the batch: every file gets its own [DeleteResult] and the loop
  /// always continues to the next one.
  Future<List<DeleteResult>> deleteSelected() async {
    if (isDeleting) return const []; // already running; refuse re-entry
    isDeleting = true;
    _notify();

    final results = <DeleteResult>[];
    try {
      final groups = lastResult?.groups ?? const [];
      final toDelete = <ScannedFile>[];
      final keepByPath = <String, ScannedFile>{};
      for (final group in groups) {
        final keep = keepFileFor(group);
        for (final f in group.files) {
          keepByPath[f.path] = keep;
          if (_selectedForDeletion.contains(f.path)) toDelete.add(f);
        }
      }

      for (final file in toDelete) {
        final result = await deleteCoordinator.delete(
          file,
          mustNotEqual: keepByPath[file.path],
        );
        results.add(result);
        if (result.succeeded) _selectedForDeletion.remove(file.path);
      }
      return results;
    } finally {
      isDeleting = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_progressSubscription?.cancel());
    // A scan still in flight has no listener left to report to once this
    // controller is gone; cancel its worker isolates/native hashing rather
    // than letting them keep running in the background until the process
    // exits on its own.
    unawaited(scanEngine?.cancel());
    scanEngine?.dispose();
    unawaited(_db?.close());
    super.dispose();
  }
}
