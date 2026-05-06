import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../utils/platform_paths.dart';

class ImageStorageService {
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
    return path;
  }

  Future<String?> saveAvatarFromDataUrl(
      String characterId, String dataUrl) async {
    final bytes = _dataUrlToBytes(dataUrl);
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

  Uint8List? _dataUrlToBytes(String dataUrl) {
    final commaIndex = dataUrl.indexOf(',');
    if (commaIndex == -1) return null;
    final base64Str = dataUrl.substring(commaIndex + 1);
    try {
      return Uint8List.fromList(Uri.parse('data:;base64,$base64Str').data!.contentAsBytes());
    } catch (_) {
      return null;
    }
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
