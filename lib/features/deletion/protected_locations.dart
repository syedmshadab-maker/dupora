import 'dart:io';

import 'package:path/path.dart' as p;

/// Guards against deleting files inside operating system, application, or
/// user-designated protected directories.
///
/// Deliberately conservative but not so aggressive that ordinary user
/// folders (Documents, Downloads, Pictures, a random project directory)
/// become uncleanable: only well-known system/app roots are protected by
/// default, plus whatever the user adds in Settings.
class ProtectedLocations {
  ProtectedLocations({List<String>? userDefined})
    : _roots = {
        ..._defaultRootsForPlatform(),
        ...?userDefined?.map(_normalize),
      };

  final Set<String> _roots;

  void add(String path) => _roots.add(_normalize(path));

  void remove(String path) => _roots.remove(_normalize(path));

  List<String> get roots => List.unmodifiable(_roots);

  bool isProtected(String path) {
    final normalized = _normalize(path);
    for (final root in _roots) {
      if (_isWithin(normalized, root)) return true;
    }
    return false;
  }

  static String _normalize(String path) {
    var normalized = p.normalize(path);
    if (Platform.isWindows) normalized = normalized.toLowerCase();
    return normalized;
  }

  static bool _isWithin(String path, String root) {
    if (path == root) return true;
    final withSep = root.endsWith(p.separator) ? root : '$root${p.separator}';
    return path.startsWith(withSep);
  }

  static Set<String> _defaultRootsForPlatform() {
    if (Platform.isWindows) {
      final systemRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';
      final programFiles =
          Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
      final programFilesX86 =
          Platform.environment['ProgramFiles(x86)'] ??
          r'C:\Program Files (x86)';
      final programData =
          Platform.environment['ProgramData'] ?? r'C:\ProgramData';
      final localAppData = Platform.environment['LOCALAPPDATA'];
      final roots = <String>{
        systemRoot,
        programFiles,
        programFilesX86,
        programData,
        r'C:\$Recycle.Bin',
        r'C:\System Volume Information',
      };
      if (localAppData != null) {
        roots.add(p.join(localAppData, 'Dupora'));
      }
      return roots.map(_normalize).toSet();
    }
    if (Platform.isMacOS) {
      return {
        '/System',
        '/Library',
        '/private',
        '/bin',
        '/sbin',
        '/usr',
        '/Applications',
      }.map(_normalize).toSet();
    }
    if (Platform.isLinux) {
      return {
        '/bin',
        '/boot',
        '/etc',
        '/lib',
        '/lib64',
        '/proc',
        '/sys',
        '/sbin',
        '/usr',
        '/var/lib',
      }.map(_normalize).toSet();
    }
    if (Platform.isAndroid) {
      return {
        '/system',
        '/data/system',
        '/data/app',
        '/vendor',
      }.map(_normalize).toSet();
    }
    return {};
  }
}
