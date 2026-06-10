import 'dart:io';
import 'package:path/path.dart' as p;
// Pinned via dependency_overrides to keep Windows builds green; see docs/BUILD_NOTES.md.
// ignore: depend_on_referenced_packages
import 'package:path_provider/path_provider.dart';

/// Cached Glaze data root, populated on the first [getAppDataDir] call (which
/// happens at startup via ImageStorageService.create / AppDatabase open).
/// Used by [resolveGlazeFilePath] so widgets can rebase stale absolute paths
/// without an async lookup.
String? _cachedAppDataDir;

String? get cachedAppDataDir => _cachedAppDataDir;

Future<String> getAppDataDir() async {
  if (Platform.isAndroid || Platform.isIOS) {
    final dir = await getApplicationDocumentsDirectory();
    final base = p.join(dir.path, 'Glaze');
    _cachedAppDataDir = base;
    return base;
  }
  final base = _desktopDataDir();
  _cachedAppDataDir = base;
  return base;
}

/// Resolves a stored avatar/gallery/etc. path for display.
///
/// iOS changes the app sandbox container UUID on every reinstall/OS update, so
/// absolute paths persisted by an older build (e.g.
/// `.../Application/<OLD_UUID>/Documents/Glaze/avatars/x.png`) stop existing
/// even though the files survive under the *new* container. This rebases any
/// absolute path that lives under a `Glaze` data root onto the current
/// [cachedAppDataDir]. Relative paths are joined onto the current base. When no
/// base is cached yet (very early startup) the input is returned unchanged.
String? resolveGlazeFilePath(String? path) {
  if (path == null || path.isEmpty) return path;
  final base = _cachedAppDataDir;
  if (base == null) return path;

  if (!p.isAbsolute(path)) {
    return p.join(base, path);
  }
  // Absolute: if it already exists, keep it. Otherwise try to rebase onto the
  // current base by the last "/Glaze/" marker.
  if (File(path).existsSync()) return path;

  final normalized = path.replaceAll('\\', '/');
  const marker = '/Glaze/';
  final idx = normalized.lastIndexOf(marker);
  if (idx < 0) return path;
  final suffix = normalized.substring(idx + marker.length);
  if (suffix.isEmpty) return path;
  return p.join(base, suffix);
}

String _desktopDataDir() {
  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA']!;
    return p.join(appData, 'Glaze');
  } else if (Platform.isLinux) {
    final xdg = Platform.environment['XDG_DATA_HOME'] ??
        p.join(Platform.environment['HOME']!, '.local', 'share');
    return p.join(xdg, 'Glaze');
  } else if (Platform.isMacOS) {
    return p.join(Platform.environment['HOME']!, 'Library',
        'Application Support', 'Glaze');
  }
  throw UnsupportedError('Platform not supported yet');
}
