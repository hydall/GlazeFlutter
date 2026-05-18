import 'dart:convert';
import 'dart:io';

import '../cloud_adapter.dart';
import '../sync_models.dart';
import 'sync_conflict.dart';
import 'sync_manifest.dart';
import 'sync_queue.dart';
import 'sync_serialization.dart';
import '../../../core/services/image_storage_service.dart';
import '../../../core/models/character.dart';
import '../../../core/models/gallery_entry.dart';
import '../../../core/models/persona.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/lorebook.dart';
import '../../../core/models/api_config.dart';
import '../../../core/models/preset.dart';
import '../sync_repo_interfaces.dart';

class SyncProgress {
  final int current;
  final int total;
  final String? message;

  const SyncProgress({this.current = 0, this.total = 0, this.message});
}

class SyncEngine {
  final CloudAdapter _adapter;
  final SyncManifestProvider _manifestBuilder;
  final SyncCharacterStore _characterRepo;
  final SyncChatStore _chatRepo;
  final SyncPersonaStore _personaRepo;
  final SyncPresetStore _presetRepo;
  final SyncApiConfigStore _apiRepo;
  final SyncLorebookStore _lorebookRepo;
  final SyncEmbeddingStore _embeddingRepo;
  final SyncImageStore _imageStorage;
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
    this._embeddingRepo,
    this._imageStorage,
  );

  Future<void> pushEntities({
    required void Function(SyncProgress) onProgress,
  }) async {
    await _adapter.ensureFolder(cloudBase);
    await _adapter.ensureFolder('$cloudBase/characters');
    await _adapter.ensureFolder('$cloudBase/personas');
    await _adapter.ensureFolder('$cloudBase/chats');

    final localManifest = await _manifestBuilder.buildLocalManifest();
    SyncManifest? cloudManifest;
    try {
      final raw = await _adapter.download(cloudPath('manifest', 'manifest'));
      cloudManifest = SyncManifest.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {}

    final entries = localManifest.entries.values.toList();

    final galleryDirs = <String>{};
    for (final entry in entries) {
      if (entry.type == 'character' && !entry.deleted) {
        galleryDirs.add('$cloudBase/gallery/${entry.id}');
      }
    }
    for (final dir in galleryDirs) {
      await _adapter.ensureFolder(dir);
    }

    final tasks = <Future<void> Function()>[];
    var processed = 0;

    for (final entry in entries) {
      final cloudEntry = cloudManifest?.entries[entry.key];

      if (entry.deleted) {
        if (cloudEntry != null && !cloudEntry.deleted) {
          tasks.add(() async {
            processed++;
            onProgress(SyncProgress(
              current: processed,
              total: tasks.length,
              message: 'Deleting ${entry.type}:${entry.id}',
            ));
            await SyncSerialization.deleteCloudFileIfExists(_adapter, entry);
          });
        }
        continue;
      }

      if (cloudEntry != null && cloudEntry.hash == entry.hash && !cloudEntry.deleted) {
        continue;
      }

      tasks.add(() async {
        processed++;
        onProgress(SyncProgress(
          current: processed,
          total: tasks.length,
          message: 'Pushing ${entry.type}:${entry.id}',
        ));
        await _pushEntry(entry);
      });
    }

    onProgress(SyncProgress(
      current: 0,
      total: tasks.length,
      message: tasks.isEmpty ? 'Nothing to push' : 'Pushing ${tasks.length} items...',
    ));

    List<Object>? taskErrors;
    if (tasks.isNotEmpty) {
      final result = await _queue.enqueueAll(tasks, concurrency: 3, delayMs: 300);
      taskErrors = result.errors;
    }

    final cleanedEntries = Map<String, SyncManifestEntry>.from(localManifest.entries)
      ..removeWhere((_, e) => e.deleted);

    final updatedManifest = localManifest.copyWith(
      lastSync: DateTime.now().millisecondsSinceEpoch,
      entries: cleanedEntries,
    );
    await _adapter.upload(
      cloudPath('manifest', 'manifest'),
      jsonEncode(updatedManifest.toJson()),
    );
    await _manifestBuilder.writeLocalManifest(updatedManifest);
    await _manifestBuilder.clearDeleted();

    if (taskErrors != null && taskErrors.isNotEmpty) {
      throw SyncQueueAggregateError(taskErrors);
    }
  }

  Future<void> pullEntities({
    required void Function(SyncProgress) onProgress,
    required void Function(SyncConflict) onConflict,
  }) async {
    final raw = await _adapter.download(cloudPath('manifest', 'manifest'));
    final cloudManifest = SyncManifest.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    final localManifest = await _manifestBuilder.buildLocalManifest();

    final entries = cloudManifest.entries.values.toList();
    final tasks = <Future<void> Function()>[];
    var processed = 0;

    for (final cloudEntry in entries) {
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

      tasks.add(() async {
        processed++;
        onProgress(SyncProgress(
          current: processed,
          total: tasks.length,
          message: 'Pulling ${cloudEntry.type}:${cloudEntry.id}',
        ));
        await _pullEntry(cloudEntry);
      });
    }

    onProgress(SyncProgress(
      current: 0,
      total: tasks.length,
      message: tasks.isEmpty ? 'Nothing to pull' : 'Pulling ${tasks.length} items...',
    ));

    List<Object>? taskErrors;
    if (tasks.isNotEmpty) {
      final result = await _queue.enqueueAll(tasks, concurrency: 3, delayMs: 300);
      taskErrors = result.errors;
    }

    final cloudKeys = cloudManifest.entries.keys.toSet();
    final previousLocal = await _manifestBuilder.readLocalManifest();
    for (final localEntry in localManifest.entries.values) {
      if (localEntry.deleted) continue;
      if (!cloudKeys.contains(localEntry.key) &&
          previousLocal.entries.containsKey(localEntry.key) &&
          !previousLocal.entries[localEntry.key]!.deleted) {
        await _deleteLocalEntity(localEntry.type, localEntry.id);
      }
    }

    await _manifestBuilder.writeLocalManifest(cloudManifest.copyWith(
      lastSync: DateTime.now().millisecondsSinceEpoch,
    ));
    await _manifestBuilder.clearDeleted();

    if (taskErrors != null && taskErrors.isNotEmpty) {
      throw SyncQueueAggregateError(taskErrors);
    }
  }

  Future<void> resolveConflict(SyncConflict conflict, String choice) async {
    if (choice == 'cloud') {
      await _pullEntry(conflict.cloudEntry);
    }

    final localManifest = await _manifestBuilder.readLocalManifest();
    final updatedEntries = Map<String, SyncManifestEntry>.from(localManifest.entries);
    updatedEntries[conflict.key] = conflict.cloudEntry;
    await _manifestBuilder.writeLocalManifest(
      localManifest.copyWith(entries: updatedEntries),
    );
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
    onProgress(const SyncProgress(message: 'Deleting cloud data...'));
    try {
      await _adapter.deleteFolder(cloudBase);
    } catch (e) {
      final msg = e.toString();
      if (!msg.contains('not_found') && !msg.contains('path_not_found')) {
        rethrow;
      }
    }

    onProgress(const SyncProgress(message: 'Waiting for cloud to finalize...'));
    for (var i = 0; i < 10; i++) {
      await Future.delayed(const Duration(seconds: 2));
      try {
        final files = await _adapter.listFolder(cloudBase);
        if (files == null || files.isEmpty) break;
      } catch (_) {
        break;
      }
    }

    onProgress(const SyncProgress(message: 'Recreating cloud folder...'));
    await _adapter.invalidateFolderCache();
    try {
      await _adapter.ensureFolder(cloudBase);
    } catch (_) {}
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
      await _pushCharacterGallery(entry.id);
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
      await _pullCharacterGallery(entry.id);
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
          final all = await _lorebookRepo.getAll();
          return {'__singleton': true, 'items': all.map((l) => l.toJson()).toList()};
        case 'api_presets':
          final all = await _apiRepo.getAll();
          return {'__singleton': true, 'items': all.map((a) => a.toJson()).toList()};
        case 'theme_presets':
          final all = await _presetRepo.getAll();
          return {'__singleton': true, 'items': all.map((p) => p.toJson()).toList()};
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
          await _characterRepo.put(Character.fromJson(data));
          break;
        case 'persona':
          await _personaRepo.put(Persona.fromJson(data));
          break;
        case 'chat':
          await _chatRepo.put(ChatSession.fromJson(data));
          break;
        case 'lorebooks':
          await _applySingleton<Lorebook>(data, Lorebook.fromJson, _lorebookRepo);
          break;
        case 'api_presets':
          await _applySingleton<ApiConfig>(data, ApiConfig.fromJson, _apiRepo);
          break;
        case 'theme_presets':
          await _applySingleton<Preset>(data, Preset.fromJson, _presetRepo);
          break;
      }
    } catch (_) {}
  }

  Future<void> _applySingleton<T>(
    Map<String, dynamic> data,
    T Function(Map<String, dynamic>) fromJson,
    dynamic repo,
  ) async {
    final List<Map<String, dynamic>> items;
    if (data['__singleton'] == true) {
      items = (data['items'] as List).cast<Map<String, dynamic>>();
    } else if (data.containsKey('items')) {
      items = (data['items'] as List).cast<Map<String, dynamic>>();
    } else {
      items = [data];
    }

    final put = repo.put as Future<void> Function(T);
    for (final item in items) {
      await put(fromJson(item));
    }
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
        case 'lorebooks':
          final all = await _lorebookRepo.getAll();
          for (final lb in all) {
            await _lorebookRepo.delete(lb.id);
            await _embeddingRepo.deleteBySourceId(lb.id);
          }
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

  Future<void> _pushCharacterGallery(String charId) async {
    try {
      final c = await _characterRepo.getById(charId);
      if (c == null) return;
      await _adapter.ensureFolder('$cloudBase/gallery/$charId');
      for (final entry in c.gallery) {
        final absPath = _imageStorage.absolutePath(entry.imagePath);
        if (absPath == null) continue;
        final file = File(absPath);
        if (!await file.exists()) continue;
        final bytes = await file.readAsBytes();
        final ext = entry.imagePath.split('.').last;
        await _adapter.uploadBinary(
          galleryCloudPath(charId, entry.id, ext),
          bytes,
        );
      }
    } catch (_) {}
  }

  Future<void> _pullCharacterGallery(String charId) async {
    try {
      final c = await _characterRepo.getById(charId);
      if (c == null) return;

      final updatedGallery = <GalleryEntry>[];
      for (final entry in c.gallery) {
        var pulled = false;
        for (final ext in ['png', 'jpg', 'webp', 'gif']) {
          try {
            final imgCloudPath = galleryCloudPath(charId, entry.id, ext);
            final bytes = await _adapter.downloadBinary(imgCloudPath);
            if (bytes.isNotEmpty) {
              final destPath = await _imageStorage.saveBytes(
                bytes, 'gallery/$charId', entry.id, ext,
              );
              updatedGallery.add(entry.copyWith(imagePath: destPath));
              pulled = true;
              break;
            }
          } catch (_) {}
        }
        if (!pulled) {
          final absPath = _imageStorage.absolutePath(entry.imagePath);
          if (absPath != null && await File(absPath).exists()) {
            updatedGallery.add(entry);
          }
        }
      }

      if (updatedGallery.length != c.gallery.length ||
          !_galleriesEqual(updatedGallery, c.gallery)) {
        await _characterRepo.put(c.copyWith(gallery: updatedGallery));
      }
    } catch (_) {}
  }

  bool _galleriesEqual(List<GalleryEntry> a, List<GalleryEntry> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].imagePath != b[i].imagePath) return false;
    }
    return true;
  }
}
