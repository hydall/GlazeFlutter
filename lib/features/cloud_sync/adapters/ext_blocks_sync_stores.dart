import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/db/repositories/extension_presets_repository.dart';
import '../../../core/db/repositories/info_blocks_repository.dart';
import '../../../core/db/repositories/tracker_snapshot_repo.dart';
import '../../../core/models/tracker_snapshot.dart';
import '../../extensions/models/extension_preset.dart';
import '../../extensions/models/extensions_settings.dart';
import '../../extensions/models/info_block.dart';
import '../sync_repo_interfaces.dart';

// ---------------------------------------------------------------------------
// ExtensionPresetSyncStore
// ---------------------------------------------------------------------------

class ExtensionPresetSyncStore implements SyncExtensionPresetStore {
  final ExtensionPresetsRepository _repo;

  ExtensionPresetSyncStore(this._repo);

  @override
  Future<List<ExtensionPreset>> getAll() => _repo.getAll();

  @override
  Future<ExtensionPreset?> getById(String id) => _repo.getById(id);

  @override
  Future<void> put(ExtensionPreset p) async {
    final existing = await _repo.getById(p.id);
    if (existing == null) {
      await _repo.insert(p);
    } else {
      await _repo.updatePreset(p);
    }
  }

  @override
  Future<void> delete(String id) => _repo.deletePreset(id);
}

// ---------------------------------------------------------------------------
// ExtensionsSettingsSyncStore
// ---------------------------------------------------------------------------

class ExtensionsSettingsSyncStore implements SyncExtensionsSettingsStore {
  static const _storageKey = 'extensions_settings';

  @override
  Future<ExtensionsSettings> get() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_storageKey);
    if (jsonStr == null) return const ExtensionsSettings();
    try {
      return ExtensionsSettings.fromJson(
        jsonDecode(jsonStr) as Map<String, dynamic>,
      );
    } catch (_) {
      return const ExtensionsSettings();
    }
  }

  @override
  Future<void> put(ExtensionsSettings s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(s.toJson()));
  }
}

// ---------------------------------------------------------------------------
// InfoBlockSyncStore
// ---------------------------------------------------------------------------

class InfoBlockSyncStore implements SyncInfoBlockStore {
  final InfoBlocksRepository _repo;

  InfoBlockSyncStore(this._repo);

  @override
  Future<List<String>> getAllSessionIds() => _repo.getAllSessionIds();

  @override
  Future<List<InfoBlock>> getBySessionId(String sessionId) =>
      _repo.getBySessionId(sessionId);

  @override
  Future<void> deleteBySessionId(String sessionId) =>
      _repo.deleteBySessionId(sessionId);

  @override
  Future<void> insert(InfoBlock block) => _repo.insert(block);
}

/// Adapter wrapping [TrackerSnapshotRepo] for cloud sync. Per-session
/// collection, same shape as [InfoBlockSyncStore].
class TrackerSnapshotSyncStore implements SyncTrackerSnapshotStore {
  final TrackerSnapshotRepo _repo;

  TrackerSnapshotSyncStore(this._repo);

  @override
  Future<List<String>> getAllSessionIds() => _repo.getAllSessionIds();

  @override
  Future<List<Map<String, dynamic>>> getBySessionId(String sessionId) async {
    final snapshots = await _repo.getBySessionId(sessionId);
    return snapshots.map((s) => s.toJson()).toList();
  }

  @override
  Future<void> deleteBySessionId(String sessionId) =>
      _repo.deleteBySessionId(sessionId);

  @override
  Future<void> insertRaw(Map<String, dynamic> snapshot) async {
    await _repo.upsert(TrackerSnapshot.fromJson(snapshot));
  }
}
