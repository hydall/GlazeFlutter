import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class FileExportService {
  static Future<String> export({
    required String data,
    required String filename,
    required String subfolder,
  }) async {
    if (Platform.isWindows || Platform.isLinux) {
      return _saveWithPicker(data: data, filename: filename);
    }
    if (Platform.isAndroid) {
      return _saveToDownloads(data, filename, subfolder);
    }
    if (Platform.isMacOS) {
      return _saveToMacDownloads(data, filename, subfolder);
    }
    return _share(data, filename);
  }

  static Future<String> exportFile({
    required String sourcePath,
    required String filename,
    required String subfolder,
  }) async {
    if (Platform.isWindows || Platform.isLinux) {
      return _copyWithPicker(sourcePath: sourcePath, filename: filename);
    }
    if (Platform.isAndroid) {
      return _copyToDownloads(sourcePath, filename, subfolder);
    }
    if (Platform.isMacOS) {
      return _copyToMacDownloads(sourcePath, filename, subfolder);
    }
    return _shareFile(sourcePath, filename);
  }

  static Future<String> exportBytes({
    required List<int> bytes,
    required String filename,
    required String subfolder,
  }) async {
    if (Platform.isWindows || Platform.isLinux) {
      return _saveBytesWithPicker(bytes: bytes, filename: filename);
    }
    if (Platform.isAndroid) {
      return _saveBytesToDownloads(bytes, filename, subfolder);
    }
    if (Platform.isMacOS) {
      return _saveBytesToMacDownloads(bytes, filename, subfolder);
    }
    return _shareBytes(bytes, filename);
  }

  static Future<String> _saveWithPicker({
    required String data,
    required String filename,
  }) async {
    final path = await FilePicker.saveFile(
      dialogTitle: 'Save $filename',
      fileName: filename,
      type: FileType.custom,
      allowedExtensions: [filename.split('.').last],
    );
    if (path == null) throw Exception('Save cancelled');
    final file = File(path);
    await file.writeAsString(data);
    return file.path;
  }

  static Future<String> _saveBytesWithPicker({
    required List<int> bytes,
    required String filename,
  }) async {
    final path = await FilePicker.saveFile(
      dialogTitle: 'Save $filename',
      fileName: filename,
      type: FileType.custom,
      allowedExtensions: [filename.split('.').last],
    );
    if (path == null) throw Exception('Save cancelled');
    final file = File(path);
    await file.writeAsBytes(bytes);
    return file.path;
  }

  /// Scoped-storage-safe Downloads/Glaze path on Android; null if unavailable.
  static Future<Directory?> _androidGlazeDir(String subfolder) async {
    try {
      var downloads = await getDownloadsDirectory();

      // path_provider may return null on some Android versions/OEMs.
      // Fall back to the well-known public Downloads path.
      downloads ??= Directory('/storage/emulated/0/Download');

      final dir = Directory('${downloads.path}/Glaze/$subfolder');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    } catch (_) {
      return null;
    }
  }

  static Future<String> _saveToDownloads(
      String data, String filename, String subfolder) async {
    final dir = await _androidGlazeDir(subfolder);
    if (dir != null) {
      try {
        final file = File('${dir.path}/$filename');
        await file.writeAsString(data);
        return file.path;
      } catch (_) {}
    }
    return _share(data, filename);
  }

  static Future<String> _saveBytesToDownloads(
      List<int> bytes, String filename, String subfolder) async {
    final dir = await _androidGlazeDir(subfolder);
    if (dir != null) {
      try {
        final file = File('${dir.path}/$filename');
        await file.writeAsBytes(bytes);
        return file.path;
      } catch (_) {}
    }
    return _shareBytes(bytes, filename);
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

  static Future<String> _copyWithPicker({
    required String sourcePath,
    required String filename,
  }) async {
    final path = await FilePicker.saveFile(
      dialogTitle: 'Save $filename',
      fileName: filename,
      type: FileType.custom,
      allowedExtensions: [filename.split('.').last],
    );
    if (path == null) throw Exception('Save cancelled');
    await File(sourcePath).copy(path);
    return path;
  }

  static Future<String> _copyToDownloads(
      String sourcePath, String filename, String subfolder) async {
    final dir = await _androidGlazeDir(subfolder);
    if (dir != null) {
      try {
        final destPath = '${dir.path}/$filename';
        await File(sourcePath).copy(destPath);
        return destPath;
      } catch (_) {}
    }
    return _shareFile(sourcePath, filename);
  }

  static Future<String> _copyToMacDownloads(
      String sourcePath, String filename, String subfolder) async {
    final downloads = await getDownloadsDirectory();
    final dir = Directory('${downloads?.path ?? '~/Downloads'}/Glaze/$subfolder');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final destPath = '${dir.path}/$filename';
    await File(sourcePath).copy(destPath);
    return destPath;
  }

  static Future<String> _shareFile(String sourcePath, String filename) async {
    await Share.shareXFiles([XFile(sourcePath)]);
    return sourcePath;
  }
}
