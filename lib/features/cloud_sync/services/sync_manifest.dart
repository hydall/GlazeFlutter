import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

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
  final SyncThemePresetStore _themePresetRepo;

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
    required SyncThemePresetStore themePresetRepo,
  })  : _characterRepo = characterRepo,
        _chatRepo = chatRepo,
        _personaRepo = personaRepo,
        _presetRepo = presetRepo,
        _apiRepo = apiRepo,
        _lorebookRepo = lorebookRepo,
        _themePresetRepo = themePresetRepo;

  @override
  Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_deviceIdKey);
    if (id == null) {
      id = '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999)}';
      await prefs.setString(_deviceIdKey, id);
    }
    return id;
  }

  /// [cloudManifest] — when pulling, used to avoid bumping updatedAt to now for
  /// entities that only differ from a stale local manifest but match cloud.
  @override
  Future<SyncManifest> buildLocalManifest({SyncManifest? cloudManifest}) async {
    final deviceId = await getDeviceId();
    final now = DateTime.now().millisecondsSinceEpoch;
    final entries = <String, SyncManifestEntry>{};

    final previous = await readLocalManifest();

    final characters = await _characterRepo.getAll();
    for (final c in characters) {
      final json = c.toJson();
      final hash = SyncSerialization.computeSyncHash(
        _stripLocalPaths(json),
      );
      final key = entryKey('character', c.id);
      final prevEntry = previous.entries[key];
      final cloudEntry = cloudManifest?.entries[key];
      var updatedAt = _resolveUpdatedAt(
        hash: hash,
        prevEntry: prevEntry,
        cloudEntry: cloudEntry,
        now: now,
      );
      if (c.updatedAt > updatedAt) updatedAt = c.updatedAt;

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
      final hash = SyncSerialization.computeSyncHash(
        _stripLocalPaths(json),
      );
      final key = entryKey('persona', p.id);
      final prevEntry = previous.entries[key];
      final cloudEntry = cloudManifest?.entries[key];
      final updatedAt = _resolveUpdatedAt(
        hash: hash,
        prevEntry: prevEntry,
        cloudEntry: cloudEntry,
        now: now,
      );

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
      final hash = SyncSerialization.computeChatMetadataHash(s);
      final key = entryKey('chat', s.sessionId);
      final prevEntry = previous.entries[key];
      final cloudEntry = cloudManifest?.entries[key];
      var updatedAt = _resolveUpdatedAt(
        hash: hash,
        prevEntry: prevEntry,
        cloudEntry: cloudEntry,
        now: now,
      );
      if (s.updatedAt > updatedAt) updatedAt = s.updatedAt;

      entries[key] = SyncManifestEntry(
        type: 'chat',
        id: s.sessionId,
        path: cloudPath('chat', s.sessionId),
        updatedAt: updatedAt,
        hash: hash,
      );
    }

    await _addSingletons(entries, previous, now, cloudManifest);
    await _addDeletedEntries(entries, now);

    return SyncManifest(
      deviceId: deviceId,
      createdAt: previous.createdAt,
      lastSync: previous.lastSync,
      entries: entries,
    );
  }

  /// Decides manifest updatedAt without spurious "now" bumps on hash drift.
  static int _resolveUpdatedAt({
    required String hash,
    required SyncManifestEntry? prevEntry,
    required SyncManifestEntry? cloudEntry,
    required int now,
  }) {
    if (prevEntry != null && hash == prevEntry.hash) {
      return prevEntry.updatedAt;
    }
    if (cloudEntry != null && hash == cloudEntry.hash) {
      return cloudEntry.updatedAt;
    }
    if (prevEntry != null &&
        cloudEntry != null &&
        prevEntry.hash == cloudEntry.hash) {
      // Was aligned with cloud; local DB changed → treat as local edit.
      return now;
    }
    // No previous manifest entry — entity was never synced from this device.
    // Don't claim "now" (would always beat cloud); let entity-level updatedAt
    // (c.updatedAt, s.updatedAt) override if the entity was genuinely edited.
    return prevEntry?.updatedAt ?? 0;
  }

  /// Remove device-specific fields from entity JSON before hashing so that
  /// the same logical entity produces the same hash on every device.
  /// Gallery is excluded entirely: image paths are device-local, and gallery
  /// metadata (ids, labels, order) can drift between devices without
  /// representing a meaningful content change.
  static Map<String, dynamic> _stripLocalPaths(Map<String, dynamic> json) {
    final out = Map<String, dynamic>.from(json);
    out.remove('avatarPath');
    out.remove('gallery');
    return out;
  }

  Future<void> _addSingletons(
    Map<String, SyncManifestEntry> entries,
    SyncManifest previous,
    int now,
    SyncManifest? cloudManifest,
  ) async {
    final singletons = <String, dynamic>{};

    final lorebooks = await _lorebookRepo.getAll();
    singletons['lorebooks'] = lorebooks.map((l) => l.toJson()).toList();

    final apiConfigs = await _apiRepo.getAll();
    singletons['api_presets'] = apiConfigs
        .map((a) => a.copyWith(apiKey: '', embeddingApiKey: '').toJson())
        .toList();

    final presets = await _presetRepo.getAll();
    singletons['theme_presets'] = presets.map((p) => p.toJson()).toList();

    final uiThemes = await _themePresetRepo.getAll();
    singletons['ui_themes'] = uiThemes.map((t) => t.toJson()).toList();

    for (final entry in singletons.entries) {
      final type = entry.key;
      final items = entry.value as List;
      final hash = SyncSerialization.computeSyncHash(entry.value);
      final key = entryKey(type, type);
      final prevEntry = previous.entries[key];
      final cloudEntry = cloudManifest?.entries[key];
      final updatedAt = items.isEmpty
          ? 0
          : _resolveUpdatedAt(
              hash: hash,
              prevEntry: prevEntry,
              cloudEntry: cloudEntry,
              now: now,
            );

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

  @override
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

  @override
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

  @override
  Future<void> clearLocalManifest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_manifestKey);
    await prefs.remove(_deletedKey);
  }

  @override
  Future<void> clearDeleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_deletedKey);
  }

}
