import 'dart:convert';

import '../../db/app_db.dart';
import '../image_storage_service.dart';
import 'backup_helpers.dart';

class FlutterBackupImporter with BackupHelpers {
  @override
  final AppDatabase db;
  @override
  final ImageStorageService imageStorage;

  FlutterBackupImporter(this.db, this.imageStorage);

  Future<void> import(Map<String, dynamic> data) async {
    await _ensureSchema();
    final tables = data['tables'] as Map<String, dynamic>?;
    if (tables == null) return;

    await db.customStatement('PRAGMA foreign_keys = OFF');
    await db.transaction(() async {
      for (final entry in tables.entries) {
        final tableName = entry.key;
        final rows = entry.value as List<dynamic>;
        if (rows.isEmpty) continue;

        try {
          await db.customStatement('DELETE FROM $tableName');
        } catch (_) {}

        for (final row in rows) {
          final r = row as Map<String, dynamic>;
          final columns = r.keys.toList();
          final placeholders = columns.map((_) => '?').join(', ');

          final sql =
              'INSERT OR REPLACE INTO $tableName (${columns.join(', ')}) VALUES ($placeholders)';
          final args = <dynamic>[];
          for (final c in columns) {
            final v = r[c];
            if (v is List || v is Map) {
              args.add(jsonEncode(v));
            } else {
              args.add(v);
            }
          }

          try {
            await db.customStatement(sql, args);
          } catch (_) {}
        }
      }
    });
    await db.customStatement('PRAGMA foreign_keys = ON');

    await restoreGalleryImages(data['gallery'] as Map<String, dynamic>?);
  }

  Future<void> _ensureSchema() async {
    final tableColumns = <String, Set<String>>{};
    for (final table in [
      'api_configs',
      'chat_sessions',
      'characters',
      'lorebooks',
      'personas',
    ]) {
      final cols = await db.customSelect("PRAGMA table_info('$table')").get();
      tableColumns[table] = cols.map((c) => c.read<String>('name')).toSet();
    }

    const additions = <String, Map<String, String>>{
      'api_configs': {
        'embedding_use_same': 'BOOLEAN NOT NULL DEFAULT 1',
        'embedding_enabled': 'BOOLEAN NOT NULL DEFAULT 0',
        'embedding_endpoint': 'TEXT',
        'embedding_api_key': 'TEXT',
        'embedding_model': 'TEXT',
        'embedding_max_chunk_tokens': 'INTEGER NOT NULL DEFAULT 512',
        'omit_temperature': 'BOOLEAN NOT NULL DEFAULT 0',
        'omit_top_p': 'BOOLEAN NOT NULL DEFAULT 0',
        'omit_reasoning': 'BOOLEAN NOT NULL DEFAULT 0',
        'omit_reasoning_effort': 'BOOLEAN NOT NULL DEFAULT 0',
      },
      'chat_sessions': {
        'authors_note_json': 'TEXT',
        'draft': 'TEXT',
        'last_scroll_anchor_json': 'TEXT',
      },
      'characters': {
        'current_session_index': 'INTEGER NOT NULL DEFAULT 0',
        'fav': 'BOOLEAN NOT NULL DEFAULT 0',
        'extensions_json': 'TEXT',
        'gallery_json': 'TEXT',
        'character_version': 'TEXT',
      },
      'lorebooks': {
        'settings_json': 'TEXT',
        'description': 'TEXT',
      },
      'personas': {
        'created_at': 'INTEGER',
      },
    };

    for (final entry in additions.entries) {
      final existing = tableColumns[entry.key] ?? {};
      for (final col in entry.value.entries) {
        if (!existing.contains(col.key)) {
          await db.customStatement(
            'ALTER TABLE ${entry.key} ADD COLUMN ${col.key} ${col.value}',
          );
        }
      }
    }
  }

  Future<void> restoreGalleryImages(Map<String, dynamic>? galleryData) async {
    if (galleryData == null) return;

    for (final entry in galleryData.entries) {
      final charId = entry.key;
      final images = entry.value as List<dynamic>;

      for (final img in images) {
        final imgMap = img as Map<String, dynamic>;
        final entryData = imgMap['entry'] as Map<String, dynamic>?;
        final base64Data = imgMap['base64'] as String?;
        if (base64Data == null) continue;

        final ext = extFromEntry(entryData);
        final id = entryData?['id'] as String? ??
            'gal_${DateTime.now().millisecondsSinceEpoch}';

        try {
          await imageStorage.saveBytes(
            base64Decode(base64Data),
            'gallery/$charId',
            id,
            ext,
          );
        } catch (_) {}
      }
    }
  }
}
