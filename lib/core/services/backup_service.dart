import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../db/app_db.dart';
import 'backup/backup_exporter.dart';
import 'backup/flutter_backup_importer.dart';
import 'backup/js_backup_importer.dart';
import 'image_storage_service.dart';

class BackupService {
  final AppDatabase _db;
  final ImageStorageService _imageStorage;

  BackupService(this._db, this._imageStorage);

  Future<String> exportBackup() => BackupExporter(_db).export();

  Future<void> importBackup(String jsonString) async {
    final data = jsonDecode(jsonString) as Map<String, dynamic>;
    final isGlazeBackup = data['_isGlazeBackup'] == true ||
        data.containsKey('tables') ||
        data.containsKey('characters');
    if (!isGlazeBackup) {
      throw FormatException('Not a valid Glaze backup file');
    }

    if (data['_source'] == 'flutter') {
      await FlutterBackupImporter(_db, _imageStorage).import(data);
    } else {
      await JsBackupImporter(_db, _imageStorage).import(data);
    }

    final prefs = await SharedPreferences.getInstance();
    final prefsData = (data['preferences'] as Map<String, dynamic>?) ??
        (data['localStorage'] as Map<String, dynamic>?);
    if (prefsData != null) {
      final themeKeys = prefs.getKeys().where(
          (k) => k.startsWith('gz_theme_') || k.startsWith('glaze_theme_'));
      for (final k in themeKeys) {
        await prefs.remove(k);
      }
      for (final entry in prefsData.entries) {
        final v = entry.value;
        if (v is bool) {
          await prefs.setBool(entry.key, v);
        } else if (v is int) {
          await prefs.setInt(entry.key, v);
        } else if (v is double) {
          await prefs.setDouble(entry.key, v);
        } else if (v is String) {
          await prefs.setString(entry.key, v);
        }
      }
    }

    final lsData = data['localStorage'] as Map<String, dynamic>?;
    if (lsData != null) {
      final personaConnsRaw = lsData['gz_persona_connections'];
      if (personaConnsRaw != null) {
        try {
          final parsed = personaConnsRaw is String
              ? jsonDecode(personaConnsRaw) as Map<String, dynamic>
              : personaConnsRaw as Map<String, dynamic>;
          final conns = {
            'character': parsed['character'] ?? {},
            'chat': parsed['chat'] ?? {},
          };
          await prefs.setString('personaConnections', jsonEncode(conns));
        } catch (_) {}
      }
    }
  }
}
