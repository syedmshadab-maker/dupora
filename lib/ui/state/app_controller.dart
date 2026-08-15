import 'package:flutter/foundation.dart';

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
    }
    notifyListeners();
  }

  void clearError() {
    lastError = null;
    notifyListeners();
  }

  void toggleRootSelected(String path) {
    if (!selectedRoots.remove(path)) selectedRoots.add(path);
    notifyListeners();
  }

  void addCustomFolder(String path) {
    if (!customFolders.contains(path)) customFolders.add(path);
    selectedRoots.add(path);
    notifyListeners();
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
    notifyListeners();
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
    notifyListeners();

    final engine = ScanEngine(cache: cacheRepo, settings: settings);
    scanEngine = engine;
    engine.progressStream.listen((p) {
      lastProgress = p;
      notifyListeners();
    });

    try {
      final result = await engine.start(selectedRoots.toList());
      lastResult = result;
      screen = AppScreen.results;
      _applyDefaultSelection();
    } catch (e) {
      // Without this, any exception here (a database error, a worker
      // isolate failing to spawn, disk I/O failure while writing the
      // cache, etc.) would propagate uncaught out of this async callback
      // and leave the UI stuck on the Scanning screen forever - the user
      // would have no way to recover except restarting the app.
      lastError = 'Scan failed: $e';
      screen = AppScreen.home;
    } finally {
      notifyListeners();
    }
  }

  void pauseScan() {
    scanEngine?.pause();
    notifyListeners();
  }

  void resumeScan() {
    scanEngine?.resume();
    notifyListeners();
  }

  Future<void> cancelScan() async {
    await scanEngine?.cancel();
  }

  void backToHome() {
    screen = AppScreen.home;
    lastResult = null;
    lastProgress = null;
    scanEngine = null;
    notifyListeners();
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
    notifyListeners();
  }

  void toggleFileSelected(ScannedFile file, ScannedFile keep) {
    if (file == keep) return; // never allow selecting the kept file
    if (!_selectedForDeletion.remove(file.path)) {
      _selectedForDeletion.add(file.path);
    }
    notifyListeners();
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
    notifyListeners();
  }

  void _applyDefaultSelection() =>
      applyStrategyToAllGroups(settings.defaultSelectionStrategy);

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

  Future<List<DeleteResult>> deleteSelected() async {
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

    final results = <DeleteResult>[];
    for (final file in toDelete) {
      final result = await deleteCoordinator.delete(
        file,
        mustNotEqual: keepByPath[file.path],
      );
      results.add(result);
      if (result.succeeded) _selectedForDeletion.remove(file.path);
    }
    notifyListeners();
    return results;
  }

  @override
  void dispose() {
    scanEngine?.dispose();
    _db?.close();
    super.dispose();
  }
}
