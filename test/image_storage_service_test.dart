import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'package:glaze_flutter/core/services/image_storage_service.dart';

Uint8List makePng(int width, int height) {
  final image = img.Image(width: width, height: height);
  for (final p in image) {
    p.r = 255;
    p.g = 100;
    p.b = 50;
    p.a = 255;
  }
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  late Directory tmpDir;
  late ImageStorageService service;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('glaze_image_test_');
    service = ImageStorageService(tmpDir.path);
  });

  tearDown(() async {
    if (await tmpDir.exists()) {
      await tmpDir.delete(recursive: true);
    }
  });

  test('saveAvatar creates avatar PNG and thumbnail JPG', () async {
    final png = makePng(400, 400);
    final path = await service.saveAvatar('char1', png);

    expect(path, endsWith('char1.png'));
    expect(await File(path).exists(), isTrue);

    final thumbPath = p.join(tmpDir.path, 'thumbnails', 'char1.jpg');
    expect(await File(thumbPath).exists(), isTrue);
  });

  test('thumbnailPath returns thumbnail when it exists', () async {
    final png = makePng(200, 200);
    final avatarPath = await service.saveAvatar('c1', png);

    final result = service.thumbnailPath(avatarPath);
    expect(result, isNotNull);
    expect(result, endsWith('c1.jpg'));
  });

  test('thumbnailPath returns null when avatarPath is null', () {
    expect(service.thumbnailPath(null), isNull);
  });

  test('thumbnailPath returns null when avatarPath is empty', () {
    expect(service.thumbnailPath(''), isNull);
  });

  test('thumbnailPath returns null when thumbnail does not exist', () async {
    final avatarPath = p.join(tmpDir.path, 'avatars', 'missing.png');
    expect(service.thumbnailPath(avatarPath), isNull);
  });

  test('deleteAvatar removes avatar and thumbnail', () async {
    final png = makePng(100, 100);
    final avatarPath = await service.saveAvatar('del1', png);
    expect(await File(avatarPath).exists(), isTrue);

    await service.deleteAvatar('del1');

    expect(await File(avatarPath).exists(), isFalse);
    final thumbPath = p.join(tmpDir.path, 'thumbnails', 'del1.jpg');
    expect(await File(thumbPath).exists(), isFalse);
  });

  test('deleteAvatar does not throw when files do not exist', () async {
    await service.deleteAvatar('nonexistent');
  });

  test('saveAvatarFromDataUrl decodes base64 and saves', () async {
    final png = makePng(50, 50);
    final base64Str = Uri.encodeComponent(png.toList().toString());
    final dataUrl = 'data:image/png;base64,${Uri.encodeComponent(png.map((b) => b.toRadixString(16).padLeft(2, '0')).join())}';

    final simplePng = makePng(50, 50);
    final b64 = base64Encode(simplePng);
    final dataUrl2 = 'data:image/png;base64,$b64';

    final result = await service.saveAvatarFromDataUrl('data1', dataUrl2);
    expect(result, isNotNull);
    expect(await File(result!).exists(), isTrue);
  });

  test('saveAvatarFromDataUrl returns null for invalid data URL', () async {
    final result = await service.saveAvatarFromDataUrl('bad', 'not-a-data-url');
    expect(result, isNull);
  });

  test('saveBytes creates file in subfolder', () async {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final path = await service.saveBytes(bytes, 'gallery', 'img1', 'jpg');

    expect(path, contains('gallery'));
    expect(path, endsWith('img1.jpg'));
    expect(await File(path).exists(), isTrue);
    expect(await File(path).readAsBytes(), equals(bytes));
  });

  test('absolutePath returns absolute path unchanged', () async {
    final abs = p.join(tmpDir.path, 'avatars', 'x.png');
    expect(service.absolutePath(abs), equals(abs));
  });

  test('absolutePath returns null for null input', () {
    expect(service.absolutePath(null), isNull);
  });

  test('absolutePath joins with baseDir for relative path', () {
    final result = service.absolutePath('avatars/char1.png');
    expect(
      p.canonicalize(result!),
      equals(p.canonicalize(p.join(tmpDir.path, 'avatars', 'char1.png'))),
    );
  });

  test('thumbnail is smaller than avatar for large images', () async {
    final png = makePng(800, 800);
    final avatarPath = await service.saveAvatar('big1', png);
    final thumbPath = service.thumbnailPath(avatarPath);

    expect(thumbPath, isNotNull);
    final avatarBytes = await File(avatarPath).readAsBytes();
    final thumbBytes = await File(thumbPath!).readAsBytes();
    expect(thumbBytes.length, lessThan(avatarBytes.length));
  });

  test('thumbnail for small image is still created', () async {
    final png = makePng(50, 50);
    final avatarPath = await service.saveAvatar('small1', png);
    final thumbPath = service.thumbnailPath(avatarPath);
    expect(thumbPath, isNotNull);
    expect(await File(thumbPath!).exists(), isTrue);
  });
}

String base64Encode(Uint8List bytes) {
  const chars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  final buf = StringBuffer();
  for (var i = 0; i < bytes.length; i += 3) {
    final b0 = bytes[i];
    final b1 = i + 1 < bytes.length ? bytes[i + 1] : 0;
    final b2 = i + 2 < bytes.length ? bytes[i + 2] : 0;
    buf.write(chars[(b0 >> 2) & 0x3F]);
    buf.write(chars[((b0 << 4) | (b1 >> 4)) & 0x3F]);
    buf.write(i + 1 < bytes.length ? chars[((b1 << 2) | (b2 >> 6)) & 0x3F] : '=');
    buf.write(i + 2 < bytes.length ? chars[b2 & 0x3F] : '=');
  }
  return buf.toString();
}
