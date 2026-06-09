import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'package:shared_preferences/shared_preferences.dart';

import '../utils/cast_helpers.dart';
import '../utils/platform_paths.dart';
import '../../features/cloud_sync/sync_repo_interfaces.dart';

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
    if (prefs.getBool('gz_thumb_v3_migrated') == true) return;

    final thumbDir = Directory(p.join(baseDir, 'thumbnails'));
    if (await thumbDir.exists()) {
      await thumbDir.delete(recursive: true);
    }
    await prefs.setBool('gz_thumb_v3_migrated', true);
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
    final thumbnail = _resizeImage(imageBytes, 512);
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
    final thumbnail = _resizeImage(bytes, 512);
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
    if (File(relativePath).isAbsolute) return relativePath;
    return p.join(baseDir, relativePath);
  }

  Uint8List? _resizeImage(Uint8List imageBytes, int maxDimension) {
    try {
      final image = img.decodeImage(imageBytes);
      if (image == null) return null;
      final cropped = img.copyResizeCropSquare(image, size: maxDimension);
      return Uint8List.fromList(img.encodeJpg(cropped, quality: 90));
    } catch (_) {
      return null;
    }
  }

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
