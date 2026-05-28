import 'dart:convert';
import 'dart:io';

import 'package:glaze_flutter/core/constants/image_gen_patterns.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../cloud_adapter.dart';
import '../sync_models.dart';
import 'sync_conflict.dart';
import 'sync_queue.dart';
import 'sync_serialization.dart';
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
  static bool _isSingletonType(String type) =>
      type == 'lorebooks' ||
      type == 'api_presets' ||
      type == 'theme_presets' ||
      type == 'theme_state' ||
      type == 'local_storage';

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
  bool _includeApiKeys = false;

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
    bool includeApiKeys = false,
  }) async {
    _includeApiKeys = includeApiKeys;
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
    final cloudManifest = await _downloadCloudManifest();
    if (cloudManifest == null) return;
    final previousManifest = await _manifestBuilder.readLocalManifest();
    final isFirstSync = previousManifest.lastSync == 0;
    final localManifest = await _manifestBuilder.buildLocalManifest(
      cloudManifest: cloudManifest,
    );

    final entries = cloudManifest.entries.values.toList();
    final conflicts = <SyncConflict>[];
    final pullEntries = <SyncManifestEntry>[];

    for (final cloudEntry in entries) {
      final localEntry = localManifest.entries[cloudEntry.key];

      if (cloudEntry.hash == localEntry?.hash && cloudEntry.deleted == localEntry?.deleted) {
        continue;
      }

      // First sync: auto-prefer cloud only for singleton blobs (seeded defaults).
      // Characters/personas/chats keep normal conflict rules when local rows exist.
      if (isFirstSync &&
          localEntry != null &&
          _isSingletonType(cloudEntry.type)) {
        pullEntries.add(cloudEntry);
        continue;
      }

      if (SyncConflictDetector.needsConflict(localEntry, cloudEntry)) {
        final name = SyncConflictDetector.getConflictName(
          cloudEntry.type, null, null, cloudEntry.id,
        );
        conflicts.add(SyncConflict(
          key: cloudEntry.key,
          type: cloudEntry.type,
          id: cloudEntry.id,
          localEntry: localEntry!,
          cloudEntry: cloudEntry,
          name: name,
        ));
        continue;
      }

      pullEntries.add(cloudEntry);
    }

    for (final c in conflicts) {
      onConflict(c);
    }

    if (pullEntries.isNotEmpty) {
      await _applyPullEntries(pullEntries, localManifest, cloudManifest, onProgress);
    } else if (conflicts.isEmpty) {
      onProgress(const SyncProgress(current: 0, total: 0, message: 'Nothing to pull'));
      await _finalizePull(localManifest, cloudManifest);
    } else {
      await _saveCloudManifestForPendingPull(cloudManifest);
    }
  }

  Future<void> applyPendingPull({
    required void Function(SyncProgress) onProgress,
    List<String>? resolvedAsCloud,
  }) async {
    final cloudManifest =
        await _loadCloudManifestForPendingPull() ?? await _downloadCloudManifest();
    if (cloudManifest == null) return;
    final localManifest = await _manifestBuilder.buildLocalManifest(
      cloudManifest: cloudManifest,
    );

    final pullEntries = <SyncManifestEntry>[];
    final cloudKeys = cloudManifest.entries.keys.toSet();

    for (final cloudEntry in cloudManifest.entries.values) {
      final localEntry = localManifest.entries[cloudEntry.key];
      if (cloudEntry.hash == localEntry?.hash && cloudEntry.deleted == localEntry?.deleted) {
        continue;
      }
      if (SyncConflictDetector.needsConflict(localEntry, cloudEntry)) {
        if (resolvedAsCloud != null && resolvedAsCloud.contains(cloudEntry.key)) {
          pullEntries.add(cloudEntry);
        }
        continue;
      }
      pullEntries.add(cloudEntry);
    }

    for (final localEntry in localManifest.entries.values) {
      if (localEntry.deleted) continue;
      if (!cloudKeys.contains(localEntry.key)) {
        await _deleteLocalEntity(localEntry.type, localEntry.id);
      }
    }

    if (pullEntries.isNotEmpty) {
      await _applyPullEntries(pullEntries, localManifest, cloudManifest, onProgress);
    } else {
      onProgress(const SyncProgress(current: 0, total: 0, message: 'Nothing to pull'));
      await _finalizePull(localManifest, cloudManifest);
    }

    await _clearPendingPullManifest();
  }

  Future<void> _applyPullEntries(
    List<SyncManifestEntry> pullEntries,
    SyncManifest localManifest,
    SyncManifest cloudManifest,
    void Function(SyncProgress) onProgress,
  ) async {
    final tasks = <Future<void> Function()>[];
    var processed = 0;

    for (final entry in pullEntries) {
      tasks.add(() async {
        processed++;
        onProgress(SyncProgress(
          current: processed,
          total: tasks.length,
          message: 'Pulling ${entry.type}:${entry.id}',
        ));
        await _pullEntry(entry);
      });
    }

    onProgress(SyncProgress(
      current: 0,
      total: tasks.length,
      message: 'Pulling ${tasks.length} items...',
    ));

    List<Object>? taskErrors;
    if (tasks.isNotEmpty) {
      final result = await _queue.enqueueAll(tasks, concurrency: 3, delayMs: 300);
      taskErrors = result.errors;
    }

    final cloudKeys = cloudManifest.entries.keys.toSet();
    for (final localEntry in localManifest.entries.values) {
      if (localEntry.deleted) continue;
      if (!cloudKeys.contains(localEntry.key)) {
        await _deleteLocalEntity(localEntry.type, localEntry.id);
      }
    }

    await _finalizePull(localManifest, cloudManifest);

    if (taskErrors != null && taskErrors.isNotEmpty) {
      throw SyncQueueAggregateError(taskErrors);
    }
  }

  Future<void> _finalizePull(SyncManifest localManifest, SyncManifest cloudManifest) async {
    final rebuilt = await _manifestBuilder.buildLocalManifest(
      cloudManifest: cloudManifest,
    );
    await _manifestBuilder.writeLocalManifest(
      rebuilt.copyWith(
        createdAt: cloudManifest.createdAt != 0
            ? cloudManifest.createdAt
            : rebuilt.createdAt,
        lastSync: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    await _manifestBuilder.clearDeleted();
  }

  Future<SyncManifest?> _downloadCloudManifest() async {
    try {
      final raw = await _adapter.download(cloudPath('manifest', 'manifest'));
      return SyncManifest.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static const _pendingManifestKey = 'gz_sync_pending_pull_manifest';

  Future<void> _saveCloudManifestForPendingPull(SyncManifest manifest) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingManifestKey, jsonEncode(manifest.toJson()));
  }

  Future<SyncManifest?> _loadCloudManifestForPendingPull() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingManifestKey);
    if (raw == null) return null;
    try {
      return SyncManifest.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> _clearPendingPullManifest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingManifestKey);
  }

  Future<void> resolveConflict(SyncConflict conflict, String choice) async {
    if (choice == 'cloud') {
      await _pullEntry(conflict.cloudEntry);
    }

    final rebuiltManifest = await _manifestBuilder.buildLocalManifest();
    final updatedEntries = Map<String, SyncManifestEntry>.from(rebuiltManifest.entries);
    final rebuiltEntry = updatedEntries[conflict.key];

    if (choice == 'cloud') {
      // Align manifest with cloud so the same conflict does not reappear.
      updatedEntries[conflict.key] = conflict.cloudEntry;
    } else if (choice == 'local' && rebuiltEntry != null) {
      updatedEntries[conflict.key] = rebuiltEntry.copyWith(
        updatedAt: conflict.localEntry.updatedAt,
      );
    }

    await _manifestBuilder.writeLocalManifest(
      rebuiltManifest.copyWith(entries: updatedEntries),
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
        if (files.isEmpty) break;
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
    if (entry.type == 'persona') {
      await _pushPersonaAvatar(entry.id);
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
    if (entry.type == 'persona') {
      await _pullPersonaAvatar(entry.id);
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
          return _stripImagesFromSession(s.toJson());
        case 'lorebooks':
          final all = await _lorebookRepo.getAll();
          return {'__singleton': true, 'items': all.map((l) => l.toJson()).toList()};
        case 'api_presets':
          final all = await _apiRepo.getAll();
          final items = all.map((a) {
            if (!_includeApiKeys) {
              return a.copyWith(apiKey: '', embeddingApiKey: '').toJson();
            }
            return a.toJson();
          }).toList();
          return {'__singleton': true, 'items': items};
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
          await _applySingleton<Lorebook>(
            data,
            Lorebook.fromJson,
            _lorebookRepo,
            idOf: (lb) => lb.id,
          );
          break;
        case 'api_presets':
          await _applySingleton<ApiConfig>(
            data,
            ApiConfig.fromJson,
            _apiRepo,
            idOf: (a) => a.id,
          );
          break;
        case 'theme_presets':
          await _applySingleton<Preset>(
            data,
            Preset.fromJson,
            _presetRepo,
            idOf: (p) => p.id,
          );
          break;
      }
    } catch (_) {}
  }

  Future<void> _applySingleton<T>(
    Map<String, dynamic> data,
    T Function(Map<String, dynamic>) fromJson,
    dynamic repo, {
    String Function(T)? idOf,
  }) async {
    final List<Map<String, dynamic>> items;
    if (data['__singleton'] == true) {
      items = (data['items'] as List).cast<Map<String, dynamic>>();
    } else if (data.containsKey('items')) {
      items = (data['items'] as List).cast<Map<String, dynamic>>();
    } else {
      items = [data];
    }

    final getAll = repo.getAll as Future<List<T>> Function();
    final put = repo.put as Future<void> Function(T);
    final delete = repo.delete as Future<void> Function(String);

    final cloudIds = <String>{};
    final parsed = <T>[];
    for (final item in items) {
      final entity = fromJson(item);
      parsed.add(entity);
      if (idOf != null) {
        cloudIds.add(idOf(entity));
      }
    }

    if (idOf != null) {
      final existing = await getAll();
      for (final entity in existing) {
        final id = idOf(entity);
        if (!cloudIds.contains(id)) {
          await delete(id);
        }
      }
    }

    for (final entity in parsed) {
      await put(entity);
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
        case 'api_presets':
          final apis = await _apiRepo.getAll();
          for (final a in apis) {
            await _apiRepo.delete(a.id);
          }
          break;
        case 'theme_presets':
          final presets = await _presetRepo.getAll();
          for (final p in presets) {
            await _presetRepo.delete(p.id);
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

  Future<void> _pushPersonaAvatar(String personaId) async {
    try {
      final p = await _personaRepo.getById(personaId);
      if (p?.avatarPath == null) return;
      final file = File(_imageStorage.absolutePath(p!.avatarPath)!);
      if (!await file.exists()) return;
      final bytes = await file.readAsBytes();
      final ext = p.avatarPath!.split('.').last;
      await _adapter.uploadBinary(
        personaAvatarCloudPath(personaId, ext),
        bytes,
      );
    } catch (_) {}
  }

  Future<void> _pullPersonaAvatar(String personaId) async {
    try {
      final p = await _personaRepo.getById(personaId);
      if (p == null) return;

      for (final ext in ['png', 'jpg', 'webp', 'gif']) {
        try {
          final imgCloudPath = personaAvatarCloudPath(personaId, ext);
          final bytes = await _adapter.downloadBinary(imgCloudPath);
          if (bytes.isNotEmpty) {
            final relativePath = await _imageStorage.saveBytes(
              bytes, 'avatars', personaId, ext,
            );
            await _personaRepo.put(p.copyWith(avatarPath: relativePath));
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

final _imgResultRegex = ImgGenPatterns.imgResultStripRegex;
final _imgErrorRegex = ImgGenPatterns.imgErrorStripRegex;
final _imgGenRegex = ImgGenPatterns.imgGenStripRegex;
final _base64DataUrlRegex = ImgGenPatterns.base64DataUrlRegex;
final _imgTagRegex = ImgGenPatterns.imgTagDataSrcRegex;

Map<String, dynamic> _stripImagesFromSession(Map<String, dynamic> json) {
  final messages = json['messages'];
  if (messages is! List) return json;
  final stripped = messages.map((m) {
    if (m is! Map<String, dynamic>) return m;
    var modified = false;
    final content = m['content'];
    String? cleanedContent;
    if (content is String && content.length >= 10) {
      cleanedContent = _stripImageContent(content);
      if (!identical(cleanedContent, content)) modified = true;
    }
    List<dynamic>? cleanedSwipes;
    final swipes = m['swipes'];
    if (swipes is List && swipes.isNotEmpty) {
      cleanedSwipes = swipes.map((s) {
        if (s is String && s.length >= 10) {
          final c = _stripImageContent(s);
          if (!identical(c, s)) modified = true;
          return c;
        }
        return s;
      }).toList();
    }
    if (!modified) return m;
    final result = <String, dynamic>{...m};
    if (cleanedContent != null) result['content'] = cleanedContent;
    if (cleanedSwipes != null) result['swipes'] = cleanedSwipes;
    return result;
  }).toList();
  return {...json, 'messages': stripped};
}

String _stripImageContent(String text) {
  var result = text;
  result = result.replaceAll(_imgResultRegex, '');
  result = result.replaceAll(_imgErrorRegex, '');
  result = result.replaceAll(_imgGenRegex, '');
  result = result.replaceAll(_imgTagRegex, '');
  result = result.replaceAll(_base64DataUrlRegex, '');
  return result;
}
