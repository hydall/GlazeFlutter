import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../../db/app_db.dart';

class BackupExporter {
  final AppDatabase _db;

  BackupExporter(this._db);

  Future<String> export() async {
    final data = <String, dynamic>{
      '_isGlazeBackup': true,
      '_glazeVersion': 1,
      '_source': 'flutter',
      'exportedAt': DateTime.now().toIso8601String(),
    };

    final tables = await _readAllTables();
    data['tables'] = tables;

    final prefs = await SharedPreferences.getInstance();
    final prefsMap = <String, dynamic>{};
    for (final key in prefs.getKeys()) {
      final value = prefs.get(key);
      if (value != null) prefsMap[key] = value;
    }
    data['preferences'] = prefsMap;

    final gallery = await _readGalleryImages(tables);
    if (gallery.isNotEmpty) data['gallery'] = gallery;

    return JsonEncoder.withIndent(null).convert(data);
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

  Future<Map<String, dynamic>> _readGalleryImages(
      Map<String, dynamic> tables) async {
    final gallery = <String, dynamic>{};

    final charRows = tables['characters'] as List<dynamic>?;
    if (charRows == null) return gallery;

    for (final row in charRows) {
      final charId = row['char_id'] as String?;
      if (charId == null) continue;

      final galleryJson = row['gallery_json'] as String?;
      if (galleryJson == null || galleryJson.isEmpty) continue;

      final entries = jsonDecode(galleryJson) as List<dynamic>;
      final images = <Map<String, dynamic>>[];

      for (final e in entries) {
        final entry = e as Map<String, dynamic>;
        final imagePath = entry['imagePath'] as String?;
        if (imagePath == null) continue;

        final file = File(imagePath);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          images.add({
            'entry': entry,
            'base64': base64Encode(bytes),
          });
        }
      }

      if (images.isNotEmpty) gallery[charId] = images;
    }

    return gallery;
  }
}
