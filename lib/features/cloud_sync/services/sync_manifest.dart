import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/models/character.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/persona.dart';
import '../../../core/models/preset.dart';
import '../../../core/models/api_config.dart';
import '../../../core/models/lorebook.dart';
import 'sync_serialization.dart';
import '../sync_models.dart';
import '../sync_repo_interfaces.dart';

class SyncManifestBuilder implements SyncManifestProvider {
  final SyncCharacterStore _characterRepo;
  final SyncChatStore _chatRepo;
  final SyncPersonaStore _personaRepo;
  final SyncPresetStore _presetRepo;
  final SyncApiConfigStore _apiRepo;
  final SyncLorebookStore _lorebookRepo;

  static const _manifestKey = 'gz_sync_manifest_v2';
  static const _deviceIdKey = 'gz_sync_device_id';
  static const _deletedKey = 'gz_sync_deleted_entries';

  SyncManifestBuilder({
    required SyncCharacterStore characterRepo,
    required SyncChatStore chatRepo,
    required SyncPersonaStore personaRepo,
    required SyncPresetStore presetRepo,
    required SyncApiConfigStore apiRepo,
    required SyncLorebookStore lorebookRepo,
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
      final json = c.toJson();
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
      final json = p.toJson();
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
    singletons['api_presets'] = apiConfigs.map((a) => a.toJson()).toList();

    final presets = await _presetRepo.getAll();
    singletons['theme_presets'] = presets.map((p) => p.toJson()).toList();

    for (final entry in singletons.entries) {
      final type = entry.key;
      final items = entry.value as List;
      final hash = SyncSerialization.computeSyncHash(entry.value);
      final key = entryKey(type, type);
      final prevEntry = previous.entries[key];
      final updatedAt = hash == prevEntry?.hash
          ? prevEntry!.updatedAt
          : items.isEmpty
              ? 0
              : now;

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

}
