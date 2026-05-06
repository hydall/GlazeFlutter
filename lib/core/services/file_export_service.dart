import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class FileExportService {
  static Future<String> export({
    required String data,
    required String filename,
    required String subfolder,
  }) async {
    if (Platform.isAndroid) {
      return _saveToDownloads(data, filename, subfolder);
    }
    if (Platform.isMacOS) {
      return _saveToMacDownloads(data, filename, subfolder);
    }
    return _share(data, filename);
  }

  static Future<String> exportBytes({
    required List<int> bytes,
    required String filename,
    required String subfolder,
  }) async {
    if (Platform.isAndroid) {
      return _saveBytesToDownloads(bytes, filename, subfolder);
    }
    if (Platform.isMacOS) {
      return _saveBytesToMacDownloads(bytes, filename, subfolder);
    }
    return _shareBytes(bytes, filename);
  }

  static Future<String> _saveToDownloads(
      String data, String filename, String subfolder) async {
    final dir = Directory('/storage/emulated/0/Download/Glaze/$subfolder');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File('${dir.path}/$filename');
    await file.writeAsString(data);
    return file.path;
  }

  static Future<String> _saveBytesToDownloads(
      List<int> bytes, String filename, String subfolder) async {
    final dir = Directory('/storage/emulated/0/Download/Glaze/$subfolder');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  static Future<String> _saveToMacDownloads(
      String data, String filename, String subfolder) async {
    final downloads = await getDownloadsDirectory();
    final dir = Directory('${downloads?.path ?? '~/Downloads'}/Glaze/$subfolder');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File('${dir.path}/$filename');
    await file.writeAsString(data);
    return file.path;
  }

  static Future<String> _saveBytesToMacDownloads(
      List<int> bytes, String filename, String subfolder) async {
    final downloads = await getDownloadsDirectory();
    final dir = Directory('${downloads?.path ?? '~/Downloads'}/Glaze/$subfolder');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  static Future<String> _share(String data, String filename) async {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$filename');
    await file.writeAsString(data);
    await Share.shareXFiles([XFile(file.path)]);
    return file.path;
  }

  static Future<String> _shareBytes(
      List<int> bytes, String filename) async {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$filename');
    await file.writeAsBytes(bytes);
    await Share.shareXFiles([XFile(file.path)]);
    return file.path;
  }
}
