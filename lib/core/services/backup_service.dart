import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../db/app_db.dart';
import '../services/image_storage_service.dart';

class BackupService {
  final AppDatabase _db;
  final ImageStorageService _imageStorage;

  BackupService(this._db, this._imageStorage);

  Future<String> exportBackup() async {
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

  Future<void> importBackup(String jsonString) async {
    final data = jsonDecode(jsonString) as Map<String, dynamic>;

    final isGlazeBackup = data['_isGlazeBackup'] == true ||
        data.containsKey('tables') ||
        data.containsKey('characters');

    if (!isGlazeBackup) {
      throw FormatException('Not a valid Glaze backup file');
    }

    final source = data['_source'] as String?;

    if (source == 'flutter') {
      await _importFlutterBackup(data);
    } else {
      await _importJsBackup(data);
    }

    final prefs = await SharedPreferences.getInstance();
    final prefsData = data['preferences'] as Map<String, dynamic>? ??
        data['localStorage'] as Map<String, dynamic>?;
    if (prefsData != null) {
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

  Future<void> _importFlutterBackup(Map<String, dynamic> data) async {
    final tables = data['tables'] as Map<String, dynamic>?;
    if (tables == null) return;

    await _db.customStatement('PRAGMA foreign_keys = OFF');
    await _db.transaction(() async {
      for (final entry in tables.entries) {
        final tableName = entry.key;
        final rows = entry.value as List<dynamic>;
        if (rows.isEmpty) continue;

        try {
          await _db.customStatement('DELETE FROM $tableName');
        } catch (_) {}

        for (final row in rows) {
          final r = row as Map<String, dynamic>;
          final columns = r.keys.toList();
          final placeholders = columns.map((_) => '?').join(', ');

          final sql = 'INSERT OR REPLACE INTO $tableName (${columns.join(', ')}) VALUES ($placeholders)';
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
            await _db.customStatement(sql, args);
          } catch (_) {}
        }
      }
    });
    await _db.customStatement('PRAGMA foreign_keys = ON');

    await _restoreGalleryImages(data['gallery'] as Map<String, dynamic>?);
  }

  Future<void> _importJsBackup(Map<String, dynamic> data) async {
    final characters = data['characters'] as List<dynamic>?;
    if (characters != null) {
      await _db.customStatement('DELETE FROM characters');
      for (final c in characters) {
        final char = c as Map<String, dynamic>;
        await _db.into(_db.characters).insertOnConflictUpdate(
              CharactersCompanion.insert(
                charId: char['id'] as String? ?? '',
                name: char['name'] as String? ?? '',
                avatarPath: Value(char['avatar'] as String?),
                description: Value(char['description'] as String?),
                personality: Value(char['personality'] as String?),
                scenario: Value(char['scenario'] as String?),
                firstMes: Value(char['first_mes'] as String?),
                mesExample: Value(char['mes_example'] as String?),
                systemPrompt: Value(char['system_prompt'] as String?),
                postHistoryInstructions:
                    Value(char['post_history_instructions'] as String?),
                creator: Value(char['creator'] as String?),
                creatorNotes: Value(char['creator_notes'] as String?),
                tagsJson: Value(char['tags'] != null
                    ? jsonEncode(char['tags'])
                    : null),
                alternateGreetingsJson: Value(
                    char['alternate_greetings'] != null
                        ? jsonEncode(char['alternate_greetings'])
                        : null),
              ),
            );
      }
    }

    final personas = data['personas'] as List<dynamic>?;
    if (personas != null) {
      await _db.customStatement('DELETE FROM personas');
      for (final p in personas) {
        final per = p as Map<String, dynamic>;
        await _db.into(_db.personas).insertOnConflictUpdate(
              PersonasCompanion.insert(
                personaId: per['id'] as String? ?? '',
                name: per['name'] as String? ?? '',
                prompt: Value(per['prompt'] as String? ?? per['description'] as String?),
                avatarPath: Value(per['avatar'] as String?),
              ),
            );
      }
    }

    final kv = data['keyvalue'] as Map<String, dynamic>?;
    if (kv != null) {
      await _importJsKeyValue(kv);
    }
  }

  Future<void> _importJsKeyValue(Map<String, dynamic> kv) async {
    final lorebooksRaw = kv['gz_lorebooks'];
    if (lorebooksRaw != null) {
      final lb = lorebooksRaw as Map<String, dynamic>;
      final lorebooks = lb['lorebooks'] as List<dynamic>?;
      if (lorebooks != null) {
        await _db.customStatement('DELETE FROM lorebooks');
        for (final l in lorebooks) {
          final entry = l as Map<String, dynamic>;
          await _db.into(_db.lorebooks).insertOnConflictUpdate(
                LorebooksCompanion.insert(
                  lorebookId: entry['id'] as String? ?? '',
                  name: entry['name'] as String? ?? '',
                  entriesJson: jsonEncode(entry['entries'] ?? []),
                ),
              );
        }
      }
    }

    final apiPresetsRaw = kv['gz_api_connection_presets'];
    if (apiPresetsRaw != null) {
      final presets = apiPresetsRaw as List<dynamic>;
      await _db.customStatement('DELETE FROM api_configs');
      for (final p in presets) {
        final preset = p as Map<String, dynamic>;
        await _db.into(_db.apiConfigs).insertOnConflictUpdate(
              ApiConfigsCompanion.insert(
                configId: preset['id'] as String? ?? '',
                name: preset['name'] as String? ?? '',
                providerId: Value(preset['provider'] as String? ?? 'openai_compatible'),
                endpoint: Value(preset['endpoint'] as String?),
                apiKey: Value(preset['apiKey'] as String?),
                model: Value(preset['model'] as String?),
                mode: Value(preset['mode'] as String? ?? 'chat'),
              ),
            );
      }
    }

    final chatPrefix = 'gz_chat_';
    final chatKeys =
        kv.keys.where((k) => k.startsWith(chatPrefix));
    for (final key in chatKeys) {
      final charId = key.substring(chatPrefix.length);
      final chatData = kv[key] as Map<String, dynamic>?;
      if (chatData == null) continue;

      final sessions = chatData['sessions'] as Map<String, dynamic>?;
      if (sessions == null) continue;

      for (final sessionEntry in sessions.entries) {
        final sessionIdx = int.tryParse(sessionEntry.key) ?? 0;
        final messages = sessionEntry.value as List<dynamic>;

        final messagesJson = jsonEncode(messages.map((m) {
          final msg = m as Map<String, dynamic>;
          return {
            'id': msg['id']?.toString() ??
                '${charId}_${sessionIdx}_${messages.indexOf(m)}',
            'role': msg['role'] ?? 'user',
            'content': msg['content'] ?? msg['text'] ?? '',
            'timestamp': msg['timestamp'],
            'personaId': msg['personaId'],
            'personaName': msg['personaName'],
          };
        }).toList());

        final sessionId = '${charId}_$sessionIdx';
        await _db.into(_db.chatSessions).insertOnConflictUpdate(
              ChatSessionsCompanion.insert(
                sessionId: sessionId,
                characterId: charId,
                sessionIndex: sessionIdx,
                messagesJson: messagesJson,
              ),
            );
      }
    }

    final lsData = kv;
    final themePresetsRaw = lsData['gz_theme_presets'];
    if (themePresetsRaw != null) {
      final presets = themePresetsRaw as List<dynamic>;
      await _db.customStatement('DELETE FROM presets');
      for (final p in presets) {
        final preset = p as Map<String, dynamic>;
        await _db.into(_db.presets).insertOnConflictUpdate(
              PresetsCompanion.insert(
                presetId: preset['id'] as String? ?? '',
                name: preset['name'] as String? ?? '',
                dataJson: jsonEncode(preset),
              ),
            );
      }
    }
  }

  Future<void> _restoreGalleryImages(
      Map<String, dynamic>? galleryData) async {
    if (galleryData == null) return;

    for (final entry in galleryData.entries) {
      final charId = entry.key;
      final images = entry.value as List<dynamic>;

      for (final img in images) {
        final imgMap = img as Map<String, dynamic>;
        final entryData = imgMap['entry'] as Map<String, dynamic>?;
        final base64Data = imgMap['base64'] as String?;
        if (base64Data == null) continue;

        final ext = _extFromEntry(entryData);
        final id = entryData?['id'] as String? ??
            'gal_${DateTime.now().millisecondsSinceEpoch}';

        try {
          await _imageStorage.saveBytes(
            base64Decode(base64Data),
            'gallery/$charId',
            id,
            ext,
          );
        } catch (_) {}
      }
    }
  }

  String _extFromEntry(Map<String, dynamic>? entry) {
    final path = entry?['imagePath'] as String?;
    if (path != null) {
      final ext = p.extension(path).replaceFirst('.', '');
      if (ext.isNotEmpty) return ext;
    }
    return 'png';
  }
}
