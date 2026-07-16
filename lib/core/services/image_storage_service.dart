import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'package:shared_preferences/shared_preferences.dart';

import '../utils/cast_helpers.dart';
import '../utils/platform_paths.dart';
import '../../features/cloud_sync/sync_repo_interfaces.dart';

/// Longest-side (px) of the pre-generated list/card thumbnails. Bumped from the
/// old 512²-square crop to a larger, aspect-preserving box so grid and card
/// portraits stay crisp on high-DPI screens instead of reading upscaled/"шакал".
/// Changing this must be paired with a bump of the thumbnail migration key (see
/// [_kThumbMigrationKey]) so stale thumbnails are regenerated.
const int kThumbnailMaxDimension = 768;

/// JPEG quality for the generated thumbnails.
const int _kThumbnailQuality = 92;

/// SharedPreferences flag: once set, the old square thumbnails have been wiped.
/// Bumping the version (v3 → v4 …) forces a one-time re-clear so a new
/// [kThumbnailMaxDimension] takes effect for existing libraries. Pair with
/// [_kThumbBackfillKey] so the wiped thumbnails are regenerated in the
/// background.
const String _kThumbMigrationKey = 'gz_thumb_v4_migrated';

/// SharedPreferences flag guarding the one-time background thumbnail backfill.
const String _kThumbBackfillKey = 'gz_thumb_v4_backfilled';

/// Runs in a background isolate: decodes [imageBytes], scales it so its longest
/// side is at most [maxDimension] (never upscaling), and re-encodes as JPEG.
/// Kept top-level (not an instance method) so it is safely sendable to
/// [Isolate.run] — capturing `this` would not be.
Uint8List? resizeAvatarBytes(Uint8List imageBytes, int maxDimension) {
  try {
    final image = img.decodeImage(imageBytes);
    if (image == null) return null;
    // Preserve aspect ratio: constrain only the longer axis so portrait avatars
    // keep their full height (the old square crop threw half of it away).
    final img.Image scaled;
    if (image.width >= image.height) {
      scaled = image.width > maxDimension
          ? img.copyResize(image, width: maxDimension)
          : image;
    } else {
      scaled = image.height > maxDimension
          ? img.copyResize(image, height: maxDimension)
          : image;
    }
    return Uint8List.fromList(img.encodeJpg(scaled, quality: _kThumbnailQuality));
  } catch (_) {
    return null;
  }
}

class ImageStorageService implements SyncImageStore {
  final String baseDir;

  ImageStorageService(this.baseDir);

  static Future<ImageStorageService> create() async {
    final baseDir = await getAppDataDir();
    final service = ImageStorageService(baseDir);
    await service._migrateOldThumbnails();
    return service;
  }

  Future<void> _migrateOldThumbnails([SharedPreferences? prefsArg]) async {
    final prefs = prefsArg ?? await SharedPreferences.getInstance();
    if (prefs.getBool(_kThumbMigrationKey) == true) return;

    final thumbDir = Directory(p.join(baseDir, 'thumbnails'));
    if (await thumbDir.exists()) {
      await thumbDir.delete(recursive: true);
    }
    await prefs.setBool(_kThumbMigrationKey, true);
    // The wipe leaves existing characters without thumbnails until they are
    // re-saved; clear the backfill flag so the next [backfillMissingThumbnails]
    // pass regenerates them at the new resolution.
    await prefs.setBool(_kThumbBackfillKey, false);
  }

  /// One-time background pass that regenerates thumbnails for any [avatarPaths]
  /// that lost theirs to the resolution bump wipe. Decoding is offloaded to a
  /// short-lived isolate per image so the UI stays smooth; the whole pass is
  /// guarded by a SharedPreferences flag so it only runs once per bump.
  ///
  /// Returns the number of thumbnails (re)generated.
  Future<int> backfillMissingThumbnails(Iterable<String?> avatarPaths) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kThumbBackfillKey) == true) return 0;

    final dir = Directory(p.join(baseDir, 'thumbnails'));
    if (!await dir.exists()) await dir.create(recursive: true);

    var made = 0;
    for (final avatarPath in avatarPaths) {
      if (avatarPath == null || avatarPath.isEmpty) continue;
      if (thumbnailPath(avatarPath) != null) continue; // already has one

      final resolvedPath = absolutePath(avatarPath) ?? avatarPath;
      final avatarFile = File(resolvedPath);
      if (!await avatarFile.exists()) continue;

      try {
        final bytes = await avatarFile.readAsBytes();
        final thumbnail = await Isolate.run(
          () => resizeAvatarBytes(bytes, kThumbnailMaxDimension),
        );
        if (thumbnail == null) continue;
        final name = p.basenameWithoutExtension(resolvedPath);
        await File(p.join(dir.path, '$name.jpg')).writeAsBytes(thumbnail);
        made++;
      } catch (_) {
        // Skip this one; the full-res fallback still renders it correctly.
      }
    }

    await prefs.setBool(_kThumbBackfillKey, true);
    return made;
  }

  Future<String> saveAvatar(String characterId, Uint8List imageBytes) async {
    final dir = Directory(p.join(baseDir, 'avatars'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final cleanBytes = _stripPngTextChunks(imageBytes);
    final path = p.join(dir.path, '$characterId.png');
    await File(path).writeAsBytes(cleanBytes);
    await saveThumbnail(characterId, cleanBytes);
    return path;
  }

  Future<String?> saveAvatarFromDataUrl(
      String characterId, String dataUrl) async {
    final bytes = dataUrlToBytes(dataUrl);
    if (bytes == null) return null;
    return saveAvatar(characterId, bytes);
  }

  Future<String?> saveThumbnail(
      String characterId, Uint8List imageBytes) async {
    final dir = Directory(p.join(baseDir, 'thumbnails'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final thumbnail = _resizeImage(imageBytes, kThumbnailMaxDimension);
    if (thumbnail == null) return null;
    final path = p.join(dir.path, '$characterId.jpg');
    await File(path).writeAsBytes(thumbnail);
    return path;
  }

  Future<String?> ensureThumbnailForAvatarPath(String? avatarPath) async {
    if (avatarPath == null || avatarPath.isEmpty) return null;
    final resolvedPath = absolutePath(avatarPath) ?? avatarPath;
    final avatarFile = File(resolvedPath);
    if (!await avatarFile.exists()) return null;

    final bytes = await avatarFile.readAsBytes();
    final thumbnail = _resizeImage(bytes, kThumbnailMaxDimension);
    if (thumbnail == null) return null;

    final dir = Directory(p.join(baseDir, 'thumbnails'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final name = p.basenameWithoutExtension(resolvedPath);
    final path = p.join(dir.path, '$name.jpg');
    await File(path).writeAsBytes(thumbnail);
    return path;
  }

  Future<void> deleteAvatar(String characterId) async {
    final avatarPath = p.join(baseDir, 'avatars', '$characterId.png');
    final file = File(avatarPath);
    if (await file.exists()) await file.delete();
    final thumbPath = p.join(baseDir, 'thumbnails', '$characterId.jpg');
    final thumbFile = File(thumbPath);
    if (await thumbFile.exists()) await thumbFile.delete();
  }

  String? thumbnailPath(String? avatarPath) {
    if (avatarPath == null || avatarPath.isEmpty) return null;
    final name = p.basenameWithoutExtension(avatarPath);
    final thumb = p.join(baseDir, 'thumbnails', '$name.jpg');
    return File(thumb).existsSync() ? thumb : null;
  }

  @override
  Future<String> saveBytes(
    Uint8List bytes,
    String subfolder,
    String filename,
    String ext,
  ) async {
    final dir = Directory(p.join(baseDir, subfolder));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final path = p.join(dir.path, '$filename.$ext');
    await File(path).writeAsBytes(bytes);
    return path;
  }

  @override
  String? absolutePath(String? relativePath) {
    if (relativePath == null) return null;
    if (relativePath.isEmpty) return relativePath;
    if (!File(relativePath).isAbsolute) {
      return p.join(baseDir, relativePath);
    }
    // The path is absolute. On iOS the app sandbox container UUID changes on
    // every reinstall/OS update, so an absolute path persisted by an older
    // build (e.g. .../Application/<OLD_UUID>/Documents/Glaze/avatars/x.png)
    // no longer exists under the current container. The files themselves are
    // preserved under the *new* container, so rebase any absolute path that
    // lives under a "Glaze" data root onto the current [baseDir].
    final rebased = _rebaseOntoBaseDir(relativePath);
    return rebased ?? relativePath;
  }

  /// If [absPath] points inside a Glaze data directory from a stale sandbox
  /// container, return the equivalent path under the current [baseDir].
  /// Returns null when the path can't be rebased (not under a Glaze root) or
  /// already resolves correctly.
  String? _rebaseOntoBaseDir(String absPath) {
    if (File(absPath).existsSync()) return absPath; // already valid

    final normalized = absPath.replaceAll('\\', '/');
    // Find the last "/Glaze/" segment — everything after it is the stable
    // sub-path (avatars/<id>.png, gallery/..., etc.).
    const marker = '/Glaze/';
    final idx = normalized.lastIndexOf(marker);
    if (idx < 0) return null;
    final suffix = normalized.substring(idx + marker.length);
    if (suffix.isEmpty) return null;
    return p.join(baseDir, suffix);
  }

  Uint8List? _resizeImage(Uint8List imageBytes, int maxDimension) =>
      resizeAvatarBytes(imageBytes, maxDimension);

  Uint8List _stripPngTextChunks(Uint8List pngBytes) {
    if (pngBytes.length < 8) return pngBytes;
    final sig = <int>[137, 80, 78, 71, 13, 10, 26, 10];
    for (int i = 0; i < 8; i++) {
      if (pngBytes[i] != sig[i]) return pngBytes;
    }
    final data = ByteData.sublistView(pngBytes);
    final out = BytesBuilder();
    out.add(pngBytes.sublist(0, 8));
    int offset = 8;
    bool stripped = false;
    while (offset < pngBytes.length - 4) {
      final length = data.getUint32(offset, Endian.big);
      final type = String.fromCharCodes(pngBytes.sublist(offset + 4, offset + 8));
      if (type == 'tEXt' || type == 'zTXt' || type == 'iTXt') {
        stripped = true;
        offset += 12 + length;
        continue;
      }
      out.add(pngBytes.sublist(offset, offset + 12 + length));
      offset += 12 + length;
      if (type == 'IEND') break;
    }
    return stripped ? out.toBytes() : pngBytes;
  }
}
