import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/db/repositories/character_repo.dart';
import '../../../core/db/repositories/chat_repo.dart';
import '../../../core/db/repositories/persona_repo.dart';
import '../../../core/db/repositories/preset_repo.dart';
import '../../../core/db/repositories/api_config_repo.dart';
import '../../../core/db/repositories/lorebook_repo.dart';
import 'sync_serialization.dart';
import '../sync_models.dart';

class SyncManifestBuilder {
  final CharacterRepo _characterRepo;
  final ChatRepo _chatRepo;
  final PersonaRepo _personaRepo;
  final PresetRepo _presetRepo;
  final ApiConfigRepo _apiRepo;
  final LorebookRepo _lorebookRepo;

  static const _manifestKey = 'gz_sync_manifest_v2';
  static const _deviceIdKey = 'gz_sync_device_id';
  static const _deletedKey = 'gz_sync_deleted_entries';

  SyncManifestBuilder({
    required CharacterRepo characterRepo,
    required ChatRepo chatRepo,
    required PersonaRepo personaRepo,
    required PresetRepo presetRepo,
    required ApiConfigRepo apiRepo,
    required LorebookRepo lorebookRepo,
  })  : _characterRepo = characterRepo,
        _chatRepo = chatRepo,
        _personaRepo = personaRepo,
        _presetRepo = presetRepo,
        _apiRepo = apiRepo,
        _lorebookRepo = lorebookRepo;

  Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_deviceIdKey);
    if (id == null) {
      id = '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999)}';
      await prefs.setString(_deviceIdKey, id);
    }
    return id;
  }

  Future<SyncManifest> buildLocalManifest() async {
    final deviceId = await getDeviceId();
    final now = DateTime.now().millisecondsSinceEpoch;
    final entries = <String, SyncManifestEntry>{};

    final previous = await readLocalManifest();

    final characters = await _characterRepo.getAll();
    for (final c in characters) {
      final json = _characterToJson(c);
      final hash = SyncSerialization.computeSyncHash(json);
      final key = entryKey('character', c.id);
      final prevEntry = previous.entries[key];
      final updatedAt = hash == prevEntry?.hash
          ? prevEntry!.updatedAt
          : now;

      entries[key] = SyncManifestEntry(
        type: 'character',
        id: c.id,
        path: cloudPath('character', c.id),
        updatedAt: updatedAt,
        hash: hash,
      );
    }

    final personas = await _personaRepo.getAll();
    for (final p in personas) {
      final json = _personaToJson(p);
      final hash = SyncSerialization.computeSyncHash(json);
      final key = entryKey('persona', p.id);
      final prevEntry = previous.entries[key];
      final updatedAt = hash == prevEntry?.hash ? prevEntry!.updatedAt : now;

      entries[key] = SyncManifestEntry(
        type: 'persona',
        id: p.id,
        path: cloudPath('persona', p.id),
        updatedAt: updatedAt,
        hash: hash,
      );
    }

    final sessions = await _chatRepo.getAllSessionMetadata();
    for (final s in sessions) {
      final hash = SyncSerialization.computeSyncHash(s.sessionId);
      final key = entryKey('chat', s.sessionId);
      final prevEntry = previous.entries[key];
      final updatedAt = prevEntry?.updatedAt ?? now;

      entries[key] = SyncManifestEntry(
        type: 'chat',
        id: s.sessionId,
        path: cloudPath('chat', s.sessionId),
        updatedAt: updatedAt,
        hash: hash,
      );
    }

    await _addSingletons(entries, previous, now);
    await _addDeletedEntries(entries, now);

    return SyncManifest(
      deviceId: deviceId,
      createdAt: previous.createdAt,
      lastSync: previous.lastSync,
      entries: entries,
    );
  }

  Future<void> _addSingletons(
    Map<String, SyncManifestEntry> entries,
    SyncManifest previous,
    int now,
  ) async {
    final singletons = <String, dynamic>{};

    final lorebooks = await _lorebookRepo.getAll();
    singletons['lorebooks'] = lorebooks.map((l) => l.toJson()).toList();

    final apiConfigs = await _apiRepo.getAll();
    singletons['api_presets'] = apiConfigs.map((a) => _apiConfigToJson(a)).toList();

    final presets = await _presetRepo.getAll();
    singletons['theme_presets'] = presets.map((p) => _presetToJson(p)).toList();

    for (final entry in singletons.entries) {
      final type = entry.key;
      final hash = SyncSerialization.computeSyncHash(entry.value);
      final key = entryKey(type, type);
      final prevEntry = previous.entries[key];
      final updatedAt = hash == prevEntry?.hash ? prevEntry!.updatedAt : now;

      entries[key] = SyncManifestEntry(
        type: type,
        id: type,
        path: cloudPath(type, type),
        updatedAt: updatedAt,
        hash: hash,
      );
    }
  }

  Future<void> _addDeletedEntries(
    Map<String, SyncManifestEntry> entries,
    int now,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_deletedKey);
    if (raw == null) return;

    final deleted = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    for (final d in deleted) {
      final type = d['type'] as String;
      final id = d['id'] as String;
      final key = entryKey(type, id);
      if (!entries.containsKey(key)) {
        entries[key] = SyncManifestEntry(
          type: type,
          id: id,
          path: cloudPath(type, id),
          updatedAt: now,
          hash: '',
          deleted: true,
        );
      }
    }
  }

  Future<SyncManifest> readLocalManifest() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_manifestKey);
    if (raw == null) return const SyncManifest(deviceId: '', createdAt: 0);
    try {
      return SyncManifest.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const SyncManifest(deviceId: '', createdAt: 0);
    }
  }

  Future<void> writeLocalManifest(SyncManifest manifest) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_manifestKey, jsonEncode(manifest.toJson()));
  }

  Future<void> markDeleted(String type, String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_deletedKey);
    final deleted = raw != null
        ? (jsonDecode(raw) as List).cast<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];
    deleted.add({'type': type, 'id': id});
    await prefs.setString(_deletedKey, jsonEncode(deleted));
  }

  Future<void> clearDeleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_deletedKey);
  }

  Map<String, dynamic> _characterToJson(dynamic c) => {
    'id': c.id, 'name': c.name, 'description': c.description,
    'personality': c.personality, 'scenario': c.scenario,
    'firstMes': c.firstMes, 'mesExample': c.mesExample,
    'systemPrompt': c.systemPrompt, 'postHistoryInstructions': c.postHistoryInstructions,
    'creator': c.creator, 'creatorNotes': c.creatorNotes,
    'tags': c.tags, 'alternateGreetings': c.alternateGreetings,
  };

  Map<String, dynamic> _personaToJson(dynamic p) => {
    'id': p.id, 'name': p.name, 'prompt': p.prompt,
  };

  Map<String, dynamic> _apiConfigToJson(dynamic a) => {
    'id': a.id, 'name': a.name, 'providerId': a.providerId,
    'endpoint': a.endpoint, 'model': a.model,
    'maxTokens': a.maxTokens, 'contextSize': a.contextSize,
    'temperature': a.temperature, 'topP': a.topP,
    'stream': a.stream,
  };

  Map<String, dynamic> _presetToJson(dynamic p) => {
    'id': p.id, 'name': p.name, 'author': p.author,
  };
}
