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
    await _ensureSchema();
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
    await _ensureSchema();
    await _clearAllTables();

    final kv = Map<String, dynamic>.from(data['keyvalue'] ?? {});
    final ls = Map<String, dynamic>.from(data['localStorage'] ?? {});

    await _importJsCharacters(data['characters']);
    await _importJsPersonas(data['personas']);
    await _importJsLorebooks(kv);
    await _importJsCharacterBooks(data['characters']);
    await _importJsApiConfigs(kv, ls, data);
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

  Future<void> _ensureSchema() async {
    final existing = <String>{};
    final cols = await _db.customSelect(
      "PRAGMA table_info('api_configs')",
    ).get();
    for (final c in cols) {
      existing.add(c.read<String>('name'));
    }
    const additions = <String, String>{
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
    };
    for (final e in additions.entries) {
      if (!existing.contains(e.key)) {
        await _db.customStatement(
          'ALTER TABLE api_configs ADD COLUMN ${e.key} ${e.value}',
        );
      }
    }
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
                  DateTime.now().millisecondsSinceEpoch),
              fav: Value(char['fav'] == true),
              extensionsJson: Value(_extractExtensionsJson(char)),
              characterVersion: Value(char['character_version'] is String ? char['character_version'] as String : '1'),
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
    if (lorebooksRaw == null) return;

    List<dynamic>? lorebooks;
    Map<String, dynamic>? globalSettings;
    Map<String, dynamic>? activations;

    if (lorebooksRaw is List) {
      lorebooks = lorebooksRaw;
    } else if (lorebooksRaw is Map<String, dynamic>) {
      final lb = lorebooksRaw;
      final inner = lb['lorebooks'];
      if (inner is List) {
        lorebooks = inner;
      } else {
        lorebooks = lb.values.whereType<Map<String, dynamic>>().where((m) => m.containsKey('entries') || m.containsKey('name')).toList();
      }
      if (lb['settings'] is Map<String, dynamic>) globalSettings = lb['settings'];
      if (lb['activations'] is Map<String, dynamic>) activations = lb['activations'];
    }

    if (lorebooks == null) return;

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


      final lbSettingsRaw = lbJson['settings'] as Map<String, dynamic>? ?? globalSettings;
      final String settingsJsonStr;
      if (lbSettingsRaw != null) {
        final normalized = Map<String, dynamic>.from(lbSettingsRaw);
        final mww = normalized['matchWholeWords'];
        if (mww is bool) {
          normalized['matchWholeWords'] = mww ? 'true' : 'false';
        } else if (mww == null) {
          normalized.remove('matchWholeWords');
        }
        settingsJsonStr = jsonEncode(normalized);
      } else {
        settingsJsonStr = '';
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
              settingsJson: Value(settingsJsonStr),
              description: Value(lbJson['description'] is String ? lbJson['description'] as String : ''),
              updatedAt: Value(_toInt(lbJson['updatedAt']) ?? DateTime.now().millisecondsSinceEpoch ~/ 1000),
            ),
          );
    }

    if (activations != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lorebookActivations', jsonEncode(activations));
    }

    if (globalSettings != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lorebookSettings', jsonEncode(globalSettings));
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
      'probability': _toDouble(e['probability']) ?? 100.0,
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
      'delayUntilRecursion': e['delayUntilRecursion'] ?? e['delay_until_recursion'] ?? false,
      'useGroupScoring': e['useGroupScoring'] ?? e['use_group_scoring'] ?? false,
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
      Map<String, dynamic> kv, Map<String, dynamic> ls,
      [Map<String, dynamic>? topLevel]) async {
    final profilesRaw = ls['gz_provider_profiles'];
    Map<String, dynamic>? serviceProfileMap;
    for (final src in [ls, kv]) {
      final spmRaw = src['gz_service_profile_map'];
      if (spmRaw is String) {
        try { serviceProfileMap = jsonDecode(spmRaw); break; } catch (_) {}
      } else if (spmRaw is Map<String, dynamic>) {
        serviceProfileMap = spmRaw; break;
      }
    }

    Map<String, dynamic>? connPreset;
    final connPresetsRaw = kv['gz_api_connection_presets'];
    if (connPresetsRaw != null) {
      final presets = <Map<String, dynamic>>[];
      _extractPresetsFromRaw(connPresetsRaw, presets);
      if (presets.isNotEmpty) connPreset = presets.first;
    }

    if (profilesRaw != null) {
      final allProfiles = <Map<String, dynamic>>[];
      _extractPresetsFromRaw(profilesRaw, allProfiles);

      String? llmProfileId;
      final skipIds = <String>{};
      Map<String, dynamic>? embProfile;
      bool embUseSame = true;

      llmProfileId = ls['gz_active_llm_profile_id'] as String?
          ?? kv['gz_active_llm_profile_id'] as String?;

      if (serviceProfileMap != null) {
        final spmLlm = (serviceProfileMap['llm'] as Map<String, dynamic>?)?['profileId'] as String?;
        if (spmLlm != null) llmProfileId = spmLlm;

        for (final svc in ['embedding', 'image_gen', 'memory_books']) {
          final svcConfig = serviceProfileMap[svc] as Map<String, dynamic>?;
          final svcProfileId = svcConfig?['profileId'] as String?;
          if (svcProfileId != null && svcProfileId != llmProfileId) {
            skipIds.add(svcProfileId);
          }
        }

        final embConfig = serviceProfileMap['embedding'] as Map<String, dynamic>?;
        embUseSame = embConfig?['useSameAsLLM'] as bool? ?? true;
        final embProfileId = embConfig?['profileId'] as String?;
        if (embProfileId != null && embProfileId != llmProfileId) {
          embProfile = allProfiles.cast<Map<String, dynamic>?>().firstWhere(
            (p) => p?['id'] == embProfileId, orElse: () => null);
        }
      }

      final imggenApiKeys = <String>{};
      for (final k in ['gz_imggen_api_key', 'gz_imggen_routmy_api_key', 'gz_imggen_naistera_api_key']) {
        final v = ls[k] as String?;
        if (v != null && v.isNotEmpty) imggenApiKeys.add(v);
      }

      final seenIds = <String>{};
      for (final p in allProfiles) {
        final pid = p['id'] as String? ?? '';
        if (seenIds.contains(pid)) continue;
        seenIds.add(pid);

        if (skipIds.contains(pid)) continue;
        if (pid != llmProfileId) {
          final ep = (p['endpoint'] as String?) ?? '';
          final ak = (p['apiKey'] as String?) ?? (p['key'] as String?) ?? '';
          if (ep.isEmpty && imggenApiKeys.contains(ak)) continue;
        }

        String embEndpoint = '';
        String embApiKey = '';
        String embModel = '';
        bool embSame = embUseSame;
        bool embEnabled = false;
        int embMaxChunk = 512;

        if (embProfile != null && pid == llmProfileId && !embUseSame) {
          embEndpoint = embProfile['endpoint'] as String? ?? '';
          embApiKey = embProfile['apiKey'] as String? ?? embProfile['key'] as String? ?? '';
          embModel = embProfile['model'] as String? ?? '';
          embSame = false;
          embEnabled = true;
        } else if (embUseSame && pid == llmProfileId) {
          embSame = true;
          embEnabled = true;
        }

        final merged = <String, dynamic>{};
        if (pid == llmProfileId && connPreset != null) {
          merged.addAll(connPreset);
        } else {
          merged['max_tokens'] = ls['api-max-tokens'] ?? kv['api-max-tokens'];
          merged['context'] = ls['api-context'] ?? kv['api-context'];
          merged['temp'] = ls['gz_api_temp'] ?? kv['gz_api_temp'];
          merged['topp'] = ls['gz_api_topp'] ?? kv['gz_api_topp'];
        }
        for (final e in p.entries) {
          if (e.value != null && e.value != '') {
            merged[e.key] = e.value;
          }
        }

        await _insertApiConfig(merged, 'chat',
          embeddingUseSame: embSame,
          embeddingEnabled: embEnabled,
          embeddingEndpoint: embEndpoint,
          embeddingApiKey: embApiKey,
          embeddingModel: embModel,
          embeddingMaxChunkTokens: embMaxChunk,
        );
      }
      return;
    }

    final presets = <Map<String, dynamic>>[];
    for (final source in [kv, ls]) {
      for (final key in [
        'gz_api_connection_presets',
        'sc_api_connection_presets',
        'silly_cradle_api_presets',
        'api_connection_presets',
      ]) {
        final raw = source[key];
        if (raw == null) continue;
        _extractPresetsFromRaw(raw, presets);
      }
    }

    if (presets.isEmpty) {
      final endpoint = ls['api-endpoint'] as String? ??
                       kv['api-endpoint'] as String?;
      final apiKey = ls['api-key'] as String? ??
                     kv['api-key'] as String?;
      final model = ls['api-model'] as String? ??
                    kv['api-model'] as String?;
      if (endpoint != null && endpoint.isNotEmpty) {
        presets.add({
          'id': 'default',
          'name': 'Default',
          'endpoint': endpoint,
          'key': apiKey ?? '',
          'apiKey': apiKey ?? '',
          'model': model ?? '',
          'max_tokens': ls['api-max-tokens'] ?? kv['api-max-tokens'],
          'context': ls['api-context'] ?? kv['api-context'],
          'temp': ls['gz_api_temp'] ?? kv['gz_api_temp'],
          'topp': ls['gz_api_topp'] ?? kv['gz_api_topp'],
          'stream': ls['gz_api_stream'] ?? kv['gz_api_stream'],
          'reasoning_effort': ls['gz_api_reasoning_effort'] ?? kv['gz_api_reasoning_effort'],
          'reasoning_enabled': ls['gz_api_request_reasoning'] ?? kv['gz_api_request_reasoning'],
          'reasoning_start': ls['gz_api_reasoning_start'] ?? kv['gz_api_reasoning_start'],
          'reasoning_end': ls['gz_api_reasoning_end'] ?? kv['gz_api_reasoning_end'],
          'omit_reasoning': ls['gz_api_omit_reasoning'] ?? kv['gz_api_omit_reasoning'],
          'omit_reasoning_effort': ls['gz_api_omit_reasoning_effort'] ?? kv['gz_api_omit_reasoning_effort'],
        });
      }
    }

    if (topLevel != null) {
      final raw = topLevel['apiPresets'];
      if (raw != null) _extractPresetsFromRaw(raw, presets);
    }

    for (final preset in presets) {
      final embEnabled = preset['embedding_enabled'] ??
          ls['gz_embedding_enabled'] ?? kv['gz_embedding_enabled'];
      final embUseSame = preset['embedding_use_same'] ??
          ls['gz_embedding_use_same'] ?? kv['gz_embedding_use_same'];
      final embEndpoint = preset['embedding_endpoint'] ??
          ls['gz_embedding_endpoint'] ?? kv['gz_embedding_endpoint'] as String?;
      final embApiKey = preset['embedding_key'] ??
          ls['gz_embedding_key'] ?? kv['gz_embedding_key'] as String?;
      final embModel = preset['embedding_model'] ??
          ls['gz_embedding_model'] ?? kv['gz_embedding_model'] as String?;

      await _insertApiConfig(preset, preset['mode'] as String? ?? 'chat',
        embeddingUseSame: embUseSame == 'true' || embUseSame == true,
        embeddingEnabled: embEnabled == 'true' || embEnabled == true,
        embeddingEndpoint: (embEndpoint ?? '') as String,
        embeddingApiKey: (embApiKey ?? '') as String,
        embeddingModel: (embModel ?? '') as String,
      );
    }
  }

  Future<void> _insertApiConfig(Map<String, dynamic> preset, String mode, {
    bool embeddingUseSame = true,
    bool embeddingEnabled = false,
    String embeddingEndpoint = '',
    String embeddingApiKey = '',
    String embeddingModel = '',
    int embeddingMaxChunkTokens = 512,
  }) async {
    await _db.into(_db.apiConfigs).insertOnConflictUpdate(
          ApiConfigsCompanion.insert(
            configId: preset['id'] as String? ?? '',
            name: preset['name'] as String? ?? '',
            providerId: Value(
                preset['providerId'] as String? ??
                    preset['provider'] as String? ??
                    preset['providerType'] as String? ??
                    'openai_compatible'),
            endpoint: preset['endpoint'] != null
                ? Value(preset['endpoint'] as String)
                : const Value.absent(),
            apiKey: Value(
                preset['apiKey'] as String? ?? preset['key'] as String?),
            model: Value(preset['model'] as String?),
            mode: Value(mode),
            maxTokens: Value(_toInt(preset['max_tokens']) ?? 8000),
            contextSize: Value(_toInt(preset['context']) ?? 32000),
            temperature: Value(_toDouble(preset['temp']) ?? 0.7),
            topP: Value(_toDouble(preset['topp']) ?? 0.9),
            stream: Value(preset['stream'] as bool? ?? true),
            reasoningEffort: Value(preset['reasoningEffort'] as String? ??
                preset['reasoning_effort'] as String? ??
                _extractReasoningEffort(preset)),
            requestReasoning:
                Value(preset['requestReasoning'] as bool? ??
                    preset['reasoning_enabled'] as bool? ?? false),
            reasoningTagStart: Value(
                preset['reasoningTagStart'] as String? ??
                    (preset['reasoningTags'] as Map<String, dynamic>?)
                        ?['start'] as String?),
            reasoningTagEnd: Value(
                preset['reasoningTagEnd'] as String? ??
                    (preset['reasoningTags'] as Map<String, dynamic>?)
                        ?['end'] as String?),
            omitTemperature: Value(
                preset['omit_temperature'] as bool? ?? false),
            omitTopP: Value(
                preset['omit_top_p'] as bool? ?? false),
            omitReasoning: Value(
                preset['omit_reasoning'] as bool? ?? false),
            omitReasoningEffort: Value(
                preset['omit_reasoning_effort'] as bool? ?? false),
            embeddingUseSame: Value(embeddingUseSame),
            embeddingEnabled: Value(embeddingEnabled),
            embeddingEndpoint: Value(embeddingEndpoint),
            embeddingApiKey: Value(embeddingApiKey),
            embeddingModel: Value(embeddingModel),
            embeddingMaxChunkTokens: Value(embeddingMaxChunkTokens),
          ),
        );
  }

  void _extractPresetsFromRaw(dynamic raw, List<Map<String, dynamic>> presets) {
    if (raw is List) {
      for (final p in raw) {
        if (p is Map<String, dynamic>) presets.add(p);
      }
    } else if (raw is Map<String, dynamic>) {
      if (raw.containsKey('id') && raw.containsKey('endpoint')) {
        presets.add(raw);
      } else {
        for (final p in raw.values) {
          if (p is Map<String, dynamic>) presets.add(p);
        }
      }
    } else if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        _extractPresetsFromRaw(decoded, presets);
      } catch (_) {}
    }
  }

  Future<void> _importJsLorebookSettings(
      Map<String, dynamic> kv, Map<String, dynamic> ls) async {
    final prefs = await SharedPreferences.getInstance();

    final lorebooksRaw = kv['gz_lorebooks'];
    if (lorebooksRaw is Map<String, dynamic>) {
      final s = lorebooksRaw['settings'];
      if (s is Map<String, dynamic>) {
        await prefs.setString('lorebookSettings', jsonEncode(s));
        return;
      }
    }

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
    await _importJsChatsFromMap(kv, 'gz_chat_');

    final topLevelChats = kv['chats'];
    if (topLevelChats is Map<String, dynamic>) {
      for (final entry in topLevelChats.entries) {
        final charId = entry.key;
        final chatData = entry.value as Map<String, dynamic>?;
        if (chatData == null) continue;
        await _importJsChatData(charId, chatData);
      }
    }
  }

  Future<void> _importJsChatsFromMap(Map<String, dynamic> kv, String prefix) async {
    final chatKeys = kv.keys.where((k) => k.startsWith(prefix));

    for (final key in chatKeys) {
      final charId = key.substring(prefix.length);
      final chatData = kv[key] as Map<String, dynamic>?;
      if (chatData == null) continue;
      await _importJsChatData(charId, chatData);
    }
  }

  Future<void> _importJsChatData(String charId, Map<String, dynamic> chatData) async {
    if (charId == 'undefined' || charId.isEmpty) return;
    final sessions = chatData['sessions'] as Map<String, dynamic>?;
    if (sessions == null) return;

    final authorsNotesRaw = chatData['authorsNotes'] is Map<String, dynamic>
        ? chatData['authorsNotes'] as Map<String, dynamic>
        : null;

    for (final sessionEntry in sessions.entries) {
      final sessionIdx = int.tryParse(sessionEntry.key) ?? 0;
      final rawMessages = sessionEntry.value as List<dynamic>;

        final messages = rawMessages.map((m) {
          final msg = m as Map<String, dynamic>;
          var role = msg['role'] as String? ?? 'user';
          if (role == 'char') role = 'assistant';

          final content =
              (msg['text'] is String ? msg['text'] as String : null) ??
              (msg['content'] is String ? msg['content'] as String : null) ??
              (msg['mes'] is String ? msg['mes'] as String : null) ??
              '';

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
            'genTime': msg['genTime']?.toString(),
            'tokens': _toInt(msg['tokens']),
            'greetingIndex': _toInt(msg['greetingIndex'] ?? msg['greeting_index']),
            'contextRefs': msg['contextRefs'] is List ? List<String>.from(msg['contextRefs'].whereType<String>()) : <String>[],
            'swipeDirection': msg['swipeDirection'] is String ? msg['swipeDirection'] : (msg['swipe_direction'] is String ? msg['swipe_direction'] as String : 'none'),
            'isEditing': msg['isEditing'] == true || msg['is_editing'] == true,
            'isTyping': msg['isTyping'] == true || msg['is_typing'] == true,
            'guidanceText': msg['guidanceText'] is String ? msg['guidanceText'] as String : null,
            'guidanceType': msg['guidanceType'] is String ? msg['guidanceType'] as String : 'GENERATION',
            'triggeredLorebooks': msg['triggeredLorebooks'] is List ? List<String>.from(msg['triggeredLorebooks'].whereType<String>()) : <String>[],
            'triggeredMemories': msg['triggeredMemories'] is List ? List<String>.from(msg['triggeredMemories'].whereType<String>()) : <String>[],
            'swipesMeta': msg['swipesMeta'] is List ? (msg['swipesMeta'] as List).whereType<Map<String, dynamic>>().toList() : <Map<String, dynamic>>[],
            'memoryCoverage': msg['memoryCoverage'] is Map ? Map<String, dynamic>.from(msg['memoryCoverage']) : <String, dynamic>{},
            'time': msg['time'] is String ? msg['time'] as String : null,
          };
        }).toList();

        final sessionId = '${charId}_$sessionIdx';
        final chatUpdatedAt = _toInt(chatData['updatedAt']);
        final anRaw = authorsNotesRaw?[sessionEntry.key];
        final authorsNoteJson = _encodeAuthorsNote(anRaw);
        final draft = chatData['draft'] is String ? chatData['draft'] as String : null;
        final scrollAnchor = chatData['lastScrollAnchor'] is Map
            ? jsonEncode(chatData['lastScrollAnchor'])
            : null;
        await _db.into(_db.chatSessions).insertOnConflictUpdate(
              ChatSessionsCompanion.insert(
                sessionId: sessionId,
                characterId: charId,
                sessionIndex: sessionIdx,
                messagesJson: jsonEncode(messages),
                updatedAt: Value(chatUpdatedAt ?? DateTime.now().millisecondsSinceEpoch ~/ 1000),
                authorsNoteJson: Value(authorsNoteJson),
                draft: Value(draft),
                lastScrollAnchorJson: Value(scrollAnchor),
              ),
            );
      }

      final currentId = _toInt(chatData['currentId']);
      if (currentId != null) {
        await (_db.update(_db.characters)
              ..where((t) => t.charId.equals(charId)))
            .write(CharactersCompanion(
          currentSessionIndex: Value(currentId),
        ));
      }

      final memoryBooksRaw = chatData['memoryBooks'];
      if (memoryBooksRaw is Map) {
        for (final mbEntry in memoryBooksRaw.entries) {
          final mbSessionIdx = mbEntry.key;
          final mbData = mbEntry.value;
          if (mbData is! Map) continue;

          final mbFullSessionId = '${charId}_$mbSessionIdx';

          final entries = <Map<String, dynamic>>[];
          final rawEntries = mbData['entries'];
          if (rawEntries is List) {
            for (final e in rawEntries) {
              if (e is! Map) continue;
              entries.add({
                'id': e['id']?.toString() ?? '',
                'title': e['title'] is String ? e['title'] as String : (e['name'] is String ? e['name'] as String : ''),
                'keys': e['keys'] is List ? List<String>.from(e['keys'].whereType<String>()) : <String>[],
                'glazeKeys': e['glazeKeys'] is List ? List<String>.from(e['glazeKeys'].whereType<String>()) : <String>[],
                'content': e['content'] is String ? e['content'] as String : '',
                'rawContent': e['rawContent'] is String ? e['rawContent'] as String : null,
                'status': e['status'] is String ? e['status'] as String : 'active',
                'vectorSearch': e['vectorSearch'] == true,
                'messageIds': e['messageIds'] is List ? List<String>.from(e['messageIds'].whereType<String>()) : <String>[],
                'messageRange': e['messageRange'] is Map ? Map<String, dynamic>.from(e['messageRange'] as Map) : null,
                'source': e['source'] is String ? e['source'] as String : 'manual',
                'createdAt': e['createdAt']?.toString(),
                'updatedAt': e['updatedAt']?.toString(),
                'generatedAt': e['generatedAt']?.toString(),
              });
            }
          }

          final rawSettings = mbData['settings'] is Map ? mbData['settings'] as Map : {};
          final settings = <String, dynamic>{
            'enabled': rawSettings['enabled'] == true,
            'autoCreateEnabled': rawSettings['autoCreateEnabled'] == true,
            'autoGenerateEnabled': rawSettings['autoGenerateEnabled'] == true,
            'maxInjectedEntries': _toInt(rawSettings['maxInjectedEntries']) ?? 7,
            'autoCreateInterval': _toInt(rawSettings['autoCreateInterval']) ?? 15,
            'useDelayedAutomation': rawSettings['useDelayedAutomation'] == true,
            'injectionTarget': rawSettings['injectionTarget'] is String ? rawSettings['injectionTarget'] as String : 'summary_block',
            'batchSize': _toInt(rawSettings['batchSize']) ?? 3,
            'vectorSearchEnabled': rawSettings['vectorSearchEnabled'] == true,
            'keyMatchMode': rawSettings['keyMatchMode'] is String ? rawSettings['keyMatchMode'] as String : 'glaze',
            'generationSource': rawSettings['generationSource'] is String ? rawSettings['generationSource'] as String : 'current',
            'generationModel': rawSettings['generationModel'] is String ? rawSettings['generationModel'] as String : '',
            'generationEndpoint': rawSettings['generationEndpoint'] is String ? rawSettings['generationEndpoint'] as String : '',
            'generationApiKey': rawSettings['generationApiKey'] is String ? rawSettings['generationApiKey'] as String : '',
          };

          await _db.into(_db.memoryBookRows).insertOnConflictUpdate(
                MemoryBookRowsCompanion.insert(
                  sessionId: mbFullSessionId,
                  entriesJson: Value(jsonEncode(entries)),
                  settingsJson: Value(jsonEncode(settings)),
                  lastProcessedMessageCount: Value(
                      _toInt(mbData['automation'] is Map ? (mbData['automation'] as Map)['lastProcessedMessageCount'] : null) ?? 0),
                  updatedAt: Value(
                      _toInt(mbData['updatedAt']) ??
                      DateTime.now().millisecondsSinceEpoch ~/ 1000),
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

    final presetConnections = ls['gz_preset_connections'] ?? kv['gz_preset_connections'];
    if (presetConnections is String) {
      try { await prefs.setString('presetConnections', presetConnections); } catch (_) {}
    } else if (presetConnections is Map) {
      await prefs.setString('presetConnections', jsonEncode(presetConnections));
    }

    final personaConnections = ls['gz_persona_connections'] ?? kv['gz_persona_connections'];
    if (personaConnections is String) {
      try { await prefs.setString('personaConnections', personaConnections); } catch (_) {}
    } else if (personaConnections is Map) {
      await prefs.setString('personaConnections', jsonEncode(personaConnections));
    }

    for (final entry in ls.entries) {
      if (entry.key.startsWith('gz_imggen_') && entry.value is String) {
        await prefs.setString(entry.key, entry.value as String);
      }
    }

    final memSettingsRaw = ls['gz_memory_settings'] ?? kv['gz_memory_settings'];
    if (memSettingsRaw is String) {
      try { await prefs.setString('memorySettings', memSettingsRaw); } catch (_) {}
    } else if (memSettingsRaw is Map<String, dynamic>) {
      await prefs.setString('memorySettings', jsonEncode(memSettingsRaw));
    }

    final activeLlmId = ls['gz_active_llm_profile_id'] ?? kv['gz_active_llm_profile_id'];
    if (activeLlmId is String && activeLlmId.isNotEmpty) {
      await prefs.setString('activeApiConfigId', activeLlmId);
    }

    final globalVars = ls['gz_global_vars'];
    if (globalVars is String) {
      await prefs.setString('globalVars', globalVars);
    } else if (globalVars is Map<String, dynamic>) {
      await prefs.setString('globalVars', jsonEncode(globalVars));
    }

    for (final entry in ls.entries) {
      if (!entry.key.startsWith('gz_vars_')) continue;
      final parts = entry.key.substring('gz_vars_'.length).split('_');
      if (parts.length < 2) continue;
      final charId = parts[0];
      final sessionIdx = int.tryParse(parts[1]);
      if (sessionIdx == null) continue;
      final sessionId = '${charId}_$sessionIdx';
      final varsJson = entry.value is String
          ? entry.value as String
          : (entry.value is Map ? jsonEncode(entry.value) : null);
      if (varsJson != null) {
        await (_db.update(_db.chatSessions)
              ..where((t) => t.sessionId.equals(sessionId)))
            .write(ChatSessionsCompanion(sessionVarsJson: Value(varsJson)));
      }
    }
  }

  Future<void> _importJsGalleryFromCharacters(dynamic data) async {
    if (data is! List) return;
    for (final c in data) {
      final char = c as Map<String, dynamic>;
      final charId = char['id'] as String?;
      if (charId == null) continue;

      final galleryRaw = char['images'] ?? char['gallery'] ?? char['data']?['extensions']?['gallery'];
      if (galleryRaw is! List || galleryRaw.isEmpty) continue;

      final galleryEntries = <Map<String, dynamic>>[];
      for (int i = 0; i < galleryRaw.length; i++) {
        final g = galleryRaw[i];
        if (g is! Map<String, dynamic>) continue;

        final imageUrl = g['src'] as String? ?? g['url'] as String? ?? g['image'] as String?;
        if (imageUrl == null) continue;

        String? imagePath;
        if (imageUrl.startsWith('data:')) {
          final galId = g['id'] as String? ?? 'gal_${charId}_$i';
          final bytes = _dataUrlToBytes(imageUrl);
          if (bytes == null) continue;
          final mime = _dataUrlMime(imageUrl);
          final ext = mime == 'image/png' ? 'png'
              : mime == 'image/webp' ? 'webp' : 'jpg';
          imagePath = await _imageStorage.saveBytes(
            bytes,
            'gallery/$charId',
            galId,
            ext,
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

  String? _encodeAuthorsNote(dynamic raw) {
    if (raw == null) return null;
    if (raw is String) {
      if (raw.isEmpty) return null;
      return jsonEncode({'content': raw, 'role': 'system', 'insertionMode': 'relative', 'depth': 0, 'enabled': true});
    }
    if (raw is Map) {
      final content = raw['content'] is String ? raw['content'] as String : '';
      if (content.isEmpty) return null;
      return jsonEncode({
        'content': content,
        'role': raw['role'] is String ? raw['role'] as String : 'system',
        'insertionMode': (raw['insertion_mode'] is String ? raw['insertion_mode'] as String : null) ?? (raw['insertionMode'] is String ? raw['insertionMode'] as String : null) ?? 'relative',
        'depth': _toInt(raw['depth']) ?? 0,
        'enabled': raw['enabled'] is bool ? raw['enabled'] as bool : true,
      });
    }
    return null;
  }

  String? _extractExtensionsJson(Map<String, dynamic> char) {
    final extensions = char['extensions'] ?? char['data']?['extensions'];
    if (extensions is Map<String, dynamic> && extensions.isNotEmpty) {
      extensions.remove('gallery');
      if (extensions.isNotEmpty) return jsonEncode(extensions);
    }
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

  String _dataUrlMime(String dataUrl) {
    final end = dataUrl.indexOf(';');
    if (end == -1) return '';
    return dataUrl.substring(5, end);
  }
}
