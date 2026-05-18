import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../db/app_db.dart';
import '../file_export_service.dart';
import '../image_storage_service.dart';

class BackupExporter {
  final AppDatabase _db;
  final ImageStorageService _imageStorage;

  BackupExporter(this._db, this._imageStorage);

  Future<String> export() async {
    final now = DateTime.now();
    final filename =
        'Glaze_backup_${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}.glz';

    final tempFile = File('${Directory.systemTemp.path}/$filename');
    final sink = tempFile.openWrite();

    try {
      await _writeJsonTo(sink);
      await sink.close();
      final bytes = await tempFile.readAsBytes();
      try {
        await tempFile.delete();
      } catch (_) {}
      return FileExportService.exportBytes(
        bytes: bytes,
        filename: filename,
        subfolder: 'backup',
      );
    } catch (e) {
      await sink.close();
      try {
        await tempFile.delete();
      } catch (_) {}
      rethrow;
    }
  }

  Future<String> exportToString() async {
    final tempFile = File(
        '${Directory.systemTemp.path}/glaze_export_${DateTime.now().millisecondsSinceEpoch}.glz');
    final sink = tempFile.openWrite();

    try {
      await _writeJsonTo(sink);
      await sink.close();
      final result = await tempFile.readAsString();
      try {
        await tempFile.delete();
      } catch (_) {}
      return result;
    } catch (e) {
      await sink.close();
      try {
        await tempFile.delete();
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> _writeJsonTo(IOSink sink) async {
    final tables = await _readAllTables();

    final prefs = await SharedPreferences.getInstance();
    final prefsMap = <String, dynamic>{};
    for (final key in prefs.getKeys()) {
      final value = prefs.get(key);
      if (value != null) prefsMap[key] = value;
    }

    final charRows = tables['characters'] as List<dynamic>?;

    sink.write('{');
    sink.write('"_isGlazeBackup":true,');
    sink.write('"_glazeVersion":1,');
    sink.write('"_source":"flutter",');
    sink.write(
        '"exportedAt":${jsonEncode(DateTime.now().toIso8601String())},');
    sink.write('"tables":${jsonEncode(tables)},');
    sink.write('"preferences":${jsonEncode(prefsMap)}');

    await _writeGallerySection(sink, charRows);
    await _writeAvatarsSection(
        sink, charRows, tables['personas'] as List<dynamic>?);

    sink.write('}');
  }

  Future<void> _writeGallerySection(
      IOSink sink, List<dynamic>? charRows) async {
    if (charRows == null || charRows.isEmpty) return;

    var hasGallery = false;

    for (final row in charRows) {
      final charId = row['char_id'] as String?;
      if (charId == null) continue;

      final galleryJson = row['gallery_json'] as String?;
      if (galleryJson == null || galleryJson.isEmpty) continue;

      final entries = jsonDecode(galleryJson) as List<dynamic>;
      if (entries.isEmpty) continue;

      final images = <Map<String, dynamic>>[];
      for (final e in entries) {
        final entry = e as Map<String, dynamic>;
        final imagePath = entry['imagePath'] as String?;
        if (imagePath == null) continue;

        final file = File(imagePath);
        if (await file.exists()) {
          images.add({
            'entry': entry,
            'base64': base64Encode(await file.readAsBytes()),
          });
        }
      }

      if (images.isEmpty) continue;

      if (!hasGallery) {
        sink.write(',"gallery":{');
        hasGallery = true;
      } else {
        sink.write(',');
      }
      sink.write('${jsonEncode(charId)}:${jsonEncode(images)}');
    }

    if (hasGallery) sink.write('}');
  }

  Future<void> _writeAvatarsSection(
      IOSink sink, List<dynamic>? charRows, List<dynamic>? personaRows) async {
    final avatarsDir = p.join(_imageStorage.baseDir, 'avatars');

    Future<String?> readAvatar(String id) async {
      final file = File(p.join(avatarsDir, '$id.png'));
      if (!await file.exists()) return null;
      return base64Encode(await file.readAsBytes());
    }

    var hasAvatars = false;

    if (charRows != null) {
      for (final row in charRows) {
        final charId = (row as Map<String, dynamic>)['char_id'] as String?;
        if (charId == null) continue;
        final b64 = await readAvatar(charId);
        if (b64 == null) continue;

        if (!hasAvatars) {
          sink.write(',"avatars":{"characters":{');
          hasAvatars = true;
        } else {
          sink.write(',');
        }
        sink.write('${jsonEncode(charId)}:${jsonEncode(b64)}');
      }
      if (hasAvatars) sink.write('}');
    }

    var hasPersonaAvatars = false;
    if (personaRows != null) {
      for (final row in personaRows) {
        final personaId =
            (row as Map<String, dynamic>)['persona_id'] as String?;
        if (personaId == null) continue;
        final b64 = await readAvatar(personaId);
        if (b64 == null) continue;

        if (!hasPersonaAvatars) {
          if (hasAvatars) {
            sink.write(',"personas":{');
          } else {
            sink.write(',"avatars":{"personas":{');
          }
          hasPersonaAvatars = true;
        } else {
          sink.write(',');
        }
        sink.write('${jsonEncode(personaId)}:${jsonEncode(b64)}');
      }
      if (hasPersonaAvatars) sink.write('}');
    }

    if (hasAvatars || hasPersonaAvatars) sink.write('}');
  }

  Future<Map<String, dynamic>> _readAllTables() async {
    final result = <String, dynamic>{};

    final tableMaps = await _db.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'drift_%'",
    ).get();

    for (final row in tableMaps) {
      final tableName = row.read<String>('name');
      try {
        final rows = await _db.customSelect(
          'SELECT * FROM $tableName',
        ).get();
        result[tableName] = rows.map((r) => r.data).toList();
      } catch (_) {}
    }

    return result;
  }
}
