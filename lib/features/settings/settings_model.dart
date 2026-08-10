import 'package:meta/meta.dart';

import '../duplicates/domain/selection_strategy.dart';

@immutable
class DuporaSettings {
  const DuporaSettings({
    this.scanHiddenFiles = false,
    this.scanSystemFiles = false,
    this.followSymlinks = false,
    this.maxConcurrency = 0, // 0 = auto (native logical core count, clamped)
    this.thumbnailCacheMaxBytes = 512 * 1024 * 1024,
    this.confirmBeforeDelete = true,
    this.useTrash = true,
    this.defaultSelectionStrategy = SmartSelectionStrategy.keepOldest,
    this.userProtectedLocations = const [],
    this.themeMode = DuporaThemeMode.system,
  });

  final bool scanHiddenFiles;
  final bool scanSystemFiles;
  final bool followSymlinks;
  final int maxConcurrency;
  final int thumbnailCacheMaxBytes;
  final bool confirmBeforeDelete;
  final bool useTrash;
  final SmartSelectionStrategy defaultSelectionStrategy;
  final List<String> userProtectedLocations;
  final DuporaThemeMode themeMode;

  DuporaSettings copyWith({
    bool? scanHiddenFiles,
    bool? scanSystemFiles,
    bool? followSymlinks,
    int? maxConcurrency,
    int? thumbnailCacheMaxBytes,
    bool? confirmBeforeDelete,
    bool? useTrash,
    SmartSelectionStrategy? defaultSelectionStrategy,
    List<String>? userProtectedLocations,
    DuporaThemeMode? themeMode,
  }) {
    return DuporaSettings(
      scanHiddenFiles: scanHiddenFiles ?? this.scanHiddenFiles,
      scanSystemFiles: scanSystemFiles ?? this.scanSystemFiles,
      followSymlinks: followSymlinks ?? this.followSymlinks,
      maxConcurrency: maxConcurrency ?? this.maxConcurrency,
      thumbnailCacheMaxBytes: thumbnailCacheMaxBytes ?? this.thumbnailCacheMaxBytes,
      confirmBeforeDelete: confirmBeforeDelete ?? this.confirmBeforeDelete,
      useTrash: useTrash ?? this.useTrash,
      defaultSelectionStrategy: defaultSelectionStrategy ?? this.defaultSelectionStrategy,
      userProtectedLocations: userProtectedLocations ?? this.userProtectedLocations,
      themeMode: themeMode ?? this.themeMode,
    );
  }

  Map<String, Object?> toJson() => {
        'scanHiddenFiles': scanHiddenFiles,
        'scanSystemFiles': scanSystemFiles,
        'followSymlinks': followSymlinks,
        'maxConcurrency': maxConcurrency,
        'thumbnailCacheMaxBytes': thumbnailCacheMaxBytes,
        'confirmBeforeDelete': confirmBeforeDelete,
        'useTrash': useTrash,
        'defaultSelectionStrategy': defaultSelectionStrategy.name,
        'userProtectedLocations': userProtectedLocations,
        'themeMode': themeMode.name,
      };

  factory DuporaSettings.fromJson(Map<String, Object?> json) {
    return DuporaSettings(
      scanHiddenFiles: json['scanHiddenFiles'] as bool? ?? false,
      scanSystemFiles: json['scanSystemFiles'] as bool? ?? false,
      followSymlinks: json['followSymlinks'] as bool? ?? false,
      maxConcurrency: json['maxConcurrency'] as int? ?? 0,
      thumbnailCacheMaxBytes: json['thumbnailCacheMaxBytes'] as int? ?? 512 * 1024 * 1024,
      confirmBeforeDelete: json['confirmBeforeDelete'] as bool? ?? true,
      useTrash: json['useTrash'] as bool? ?? true,
      defaultSelectionStrategy: SmartSelectionStrategy.values.firstWhere(
        (s) => s.name == json['defaultSelectionStrategy'],
        orElse: () => SmartSelectionStrategy.keepOldest,
      ),
      userProtectedLocations: (json['userProtectedLocations'] as List?)?.cast<String>() ?? const [],
      themeMode: DuporaThemeMode.values.firstWhere(
        (m) => m.name == json['themeMode'],
        orElse: () => DuporaThemeMode.system,
      ),
    );
  }
}

enum DuporaThemeMode { system, light, dark }
