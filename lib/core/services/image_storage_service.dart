import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../utils/cast_helpers.dart';
import '../utils/platform_paths.dart';
import '../../features/cloud_sync/sync_repo_interfaces.dart';

class ImageStorageService implements SyncImageStore {
  final String baseDir;

  ImageStorageService(this.baseDir);

  static Future<ImageStorageService> create() async {
    final baseDir = await getAppDataDir();
    return ImageStorageService(baseDir);
  }

  Future<String> saveAvatar(String characterId, Uint8List imageBytes) async {
    final dir = Directory(p.join(baseDir, 'avatars'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final path = p.join(dir.path, '$characterId.png');
    await File(path).writeAsBytes(imageBytes);
    await saveThumbnail(characterId, imageBytes);
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
    final thumbnail = _resizeImage(imageBytes, 150);
    if (thumbnail == null) return null;
    final path = p.join(dir.path, '$characterId.jpg');
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

  String? absolutePath(String? relativePath) {
    if (relativePath == null) return null;
    if (File(relativePath).isAbsolute) return relativePath;
    return p.join(baseDir, relativePath);
  }

  Uint8List? _resizeImage(Uint8List imageBytes, int maxDimension) {
    try {
      final image = img.decodeImage(imageBytes);
      if (image == null) return null;
      if (image.width <= maxDimension && image.height <= maxDimension) {
        return Uint8List.fromList(img.encodeJpg(image, quality: 80));
      }
      final resized = img.copyResize(
        image,
        width: maxDimension,
        height: maxDimension,
        maintainAspect: true,
      );
      return Uint8List.fromList(img.encodeJpg(resized, quality: 80));
    } catch (_) {
      return null;
    }
  }
}
