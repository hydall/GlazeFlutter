import 'dart:convert';
import 'dart:io';

import '../cloud_adapter.dart';
import '../sync_models.dart';
import 'sync_conflict.dart';
import 'sync_manifest.dart';
import 'sync_queue.dart';
import 'sync_serialization.dart';
import '../../../core/db/repositories/character_repo.dart';
import '../../../core/db/repositories/chat_repo.dart';
import '../../../core/db/repositories/persona_repo.dart';
import '../../../core/db/repositories/preset_repo.dart';
import '../../../core/db/repositories/api_config_repo.dart';
import '../../../core/db/repositories/lorebook_repo.dart';
import '../../../core/services/image_storage_service.dart';
import '../../../core/models/character.dart';
import '../../../core/models/persona.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/lorebook.dart';
import '../../../core/models/api_config.dart';
import '../../../core/models/preset.dart';

class SyncProgress {
  final int current;
  final int total;
  final String? message;

  const SyncProgress({this.current = 0, this.total = 0, this.message});
}

class SyncEngine {
  final CloudAdapter _adapter;
  final SyncManifestBuilder _manifestBuilder;
  final CharacterRepo _characterRepo;
  final ChatRepo _chatRepo;
  final PersonaRepo _personaRepo;
  final PresetRepo _presetRepo;
  final ApiConfigRepo _apiRepo;
  final LorebookRepo _lorebookRepo;
  final ImageStorageService _imageStorage;
  final SyncQueue _queue = SyncQueue();

  SyncEngine(
    this._adapter,
    this._manifestBuilder,
    this._characterRepo,
    this._chatRepo,
    this._personaRepo,
    this._presetRepo,
    this._apiRepo,
    this._lorebookRepo,
    this._imageStorage,
  );

  Future<void> pushEntities({
    required void Function(SyncProgress) onProgress,
  }) async {
    await _adapter.ensureFolder(cloudBase);
    await _adapter.ensureFolder('$cloudBase/characters');
    await _adapter.ensureFolder('$cloudBase/personas');
    await _adapter.ensureFolder('$cloudBase/chats');
    await _adapter.ensureFolder('$cloudBase/galleries');

    final localManifest = await _manifestBuilder.buildLocalManifest();
    SyncManifest? cloudManifest;
    try {
      final raw = await _adapter.download(cloudPath('manifest', 'manifest'));
      cloudManifest = SyncManifest.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {}

    final entries = localManifest.entries.values.toList();
    var processed = 0;

    for (final entry in entries) {
      processed++;
      onProgress(SyncProgress(
        current: processed,
        total: entries.length,
        message: 'Pushing ${entry.type}:${entry.id}',
      ));

      final cloudEntry = cloudManifest?.entries[entry.key];

      if (entry.deleted) {
        if (cloudEntry != null && !cloudEntry.deleted) {
          await SyncSerialization.deleteCloudFileIfExists(_adapter, entry);
        }
        continue;
      }

      if (cloudEntry != null && cloudEntry.hash == entry.hash && !cloudEntry.deleted) {
        continue;
      }

      await _queue.enqueue(() => _pushEntry(entry));
    }

    final updatedManifest = localManifest.copyWith(
      lastSync: DateTime.now().millisecondsSinceEpoch,
    );
    await _adapter.upload(
      cloudPath('manifest', 'manifest'),
      jsonEncode(updatedManifest.toJson()),
    );
    await _manifestBuilder.writeLocalManifest(updatedManifest);
  }

  Future<void> pullEntities({
    required void Function(SyncProgress) onProgress,
    required void Function(SyncConflict) onConflict,
  }) async {
    final raw = await _adapter.download(cloudPath('manifest', 'manifest'));
    final cloudManifest = SyncManifest.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    final localManifest = await _manifestBuilder.buildLocalManifest();

    final entries = cloudManifest.entries.values.toList();
    var processed = 0;

    for (final cloudEntry in entries) {
      processed++;
      onProgress(SyncProgress(
        current: processed,
        total: entries.length,
        message: 'Pulling ${cloudEntry.type}:${cloudEntry.id}',
      ));

      final localEntry = localManifest.entries[cloudEntry.key];

      if (cloudEntry.hash == localEntry?.hash && cloudEntry.deleted == localEntry?.deleted) {
        continue;
      }

      if (SyncConflictDetector.needsConflict(localEntry, cloudEntry)) {
        final name = SyncConflictDetector.getConflictName(
          cloudEntry.type, null, null, cloudEntry.id,
        );
        onConflict(SyncConflict(
          key: cloudEntry.key,
          type: cloudEntry.type,
          id: cloudEntry.id,
          localEntry: localEntry!,
          cloudEntry: cloudEntry,
          name: name,
        ));
        continue;
      }

      await _queue.enqueue(() => _pullEntry(cloudEntry));
    }

    await _manifestBuilder.writeLocalManifest(cloudManifest.copyWith(
      lastSync: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  Future<void> resolveConflict(SyncConflict conflict, String choice) async {
    if (choice == 'cloud') {
      await _pullEntry(conflict.cloudEntry);
    }
  }

  Future<bool> cloudHasData() async {
    try {
      final files = await _adapter.listFolder(cloudBase);
      return files.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> wipeCloudData({
    required void Function(SyncProgress) onProgress,
  }) async {
    await _adapter.deleteFolder(cloudBase);
    await _adapter.invalidateFolderCache();
    await _adapter.ensureFolder(cloudBase);
  }

  Future<void> _pushEntry(SyncManifestEntry entry) async {
    final data = await _readLocalEntity(entry.type, entry.id);
    if (data == null) return;
    final json = jsonEncode(data);
    if (json.length > maxSyncPayloadBytes) {
      throw Exception('Payload exceeds limit for ${entry.key}');
    }
    await _adapter.upload(entry.path, json);

    if (entry.type == 'character') {
      await _pushCharacterAvatar(entry.id);
    }
  }

  Future<void> _pullEntry(SyncManifestEntry entry) async {
    if (entry.deleted) {
      await _deleteLocalEntity(entry.type, entry.id);
      return;
    }

    final cloudData = await SyncSerialization.readCloudEntity(_adapter, entry);
    if (cloudData == null) return;

    await _applyCloudEntity(entry.type, entry.id, cloudData);

    if (entry.type == 'character') {
      await _pullCharacterAvatar(entry.id);
    }
  }

  Future<Map<String, dynamic>?> _readLocalEntity(String type, String id) async {
    try {
      switch (type) {
        case 'character':
          final c = await _characterRepo.getById(id);
          if (c == null) return null;
          return c.toJson();
        case 'persona':
          final p = await _personaRepo.getById(id);
          if (p == null) return null;
          return p.toJson();
        case 'chat':
          final s = await _chatRepo.getById(id);
          if (s == null) return null;
          return s.toJson();
        case 'lorebooks':
          final lorebook = await _lorebookRepo.getById(id);
          if (lorebook == null) return null;
          return lorebook.toJson();
        case 'api_presets':
          final config = await _apiRepo.getById(id);
          if (config == null) return null;
          return config.toJson();
        case 'theme_presets':
          final preset = await _presetRepo.getById(id);
          if (preset == null) return null;
          return preset.toJson();
        default:
          return null;
      }
    } catch (_) {
      return null;
    }
  }

  Future<void> _applyCloudEntity(String type, String id, Map<String, dynamic> data) async {
    try {
      switch (type) {
        case 'character':
          final c = Character.fromJson(data);
          await _characterRepo.put(c);
          break;
        case 'persona':
          final p = Persona.fromJson(data);
          await _personaRepo.put(p);
          break;
        case 'chat':
          final session = ChatSession.fromJson(data);
          await _chatRepo.put(session);
          break;
        case 'lorebooks':
          final lorebook = Lorebook.fromJson(data);
          await _lorebookRepo.put(lorebook);
          break;
        case 'api_presets':
          final config = ApiConfig.fromJson(data);
          await _apiRepo.put(config);
          break;
        case 'theme_presets':
          final preset = Preset.fromJson(data);
          await _presetRepo.put(preset);
          break;
      }
    } catch (_) {}
  }

  Future<void> _deleteLocalEntity(String type, String id) async {
    try {
      switch (type) {
        case 'character':
          await _characterRepo.delete(id);
          break;
        case 'persona':
          await _personaRepo.delete(id);
          break;
        case 'chat':
          await _chatRepo.delete(id);
          break;
      }
    } catch (_) {}
  }

  Future<void> _pushCharacterAvatar(String charId) async {
    try {
      final c = await _characterRepo.getById(charId);
      if (c?.avatarPath == null) return;
      final file = File(_imageStorage.absolutePath(c!.avatarPath)!);
      if (!await file.exists()) return;
      final bytes = await file.readAsBytes();
      final ext = c.avatarPath!.split('.').last;
      await _adapter.uploadBinary(
        galleryCloudPath(charId, 'avatar', ext),
        bytes,
      );
    } catch (_) {}
  }

  Future<void> _pullCharacterAvatar(String charId) async {
    try {
      final c = await _characterRepo.getById(charId);
      if (c == null) return;

      for (final ext in ['png', 'jpg', 'webp', 'gif']) {
        try {
          final imgCloudPath = galleryCloudPath(charId, 'avatar', ext);
            final bytes = await _adapter.downloadBinary(imgCloudPath);
          if (bytes.isNotEmpty) {
            final relativePath = await _imageStorage.saveBytes(
              bytes, 'avatars', charId, ext,
            );
            await _characterRepo.put(c.copyWith(avatarPath: relativePath));
            return;
          }
        } catch (_) {}
      }
    } catch (_) {}
  }
}
