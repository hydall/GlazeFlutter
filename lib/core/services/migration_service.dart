import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../utils/id_generator.dart';
import '../utils/time_helpers.dart';
import 'preset_defaults.dart';

import '../models/api_config.dart';
import '../models/character.dart';
import '../models/chat_message.dart';
import '../models/persona.dart';
import '../models/preset.dart';
import '../db/repositories/api_config_repo.dart';
import '../db/repositories/character_repo.dart';
import '../db/repositories/chat_repo.dart';
import '../db/repositories/persona_repo.dart';
import '../db/repositories/preset_repo.dart';
import 'image_storage_service.dart';

class MigrationResult {
  int characters = 0;
  int sessions = 0;
  int apiConfigs = 0;
  int presets = 0;
  int personas = 0;
  int errors = 0;

  @override
  String toString() =>
      'Characters: $characters, Sessions: $sessions, APIs: $apiConfigs, Presets: $presets, Personas: $personas'
      '${errors > 0 ? ', Errors: $errors' : ''}';
}

class MigrationService {
  final CharacterRepo _charRepo;
  final ChatRepo _chatRepo;
  final PersonaRepo _personaRepo;
  final PresetRepo _presetRepo;
  final ApiConfigRepo _apiRepo;
  final ImageStorageService _imageStorage;

  MigrationService({
    required CharacterRepo charRepo,
    required ChatRepo chatRepo,
    required PersonaRepo personaRepo,
    required PresetRepo presetRepo,
    required ApiConfigRepo apiRepo,
    required ImageStorageService imageStorage,
  })  : _charRepo = charRepo,
        _chatRepo = chatRepo,
        _personaRepo = personaRepo,
        _presetRepo = presetRepo,
        _apiRepo = apiRepo,
        _imageStorage = imageStorage;

  Future<MigrationResult> importGlzBackup(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    final raw = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;

    if (raw['_isGlazeBackup'] != true && raw['characters'] == null) {
      throw FormatException('Not a valid Glaze backup file');
    }

    final result = MigrationResult();
    final kv = Map<String, dynamic>.from(raw['keyvalue'] ?? {});
    final ls = Map<String, dynamic>.from(raw['localStorage'] ?? {});

    await _importCharacters(raw['characters'], result);
    await _importPersonas(raw['personas'], result);
    await _importChats(kv, result);
    await _importApiConfigs(kv, result);
    await _importPresets(ls, result);
    await _importActiveSelections(kv, ls);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('gz_migration_done', true);

    return result;
  }

  Future<void> _importCharacters(dynamic data, MigrationResult result) async {
    if (data is! List) return;
    for (final charJson in data) {
      try {
        final json = Map<String, dynamic>.from(charJson as Map);
        String? avatarPath;
        final avatar = json['avatar'] as String?;
        if (avatar != null && avatar.startsWith('data:')) {
          final id = json['id'] as String? ?? _generateId();
          avatarPath = await _imageStorage.saveAvatarFromDataUrl(id, avatar);
        }

        final char = Character(
          id: json['id'] as String? ?? _generateId(),
          name: (json['name'] as String?) ?? 'Unknown',
          avatarPath: avatarPath,
          description: json['description'] as String?,
          personality: json['personality'] as String?,
          scenario: json['scenario'] as String?,
          firstMes: json['first_mes'] as String?,
          mesExample: json['mes_example'] as String?,
          systemPrompt: json['system_prompt'] as String?,
          postHistoryInstructions: json['post_history_instructions'] as String?,
          creator: json['creator'] as String?,
          creatorNotes: json['creator_notes'] as String?,
          color: json['color'] as String?,
          tags: _toStringList(json['tags']),
          alternateGreetings: _toStringList(json['alternate_greetings']),
          updatedAt: _toInt(json['updatedAt']) ?? currentTimestampSeconds(),
        );
        await _charRepo.put(char);
        result.characters++;
      } catch (_) {
        result.errors++;
      }
    }
  }

  Future<void> _importPersonas(dynamic data, MigrationResult result) async {
    if (data is! List) return;
    for (final pJson in data) {
      try {
        final json = Map<String, dynamic>.from(pJson as Map);
        String? avatarPath;
        final avatar = json['avatar'] as String?;
        if (avatar != null && avatar.startsWith('data:')) {
          final id = json['id'] as String? ?? _generateId();
          avatarPath = await _imageStorage.saveAvatarFromDataUrl(id, avatar);
        }

        final persona = Persona(
          id: json['id'] as String? ?? _generateId(),
          name: (json['name'] as String?) ?? 'User',
          prompt: json['prompt'] as String?,
          avatarPath: avatarPath,
          createdAt: _toInt(json['createdAt'] ?? json['created_at']) ??
              currentTimestampSeconds(),
        );
        await _personaRepo.put(persona);
        result.personas++;
      } catch (_) {
        result.errors++;
      }
    }
  }

  Future<void> _importChats(Map<String, dynamic> kv, MigrationResult result) async {
    for (final entry in kv.entries) {
      if (!entry.key.startsWith('gz_chat_')) continue;

      final charId = entry.key.replaceFirst('gz_chat_', '');
      final chatData = entry.value;
      if (chatData is! Map<String, dynamic>) continue;

      final sessions = chatData['sessions'] as Map<String, dynamic>?;
      if (sessions == null) continue;

      for (final sessionEntry in sessions.entries) {
        try {
          final sessionIndex = int.tryParse(sessionEntry.key) ?? 0;
          final messagesJson = sessionEntry.value;
          if (messagesJson is! List) continue;

          final messages = <ChatMessage>[];
          for (final mJson in messagesJson) {
            if (mJson is! Map<String, dynamic>) continue;
            messages.add(_mapMessage(mJson));
          }

          final session = ChatSession(
            id: '${charId}_$sessionIndex',
            characterId: charId,
            sessionIndex: sessionIndex,
            messages: messages,
            updatedAt: _toInt(chatData['sessionDates']?[sessionEntry.key]) ?? 0,
          );
          await _chatRepo.put(session);
          result.sessions++;
        } catch (_) {
          result.errors++;
        }
      }
    }
  }

  Future<void> _importApiConfigs(Map<String, dynamic> kv, MigrationResult result) async {
    final data = kv['gz_api_connection_presets'];
    if (data is! List) return;

    for (final cfgJson in data) {
      try {
        final json = Map<String, dynamic>.from(cfgJson as Map);
        final config = ApiConfig(
          id: json['id'] as String? ?? _generateId(),
          name: (json['name'] as String?) ?? '',
          providerId: json['providerId'] as String? ?? 'openai_compatible',
          endpoint: json['endpoint'] as String? ?? '',
          apiKey: json['key'] as String? ?? '',
          model: json['model'] as String? ?? '',
          maxTokens: _toInt(json['max_tokens']) ?? 8000,
          contextSize: _toInt(json['context']) ?? 32000,
          temperature: _toDouble(json['temp']) ?? 0.7,
          topP: _toDouble(json['topp']) ?? 0.9,
          stream: json['stream'] as bool? ?? true,
        );
        await _apiRepo.put(config);
        result.apiConfigs++;
      } catch (_) {
        result.errors++;
      }
    }
  }

  Future<void> _importPresets(Map<String, dynamic> ls, MigrationResult result) async {
    final raw = ls['silly_cradle_presets'];
    if (raw == null) return;

    Map<String, dynamic> presetsMap;
    if (raw is String) {
      presetsMap = jsonDecode(raw) as Map<String, dynamic>;
    } else if (raw is Map<String, dynamic>) {
      presetsMap = raw;
    } else {
      return;
    }

    final inner = presetsMap['presets'];
    if (inner is Map<String, dynamic>) {
      presetsMap = inner;
    }

    for (final entry in presetsMap.entries) {
      if (entry.value is! Map<String, dynamic>) continue;
      try {
        final preset = _mapPreset(entry.value as Map<String, dynamic>);
        await _presetRepo.put(preset);
        result.presets++;
      } catch (_) {
        result.errors++;
      }
    }
  }

  Future<void> _importActiveSelections(
    Map<String, dynamic> kv,
    Map<String, dynamic> ls,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    final activePresetId = ls['silly_cradle_current_preset_id'] as String?;
    if (activePresetId != null) {
      await prefs.setString('active_preset_id', activePresetId);
    }

    final activePersonaRaw = ls['gz_active_persona'];
    if (activePersonaRaw is String) {
      try {
        final persona = jsonDecode(activePersonaRaw) as Map<String, dynamic>;
        final id = persona['id'] as String?;
        if (id != null) await prefs.setString('activePersonaId', id);
      } catch (_) {}
    } else if (activePersonaRaw is Map) {
      final id = activePersonaRaw['id'] as String?;
      if (id != null) await prefs.setString('activePersonaId', id);
    }

    final personaConnsRaw = ls['gz_persona_connections'];
    if (personaConnsRaw is String) {
      try {
        final parsed = jsonDecode(personaConnsRaw) as Map<String, dynamic>;
        final conns = PersonaConnections.fromJson({
          'character': parsed['character'] ?? {},
          'chat': parsed['chat'] ?? {},
        });
        await prefs.setString('personaConnections', jsonEncode(conns.toJson()));
      } catch (_) {}
    } else if (personaConnsRaw is Map) {
      try {
        final conns = PersonaConnections.fromJson({
          'character': personaConnsRaw['character'] ?? {},
          'chat': personaConnsRaw['chat'] ?? {},
        });
        await prefs.setString('personaConnections', jsonEncode(conns.toJson()));
      } catch (_) {}
    }
  }

  ChatMessage _mapMessage(Map<String, dynamic> json) {
    var role = json['role'] as String? ?? 'user';
    if (role == 'char') role = 'assistant';

    final content = (json['text'] as String?) ?? (json['mes'] as String?) ?? '';

    final swipes = <String>[];
    final rawSwipes = json['swipes'];
    if (rawSwipes is List) {
      for (final s in rawSwipes) {
        swipes.add(s.toString());
      }
    }
    if (swipes.isEmpty && content.isNotEmpty) {
      swipes.add(content);
    }

    String? reasoning;
    final rawReasoning = json['reasoning'];
    if (rawReasoning is String && rawReasoning.isNotEmpty) {
      reasoning = rawReasoning;
    } else if (json['swipesMeta'] is List) {
      final swipeId = _toInt(json['swipeId']) ?? 0;
      final meta = (json['swipesMeta'] as List).safeGet(swipeId);
      if (meta is Map) {
        final r = meta['reasoning'] as String?;
        if (r != null && r.isNotEmpty) reasoning = r;
      }
    }

    final persona = json['persona'];
    String? personaId;
    String? personaName;
    if (persona is Map) {
      personaId = persona['id'] as String?;
      personaName = persona['name'] as String?;
    }

    return ChatMessage(
      id: json['id'] as String? ?? _generateId(),
      role: role,
      content: content,
      timestamp: _toInt(json['timestamp']),
      personaId: personaId,
      personaName: personaName,
      swipes: swipes,
      swipeId: _toInt(json['swipeId']) ?? 0,
      reasoning: reasoning,
      isHidden: json['isHidden'] as bool? ?? false,
      isError: json['isError'] as bool? ?? false,
      genTime: json['genTime'] as String?,
      tokens: _toInt(json['tokens']),
    );
  }

  Preset _mapPreset(Map<String, dynamic> json) {
    final blocks = <PresetBlock>[];
    final rawBlocks = json['blocks'];
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
          insertionMode: (b['insertion_mode'] as String?) ?? (b['insertionMode'] as String?) ?? 'relative',
          depth: _toInt(b['depth']),
          prefix: b['prefix'] as String?,
          isStashed: b['isStashed'] as bool? ?? false,
        ));
      }
    }

    final regexes = <PresetRegex>[];
    final rawRegexes = json['regexes'];
    if (rawRegexes is List) {
      for (final r in rawRegexes) {
        if (r is! Map<String, dynamic>) continue;
        regexes.add(PresetRegex(
          id: r['id'] as String? ?? _generateId(),
          name: r['name'] as String? ?? r['scriptName'] as String? ?? '',
          regex: r['regex'] as String? ?? r['findRegex'] as String? ?? '',
          replacement: r['replacement'] as String? ?? r['replaceString'] as String? ?? '',
          trimOut: r['trimOut'] as String? ?? _joinTrimStrings(r['trimStrings']),
          placement: _toIntList(r['placement']),
          ephemerality: _toIntList(r['ephemerality']),
          disabled: r['disabled'] as bool? ?? false,
          macroRules: (r['macroRules'] ?? r['substituteRegex'] ?? 0).toString(),
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

  String _generateId() {
    return generateId() +
        Random().nextInt(9999).toRadixString(36);
  }

  List<String> _toStringList(dynamic value) {
    if (value is List) return value.map((e) => e.toString()).toList();
    return [];
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
}

extension on List {
  dynamic safeGet(int index) =>
      index >= 0 && index < length ? this[index] : null;
}
