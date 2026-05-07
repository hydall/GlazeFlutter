import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../db/app_db.dart';
import '../models/lorebook.dart';
import '../models/preset.dart';
import 'image_storage_service.dart';
import 'preset_defaults.dart';

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
            await _db.customStatement(sql, args);
          } catch (_) {}
        }
      }
    });
    await _db.customStatement('PRAGMA foreign_keys = ON');

    await _restoreGalleryImages(data['gallery'] as Map<String, dynamic>?);
  }

  Future<void> _importJsBackup(Map<String, dynamic> data) async {
    await _clearAllTables();

    final kv = Map<String, dynamic>.from(data['keyvalue'] ?? {});
    final ls = Map<String, dynamic>.from(data['localStorage'] ?? {});

    await _importJsCharacters(data['characters']);
    await _importJsPersonas(data['personas']);
    await _importJsLorebooks(kv);
    await _importJsCharacterBooks(data['characters']);
    await _importJsApiConfigs(kv, ls);
    await _importJsMemoryBooks(kv, ls, data['characters']);
    await _importJsLorebookSettings(kv, ls);
    await _importJsChats(kv);
    await _importJsPresets(kv, ls);
    await _importJsActiveSelections(kv, ls);
    await _importJsGalleryFromCharacters(data['characters']);
  }

  Future<void> _clearAllTables() async {
    await _db.customStatement('PRAGMA foreign_keys = OFF');
    await _db.transaction(() async {
      const tables = [
        'characters',
        'chat_sessions',
        'presets',
        'api_configs',
        'personas',
        'lorebooks',
        'embeddings',
        'chat_summaries',
        'memory_book_rows',
      ];
      for (final table in tables) {
        try {
          await _db.customStatement('DELETE FROM $table');
        } catch (_) {}
      }
    });
    await _db.customStatement('PRAGMA foreign_keys = ON');
  }

  Future<void> _importJsCharacters(dynamic data) async {
    if (data is! List) return;
    for (final c in data) {
      final char = c as Map<String, dynamic>;
      String? avatarPath;
      final avatar = char['avatar'] as String?;
      if (avatar != null && avatar.startsWith('data:')) {
        final id = char['id'] as String? ?? _generateId();
        avatarPath = await _imageStorage.saveAvatarFromDataUrl(id, avatar);
      } else {
        avatarPath = avatar;
      }

      await _db.into(_db.characters).insertOnConflictUpdate(
            CharactersCompanion.insert(
              charId: char['id'] as String? ?? '',
              name: char['name'] as String? ?? '',
              avatarPath: Value(avatarPath),
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
              color: Value(char['color'] as String?),
              tagsJson:
                  Value(char['tags'] != null ? jsonEncode(char['tags']) : null),
              alternateGreetingsJson: Value(
                  char['alternate_greetings'] != null
                      ? jsonEncode(char['alternate_greetings'])
                      : null),
              updatedAt: Value(_toInt(char['updatedAt'] ?? char['updated_at']) ??
                  DateTime.now().millisecondsSinceEpoch ~/ 1000),
            ),
          );
    }
  }

  Future<void> _importJsPersonas(dynamic data) async {
    if (data is! List) return;
    for (final p in data) {
      final per = p as Map<String, dynamic>;
      String? avatarPath;
      final avatar = per['avatar'] as String?;
      if (avatar != null && avatar.startsWith('data:')) {
        final id = per['id'] as String? ?? _generateId();
        avatarPath = await _imageStorage.saveAvatarFromDataUrl(id, avatar);
      } else {
        avatarPath = avatar;
      }

      await _db.into(_db.personas).insertOnConflictUpdate(
            PersonasCompanion.insert(
              personaId: per['id'] as String? ?? '',
              name: per['name'] as String? ?? '',
              prompt:
                  Value(per['prompt'] as String? ?? per['description'] as String?),
              avatarPath: Value(avatarPath),
              createdAt: Value(_toInt(per['createdAt'] ?? per['created_at']) ??
                  DateTime.now().millisecondsSinceEpoch ~/ 1000),
            ),
          );
    }
  }

  Future<void> _importJsLorebooks(Map<String, dynamic> kv) async {
    final lorebooksRaw = kv['gz_lorebooks'];
    if (lorebooksRaw != null) {
      final lb = lorebooksRaw as Map<String, dynamic>;
      final lorebooks = lb['lorebooks'] as List<dynamic>?;
      if (lorebooks != null) {
        for (final l in lorebooks) {
          final lbJson = l as Map<String, dynamic>;
          final rawEntries = lbJson['entries'];
          final mappedEntries = <Map<String, dynamic>>[];

          if (rawEntries is List) {
            for (final e in rawEntries) {
              if (e is Map<String, dynamic>) mappedEntries.add(_mapJsLorebookEntry(e));
            }
          } else if (rawEntries is Map) {
            for (final e in rawEntries.values) {
              if (e is Map<String, dynamic>) mappedEntries.add(_mapJsLorebookEntry(e));
            }
          }

          await _db.into(_db.lorebooks).insertOnConflictUpdate(
                LorebooksCompanion.insert(
                  lorebookId: lbJson['id'] as String? ?? '',
                  name: lbJson['name'] as String? ?? '',
                  enabled: Value(lbJson['enabled'] as bool? ?? true),
                  activationScope: Value(
                      lbJson['activationScope'] as String? ??
                          lbJson['scope'] as String? ??
                          'global'),
                  activationTargetId: Value(
                      lbJson['activationTargetId'] as String? ??
                          lbJson['targetId'] as String?),
                  entriesJson: jsonEncode(mappedEntries),
                ),
              );
        }
      }
    }
  }

  Future<void> _importJsCharacterBooks(dynamic charData) async {
    if (charData is! List) return;
    for (final c in charData) {
      final char = c as Map<String, dynamic>;
      final charId = char['id'] as String?;
      if (charId == null) continue;

      final cbRaw = char['character_book'] ?? char['data']?['character_book'];
      if (cbRaw is! Map<String, dynamic>) continue;

      final rawEntries = cbRaw['entries'];
      final mappedEntries = <Map<String, dynamic>>[];

      if (rawEntries is List) {
        for (final e in rawEntries) {
          if (e is Map<String, dynamic>) mappedEntries.add(_mapJsLorebookEntry(e));
        }
      } else if (rawEntries is Map) {
        for (final e in rawEntries.values) {
          if (e is Map<String, dynamic>) mappedEntries.add(_mapJsLorebookEntry(e));
        }
      }

      if (mappedEntries.isEmpty) continue;

      final cbId = cbRaw['id'] as String? ?? 'cb_$charId';
      final existing = (_db.select(_db.lorebooks)
            ..where((t) => t.lorebookId.equals(cbId)));
      final existingRow = await existing.getSingleOrNull();
      if (existingRow != null) continue;

      await _db.into(_db.lorebooks).insertOnConflictUpdate(
            LorebooksCompanion.insert(
              lorebookId: cbId,
              name: cbRaw['name'] as String? ?? '${char['name'] ?? 'Char'} Lorebook',
              enabled: Value(cbRaw['enabled'] as bool? ?? true),
              activationScope: Value('character'),
              activationTargetId: Value(charId),
              entriesJson: jsonEncode(mappedEntries),
            ),
          );
    }
  }

  Map<String, dynamic> _mapJsLorebookEntry(Map<String, dynamic> e) {
    final keys = _toStringList(e['keys'] ?? e['key']);
    final secondaryKeys = _toStringList(e['secondaryKeys'] ?? e['secondary_keys'] ?? e['keysecondary']);

    var enabled = e['enabled'] as bool?;
    if (enabled == null) {
      final disabled = e['disable'] as bool? ?? false;
      enabled = !disabled;
    }

    final position = _mapLorebookPosition(e['position']);

    final charFilter = e['characterFilter'] ?? e['character_filter'];
    LorebookCharacterFilter? filter;
    if (charFilter is Map) {
      final names = charFilter['names'];
      filter = LorebookCharacterFilter(
        names: names is List ? names.map((n) => n.toString()).toList() : [],
        isExclude: charFilter['isExclude'] as bool? ?? false,
      );
    } else if (charFilter is List) {
      filter = LorebookCharacterFilter(
        names: charFilter.map((n) => n.toString()).toList(),
      );
    }

    return {
      'id': (e['uid'] ?? e['id'] ?? DateTime.now().millisecondsSinceEpoch).toString(),
      'comment': e['comment'] ?? e['name'] ?? '',
      'enabled': enabled,
      'constant': e['constant'] as bool? ?? false,
      'keys': keys,
      'secondaryKeys': secondaryKeys,
      'selectiveLogic': e['selectiveLogic'] ?? e['selective_logic'] ?? 5,
      'content': e['content'] ?? '',
      'position': position,
      'order': _toInt(e['order'] ?? e['insertion_order']) ?? 100,
      'scanDepth': _toInt(e['scanDepth'] ?? e['scan_depth']),
      'caseSensitive': e['caseSensitive'] ?? e['case_sensitive'] ?? false,
      'matchWholeWords': e['matchWholeWords'] ?? e['match_whole_words'] ?? false,
      'probability': _toInt(e['probability']) ?? 100,
      'preventRecursion': e['preventRecursion'] ?? e['prevent_recursion'] ?? false,
      'sticky': _toInt(e['sticky']) ?? 0,
      'cooldown': _toInt(e['cooldown']) ?? 0,
      'delay': _toInt(e['delay']) ?? 0,
      'group': e['group'] ?? '',
      'groupProminence': _toInt(e['groupProminence'] ?? e['group_prominence']) ?? 100,
      'characterFilter': filter?.toJson(),
      'ignoreBudget': e['ignoreBudget'] ?? false,
      'vectorSearch': e['vectorSearch'] ?? e['vector_search'] ?? false,
      'useKeywordSearch': e['useKeywordSearch'] ?? e['use_keyword_search'] ?? true,
    };
  }

  String _mapLorebookPosition(dynamic pos) {
    if (pos is String) return pos;
    if (pos is int) {
      return switch (pos) {
        0 => 'worldInfoBefore',
        1 => 'worldInfoAfter',
        2 => 'worldInfoBefore',
        3 => 'worldInfoAfter',
        4 => 'at_depth',
        _ => 'worldInfoBefore',
      };
    }
    return 'worldInfoBefore';
  }

  List<String> _toStringList(dynamic value) {
    if (value is List) return value.map((e) => e.toString()).toList();
    if (value is String && value.isNotEmpty) {
      return value.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    }
    return [];
  }

  Future<void> _importJsApiConfigs(
      Map<String, dynamic> kv, Map<String, dynamic> ls) async {
    final presets = <Map<String, dynamic>>[];

    for (final source in [kv, ls]) {
      for (final key in [
        'gz_api_connection_presets',
        'silly_cradle_api_presets',
        'api_connection_presets',
      ]) {
        final raw = source[key];
        if (raw == null) continue;
        if (raw is List) {
          for (final p in raw) {
            if (p is Map<String, dynamic>) presets.add(p);
          }
        } else if (raw is String) {
          try {
            final decoded = jsonDecode(raw);
            if (decoded is List) {
              for (final p in decoded) {
                if (p is Map<String, dynamic>) presets.add(p);
              }
            }
          } catch (_) {}
        }
      }
    }

    if (presets.isEmpty) return;

    for (final preset in presets) {
      await _db.into(_db.apiConfigs).insertOnConflictUpdate(
            ApiConfigsCompanion.insert(
              configId: preset['id'] as String? ?? '',
              name: preset['name'] as String? ?? '',
              providerId: Value(
                  preset['providerId'] as String? ??
                      preset['provider'] as String? ??
                      'openai_compatible'),
              endpoint: preset['endpoint'] != null
                  ? Value(preset['endpoint'] as String)
                  : const Value.absent(),
              apiKey: Value(
                  preset['apiKey'] as String? ?? preset['key'] as String?),
              model: Value(preset['model'] as String?),
              mode: Value(
                  preset['mode'] as String? ??
                  ((preset['isEmbedding'] as bool?) == true ? 'embedding' : 'chat')),
              maxTokens: Value(_toInt(preset['max_tokens']) ?? 8000),
              contextSize: Value(_toInt(preset['context']) ?? 32000),
              temperature: Value(_toDouble(preset['temp']) ?? 0.7),
              topP: Value(_toDouble(preset['topp']) ?? 0.9),
              stream: Value(preset['stream'] as bool? ?? true),
              reasoningEffort: Value(preset['reasoningEffort'] as String? ??
                  _extractReasoningEffort(preset)),
              requestReasoning:
                  Value(preset['requestReasoning'] as bool? ?? false),
              reasoningTagStart: Value(
                  preset['reasoningTagStart'] as String? ??
                      (preset['reasoningTags'] as Map<String, dynamic>?)
                          ?['start'] as String?),
              reasoningTagEnd: Value(
                  preset['reasoningTagEnd'] as String? ??
                      (preset['reasoningTags'] as Map<String, dynamic>?)
                          ?['end'] as String?),
            ),
          );
    }
  }

  Future<void> _importJsMemoryBooks(
      Map<String, dynamic> kv, Map<String, dynamic> ls, dynamic charData) async {
    final memoryPrefix = 'gz_memory_book_';
    final memoryKeys = kv.keys.where((k) => k.startsWith(memoryPrefix));

    for (final key in memoryKeys) {
      final sessionId = key.substring(memoryPrefix.length);
      final raw = kv[key];
      if (raw is! Map<String, dynamic>) continue;

      final entries = <Map<String, dynamic>>[];
      final rawEntries = raw['entries'];
      if (rawEntries is List) {
        for (final e in rawEntries) {
          if (e is Map<String, dynamic>) {
            entries.add({
              'id': e['id']?.toString() ?? '',
              'title': e['title'] as String? ?? e['name'] as String? ?? '',
              'keys': e['keys'] is List
                  ? List<String>.from(e['keys'])
                  : <String>[],
              'content': e['content'] as String? ?? '',
              'status': e['status'] as String? ?? 'active',
              'vectorSearch': e['vectorSearch'] as bool? ?? false,
              'messageIds': e['messageIds'] is List
                  ? List<String>.from(e['messageIds'])
                  : <String>[],
              'createdAt': e['createdAt']?.toString(),
            });
          }
        }
      }

      final rawSettings = raw['settings'] as Map<String, dynamic>? ?? {};
      final settings = <String, dynamic>{
        'enabled': rawSettings['enabled'] as bool? ?? true,
        'autoCreateEnabled': rawSettings['autoCreateEnabled'] as bool? ?? true,
        'autoGenerateEnabled': rawSettings['autoGenerateEnabled'] as bool? ?? false,
        'maxInjectedEntries': _toInt(rawSettings['maxInjectedEntries']) ?? 7,
        'autoCreateInterval': _toInt(rawSettings['autoCreateInterval']) ?? 15,
        'useDelayedAutomation': rawSettings['useDelayedAutomation'] as bool? ?? true,
        'injectionTarget': rawSettings['injectionTarget'] as String? ?? 'summary_block',
        'batchSize': _toInt(rawSettings['batchSize']) ?? 3,
        'vectorSearchEnabled': rawSettings['vectorSearchEnabled'] as bool? ?? false,
        'keyMatchMode': rawSettings['keyMatchMode'] as String? ?? 'plain',
        'generationModel': rawSettings['generationModel'] as String? ?? '',
        'generationEndpoint': rawSettings['generationEndpoint'] as String? ?? '',
        'generationApiKey': rawSettings['generationApiKey'] as String? ?? '',
      };

      await _db.into(_db.memoryBookRows).insertOnConflictUpdate(
            MemoryBookRowsCompanion.insert(
              sessionId: sessionId,
              entriesJson: Value(jsonEncode(entries)),
              settingsJson: Value(jsonEncode(settings)),
              lastProcessedMessageCount: Value(
                  _toInt(raw['lastProcessedMessageCount']) ?? 0),
              updatedAt: Value(
                  _toInt(raw['updatedAt']) ??
                  DateTime.now().millisecondsSinceEpoch ~/ 1000),
            ),
          );
    }
  }

  Future<void> _importJsLorebookSettings(
      Map<String, dynamic> kv, Map<String, dynamic> ls) async {
    final prefs = await SharedPreferences.getInstance();
    for (final source in [kv, ls]) {
      final raw = source['gz_lorebook_settings'] ?? source['lorebook_settings'];
      if (raw == null) continue;
      Map<String, dynamic> settings;
      if (raw is String) {
        try {
          settings = jsonDecode(raw) as Map<String, dynamic>;
        } catch (_) { continue; }
      } else if (raw is Map<String, dynamic>) {
        settings = raw;
      } else { continue; }
      await prefs.setString('lorebookSettings', jsonEncode(settings));
      break;
    }
  }

  Future<void> _importJsChats(Map<String, dynamic> kv) async {
    const chatPrefix = 'gz_chat_';
    final chatKeys = kv.keys.where((k) => k.startsWith(chatPrefix));

    for (final key in chatKeys) {
      final charId = key.substring(chatPrefix.length);
      final chatData = kv[key] as Map<String, dynamic>?;
      if (chatData == null) continue;

      final sessions = chatData['sessions'] as Map<String, dynamic>?;
      if (sessions == null) continue;

      for (final sessionEntry in sessions.entries) {
        final sessionIdx = int.tryParse(sessionEntry.key) ?? 0;
        final rawMessages = sessionEntry.value as List<dynamic>;

        final messages = rawMessages.map((m) {
          final msg = m as Map<String, dynamic>;
          var role = msg['role'] as String? ?? 'user';
          if (role == 'char') role = 'assistant';

          final content =
              msg['content'] as String? ?? msg['text'] as String? ?? msg['mes'] as String? ?? '';

          final swipes = <String>[];
          final rawSwipes = msg['swipes'];
          if (rawSwipes is List) {
            for (final s in rawSwipes) {
              swipes.add(s.toString());
            }
          }
          if (swipes.isEmpty && content.isNotEmpty) {
            swipes.add(content);
          }

          String? reasoning;
          final rawReasoning = msg['reasoning'];
          if (rawReasoning is String && rawReasoning.isNotEmpty) {
            reasoning = rawReasoning;
          }

          final persona = msg['persona'];
          String? personaId;
          String? personaName;
          if (persona is Map) {
            personaId = persona['id'] as String?;
            personaName = persona['name'] as String?;
          }

          return {
            'id': msg['id']?.toString() ??
                '${charId}_${sessionIdx}_${rawMessages.indexOf(m)}',
            'role': role,
            'content': content,
            'timestamp': msg['timestamp'],
            'personaId': msg['personaId'] ?? personaId,
            'personaName': msg['personaName'] ?? personaName,
            'swipes': swipes,
            'swipeId': _toInt(msg['swipeId'] ?? msg['swipe_id']) ?? 0,
            'reasoning': reasoning,
            'isHidden': msg['isHidden'] ?? msg['is_hidden'] ?? false,
            'isError': msg['isError'] ?? false,
            'genTime': msg['genTime'] as String?,
            'tokens': _toInt(msg['tokens']),
          };
        }).toList();

        final sessionId = '${charId}_$sessionIdx';
        await _db.into(_db.chatSessions).insertOnConflictUpdate(
              ChatSessionsCompanion.insert(
                sessionId: sessionId,
                characterId: charId,
                sessionIndex: sessionIdx,
                messagesJson: jsonEncode(messages),
              ),
            );
      }
    }
  }

  Future<void> _importJsPresets(
      Map<String, dynamic> kv, Map<String, dynamic> ls) async {
    final presetList = <Map<String, dynamic>>[];

    for (final source in [kv, ls]) {
      final sillyCradleRaw = source['silly_cradle_presets'];
      if (sillyCradleRaw == null) continue;

      Map<String, dynamic> presetsMap;
      if (sillyCradleRaw is String) {
        try {
          presetsMap = jsonDecode(sillyCradleRaw) as Map<String, dynamic>;
        } catch (_) {
          continue;
        }
      } else if (sillyCradleRaw is Map<String, dynamic>) {
        presetsMap = sillyCradleRaw;
      } else {
        continue;
      }

      var inner = presetsMap['presets'];
      if (inner is Map<String, dynamic>) {
        for (final entry in inner.entries) {
          if (entry.value is Map<String, dynamic>) {
            presetList.add(entry.value as Map<String, dynamic>);
          }
        }
      } else if (inner is List) {
        for (final p in inner) {
          if (p is Map<String, dynamic>) presetList.add(p);
        }
      } else {
        for (final entry in presetsMap.entries) {
          if (entry.value is Map<String, dynamic> &&
              entry.value.containsKey('name')) {
            presetList.add(entry.value as Map<String, dynamic>);
          }
        }
      }
    }

    if (presetList.isEmpty) return;

    for (final presetJson in presetList) {
      try {
        final preset = _mapJsPreset(presetJson);
        await _db.into(_db.presets).insertOnConflictUpdate(
              PresetsCompanion.insert(
                presetId: preset.id,
                name: preset.name,
                dataJson: jsonEncode(preset.toJson()),
              ),
            );
      } catch (_) {}
    }
  }

  Future<void> _importJsActiveSelections(
      Map<String, dynamic> kv, Map<String, dynamic> ls) async {
    final prefs = await SharedPreferences.getInstance();

    final activePresetId =
        ls['silly_cradle_current_preset_id'] ?? kv['gz_active_preset'];
    if (activePresetId is String && activePresetId.isNotEmpty) {
      await prefs.setString('activePresetId', activePresetId);
    }

    final activePersonaRaw = ls['gz_active_persona'] ?? kv['gz_active_persona'];
    if (activePersonaRaw is String) {
      try {
        final persona =
            jsonDecode(activePersonaRaw) as Map<String, dynamic>;
        final id = persona['id'] as String?;
        if (id != null) await prefs.setString('activePersonaId', id);
      } catch (_) {}
    } else if (activePersonaRaw is Map) {
      final id = activePersonaRaw['id'] as String?;
      if (id != null) await prefs.setString('activePersonaId', id);
    }
  }

  Future<void> _importJsGalleryFromCharacters(dynamic data) async {
    if (data is! List) return;
    for (final c in data) {
      final char = c as Map<String, dynamic>;
      final charId = char['id'] as String?;
      if (charId == null) continue;

      final galleryRaw = char['gallery'] ?? char['data']?['extensions']?['gallery'];
      if (galleryRaw is! List || galleryRaw.isEmpty) continue;

      final galleryEntries = <Map<String, dynamic>>[];
      for (int i = 0; i < galleryRaw.length; i++) {
        final g = galleryRaw[i];
        if (g is! Map<String, dynamic>) continue;

        final imageUrl = g['url'] as String? ?? g['image'] as String?;
        if (imageUrl == null) continue;

        String? imagePath;
        if (imageUrl.startsWith('data:')) {
          final galId = 'gal_${charId}_$i';
          final bytes = _dataUrlToBytes(imageUrl);
          if (bytes == null) continue;
          imagePath = await _imageStorage.saveBytes(
            bytes,
            'gallery/$charId',
            galId,
            'png',
          );
        } else {
          continue;
        }

        galleryEntries.add({
          'id': g['id'] as String? ?? 'gal_${charId}_$i',
          'characterId': charId,
          'imagePath': imagePath,
          'label': g['label'] as String? ?? g['name'] as String?,
          'createdAt': _toInt(g['createdAt']) ?? 0,
        });
      }

      if (galleryEntries.isNotEmpty) {
        await (_db.update(_db.characters)
              ..where((t) => t.charId.equals(charId)))
            .write(CharactersCompanion(
          galleryJson: Value(jsonEncode(galleryEntries)),
        ));
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

  Preset _mapJsPreset(Map<String, dynamic> json) {
    final blocks = <PresetBlock>[];
    final rawBlocks = json['blocks'] ?? json['prompt_order'];
    if (rawBlocks is List) {
      for (final b in rawBlocks) {
        if (b is! Map<String, dynamic>) continue;
        blocks.add(PresetBlock(
          id: b['id'] as String? ?? _generateId(),
          name: b['name'] as String? ?? '',
          role: b['role'] as String? ?? 'system',
          content: b['content'] as String? ?? '',
          enabled: b['enabled'] as bool? ?? true,
          isStatic: b['isStatic'] as bool? ?? false,
          insertionMode: (b['insertion_mode'] as String?) ??
              (b['insertionMode'] as String?) ??
              'relative',
          depth: _toInt(b['depth']),
          prefix: b['prefix'] as String?,
          isStashed: b['isStashed'] as bool? ?? false,
        ));
      }
    }

    final regexes = <PresetRegex>[];
    final rawRegexes = json['regexes'] ?? json['regex_scripts'];
    if (rawRegexes is List) {
      for (final r in rawRegexes) {
        if (r is! Map<String, dynamic>) continue;
        regexes.add(PresetRegex(
          id: r['id'] as String? ?? _generateId(),
          name: r['name'] as String? ?? r['scriptName'] as String? ?? '',
          regex: r['regex'] as String? ?? r['findRegex'] as String? ?? '',
          replacement:
              r['replacement'] as String? ?? r['replaceString'] as String? ?? '',
          trimOut: r['trimOut'] as String? ??
              _joinTrimStrings(r['trimStrings']),
          placement: _toIntList(r['placement']),
          ephemerality: _toIntList(r['ephemerality']),
          disabled: r['disabled'] as bool? ?? false,
          macroRules:
              (r['macroRules'] ?? r['substituteRegex'] ?? 0).toString(),
          minDepth: _toInt(r['minDepth']),
          maxDepth: _toInt(r['maxDepth']),
        ));
      }
    }

    return finalizeImportedPreset(Preset(
      id: json['id'] as String? ?? _generateId(),
      name: json['name'] as String? ?? 'Imported',
      author: json['author'] as String?,
      blocks: blocks,
      regexes: regexes,
      reasoningEnabled: json['reasoningEnabled'] as bool? ?? false,
      reasoningStart: json['reasoningStart'] as String?,
      reasoningEnd: json['reasoningEnd'] as String?,
      guidedGenerationPrompt: json['guidedGenerationPrompt'] as String?,
      guidedImpersonationPrompt: json['guidedImpersonationPrompt'] as String?,
      summaryPrompt: json['summaryPrompt'] as String?,
      mergePrompts: json['mergePrompts'] as bool? ?? false,
      mergeRole: json['mergeRole'] as String? ?? 'system',
      createdAt: _toInt(json['createdAt']) ?? 0,
    ));
  }

  String _extractReasoningEffort(Map<String, dynamic> preset) {
    final tags = preset['reasoningTags'] as Map<String, dynamic>?;
    if (tags != null) {
      final effort = tags['effort'] as String?;
      if (effort != null) return effort;
    }
    return 'medium';
  }

  String _extFromEntry(Map<String, dynamic>? entry) {
    final path = entry?['imagePath'] as String?;
    if (path != null) {
      final ext = p.extension(path).replaceFirst('.', '');
      if (ext.isNotEmpty) return ext;
    }
    return 'png';
  }

  String _generateId() {
    return DateTime.now().millisecondsSinceEpoch.toRadixString(36) +
        Random().nextInt(9999).toRadixString(36);
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    if (value is double) return value.toInt();
    return null;
  }

  double? _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  List<int> _toIntList(dynamic value) {
    if (value is List) {
      return value.map((e) {
        if (e is int) return e;
        if (e is num) return e.toInt();
        return int.tryParse(e.toString()) ?? 0;
      }).toList();
    }
    return [1, 2];
  }

  String _joinTrimStrings(dynamic value) {
    if (value is List) return value.map((e) => e.toString()).join('\n');
    return '';
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
}
