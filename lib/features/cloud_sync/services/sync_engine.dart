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
import '../../../core/models/memory_book.dart';
import '../../../core/models/persona.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/lorebook.dart';
import '../../../core/models/api_config.dart';
import '../../../core/models/preset.dart';
import '../../../shared/theme/theme_preset.dart';
import '../sync_repo_interfaces.dart';
import '../../../core/state/lorebook_provider.dart' show saveLorebookActivations;

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
  final SyncMemoryBookStore _memoryBookRepo;
  final SyncLorebookStore _lorebookRepo;
  final SyncEmbeddingStore _embeddingRepo;
  final SyncImageStore _imageStorage;
  final SyncThemePresetStore _themePresetRepo;
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
    this._memoryBookRepo,
    this._lorebookRepo,
    this._embeddingRepo,
    this._imageStorage,
    this._themePresetRepo,
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
    await _adapter.ensureFolder('$cloudBase/memory_books');

    final localManifest = await _manifestBuilder.buildLocalManifest();
    SyncManifest? cloudManifest;
    var cloudManifestDownloadFailed = false;
    try {
      final raw = await _adapter.download(cloudPath('manifest', 'manifest'));
      cloudManifest = SyncManifest.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      cloudManifestDownloadFailed = true;
    }

    final cloudFilePaths = await _loadCloudFilePaths();

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
    final hashSkippedKeys = <String>[];

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

      final cloudFileExists = cloudSyncPathExists(cloudFilePaths, entry.path);

      if (cloudEntry != null && !cloudEntry.deleted) {
        if (cloudEntry.hash == entry.hash && cloudFileExists) {
          hashSkippedKeys.add(entry.key);
          continue;
        }
        if (cloudEntry.hash == entry.hash && !cloudFileExists) {
        }
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
      version: SyncManifest.currentVersion,
      lastSync: DateTime.now().millisecondsSinceEpoch,
      entries: cleanedEntries,
      apiKeysIncluded: _includeApiKeys,
    );
    final manifestJson = jsonEncode(updatedManifest.toJson());
    await _adapter.upload(
      cloudPath('manifest', 'manifest'),
      manifestJson,
    );
    await _manifestBuilder.writeLocalManifest(updatedManifest);
    await _manifestBuilder.clearDeleted();

    if (taskErrors != null && taskErrors.isNotEmpty) {
      throw SyncQueueAggregateError(taskErrors);
    }
  }

  Future<Set<String>> _loadCloudFilePaths() async {
    try {
      return await _collectCloudFilePaths(cloudBase);
    } catch (_) {
      return {};
    }
  }

  Future<Set<String>> _collectCloudFilePaths(String path) async {
    final files = await _adapter.listFolder(path);
    final paths = files
        .where((f) => !f.isFolder)
        .map((f) => normalizeCloudSyncPath(f.path))
        .toSet();

    final hasNestedFiles = paths.any((p) => p.split('/').where((s) => s.isNotEmpty).length > 1);
    if (hasNestedFiles) return paths;

    for (final folder in files.where((f) => f.isFolder)) {
      paths.addAll(await _collectCloudFilePaths(folder.path));
    }
    return paths;
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

      // Before first successful sync, local manifest timestamps are unreliable
      // (no previous entries → updatedAt defaults to now or entity timestamp).
      // Auto-prefer cloud for everything on first sync.
      if (isFirstSync && localEntry != null) {
        pullEntries.add(cloudEntry);
        continue;
      }

      if (await _entriesSemanticallyEqual(cloudEntry, localEntry, cloudManifest)) {
        continue;
      }

      if (SyncConflictDetector.needsConflict(localEntry, cloudEntry)) {
        final localData = await _readLocalEntity(cloudEntry.type, cloudEntry.id);
        String? characterName;
        if (cloudEntry.type == 'chat') {
          final charId = localData?['characterId'] as String?;
          if (charId != null) {
            final character = await _characterRepo.getById(charId);
            characterName = character?.name;
          }
        }
        final name = SyncConflictDetector.getConflictName(
          cloudEntry.type, localData, null, cloudEntry.id,
          characterName: characterName,
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
      if (await _entriesSemanticallyEqual(cloudEntry, localEntry, cloudManifest)) {
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
      await Future<void>.delayed(const Duration(seconds: 2));
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
    if (entry.type == 'chat') {
      final charId = cloudData['characterId'] as String?;
      if (charId != null) {
        await _sanitizeInvalidAvatarPath(charId);
        await _pullCharacterAvatar(charId);
      }
    }
  }

  Future<bool> _entriesSemanticallyEqual(
    SyncManifestEntry cloudEntry,
    SyncManifestEntry? localEntry,
    SyncManifest cloudManifest,
  ) async {
    if (localEntry == null) return false;
    if (cloudEntry.hash == localEntry.hash) return true;

    switch (cloudEntry.type) {
      case 'memory_book':
        final localMb = await _memoryBookRepo.getBySessionId(cloudEntry.id);
        if (localMb == null) return false;
        final cloudData =
            await SyncSerialization.readCloudEntity(_adapter, cloudEntry);
        if (cloudData == null) return false;
        final localHash =
            SyncSerialization.computeMemoryBookHash(localMb.toJson());
        final cloudHash =
            SyncSerialization.computeMemoryBookHash(cloudData);
        final equal = localHash == cloudHash;
        return equal;
      case 'api_presets':
        if (cloudManifest.apiKeysIncluded) return false;
        final localAll = await _apiRepo.getAll();
        final cloudData =
            await SyncSerialization.readCloudEntity(_adapter, cloudEntry);
        if (cloudData == null) return false;
        final List<Map<String, dynamic>> cloudItems;
        if (cloudData['__singleton'] == true) {
          cloudItems = (cloudData['items'] as List).cast<Map<String, dynamic>>();
        } else if (cloudData.containsKey('items')) {
          cloudItems = (cloudData['items'] as List).cast<Map<String, dynamic>>();
        } else {
          cloudItems = [cloudData];
        }
        final localHash = SyncSerialization.computeApiPresetsHash(
          localAll.map((a) => a.toJson()),
        );
        final cloudHash = SyncSerialization.computeApiPresetsHash(cloudItems);
        return localHash == cloudHash;
      default:
        return false;
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
        case 'memory_book':
          final mb = await _memoryBookRepo.getBySessionId(id);
          if (mb == null) return null;
          return mb.toJson();
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
        case 'ui_themes':
          final all = await _themePresetRepo.getAll();
          return {'__singleton': true, 'items': all.map((t) => t.toJson()).toList()};
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
          await _applyCloudCharacter(id, data);
          break;
        case 'persona':
          await _applyCloudPersona(id, data);
          break;
        case 'chat':
          await _chatRepo.put(ChatSession.fromJson(data));
          break;
        case 'memory_book':
          await _memoryBookRepo.put(MemoryBook.fromJson(data));
          break;
        case 'lorebooks':
          await _applyLorebooksWithEmbeddingCleanup(data);
          break;
        case 'api_presets':
          await _applyApiConfigs(data);
          break;
        case 'theme_presets':
          await _applySingleton<Preset>(
            data,
            Preset.fromJson,
            _presetRepo,
            idOf: (p) => p.id,
          );
          break;
        case 'ui_themes':
          await _applyUiThemes(data);
          break;
      }
    } catch (_) {}
  }

  /// avatarPath and gallery hold device-local paths; never apply cloud values
  /// directly — binary assets are synced in [_pullCharacterAvatar] /
  /// [_pullCharacterGallery].
  Future<void> _applyCloudCharacter(String id, Map<String, dynamic> data) async {
    final local = await _characterRepo.getById(id);
    final json = Map<String, dynamic>.from(data);
    final cloudAvatarPath = json.remove('avatarPath') as String?;
    json.remove('gallery');
    var character = Character.fromJson(json);
    if (local != null) {
      character = character.copyWith(
        avatarPath: local.avatarPath,
        gallery: local.gallery,
      );
    }
    await _characterRepo.put(character);
  }

  Future<void> _applyCloudPersona(String id, Map<String, dynamic> data) async {
    final local = await _personaRepo.getById(id);
    final json = Map<String, dynamic>.from(data);
    final cloudAvatarPath = json.remove('avatarPath') as String?;
    var persona = Persona.fromJson(json);
    if (local != null) {
      persona = persona.copyWith(avatarPath: local.avatarPath);
    }
    await _personaRepo.put(persona);
  }

  bool _localAvatarFileExists(String? avatarPath) {
    if (avatarPath == null || avatarPath.isEmpty) return false;
    final abs = _imageStorage.absolutePath(avatarPath);
    if (abs == null) return false;
    return File(abs).existsSync();
  }

  Future<void> _sanitizeInvalidAvatarPath(String charId) async {
    final c = await _characterRepo.getById(charId);
    if (c == null || c.avatarPath == null || c.avatarPath!.isEmpty) return;
    if (_localAvatarFileExists(c.avatarPath)) return;
    await _characterRepo.put(c.copyWith(avatarPath: null));
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

  /// Applies the lorebook singleton from cloud data, cleaning up embeddings for
  /// removed lorebooks and rebuilding the lorebookActivations SharedPreferences
  /// from the DB truth after the apply completes.
  Future<void> _applyLorebooksWithEmbeddingCleanup(
      Map<String, dynamic> data) async {
    final List<Map<String, dynamic>> items;
    if (data['__singleton'] == true) {
      items = (data['items'] as List).cast<Map<String, dynamic>>();
    } else if (data.containsKey('items')) {
      items = (data['items'] as List).cast<Map<String, dynamic>>();
    } else {
      items = [data];
    }

    final parsed = items.map(Lorebook.fromJson).toList();
    final cloudIds = {for (final lb in parsed) lb.id};

    // Delete lorebooks no longer in the cloud, including their embedding vectors.
    final existing = await _lorebookRepo.getAll();
    for (final lb in existing) {
      if (!cloudIds.contains(lb.id)) {
        await _lorebookRepo.delete(lb.id);
        await _embeddingRepo.deleteBySourceId(lb.id);
      }
    }

    // Upsert all cloud lorebooks.
    for (final lb in parsed) {
      await _lorebookRepo.put(lb);
    }

    // Rebuild lorebookActivations prefs from the DB truth so that the
    // connections UI and the scanner use consistent data across devices.
    await _rebuildLorebookActivationsPrefs();
  }

  /// Reads all lorebooks from the DB and rewrites the `lorebookActivations`
  /// SharedPreferences key from their activationScope / activationTargetId
  /// fields. Called after a lorebook pull to eliminate stale prefs that would
  /// otherwise show phantom character/chat connections in the UI.
  Future<void> _rebuildLorebookActivationsPrefs() async {
    final all = await _lorebookRepo.getAll();
    final charMap = <String, List<String>>{};
    final chatMap = <String, List<String>>{};
    for (final lb in all) {
      final targetId = lb.activationTargetId;
      if (targetId == null) continue;
      if (lb.activationScope == 'character') {
        charMap.putIfAbsent(targetId, () => []).add(lb.id);
      } else if (lb.activationScope == 'chat') {
        chatMap.putIfAbsent(targetId, () => []).add(lb.id);
      }
    }
    final activations = LorebookActivations(character: charMap, chat: chatMap);
    await saveLorebookActivations(activations);
  }

  /// Applies cloud api_presets while preserving local API keys and embedding
  /// keys. Cloud payloads strip keys (empty string) when includeApiKeys=false;
  /// blindly writing them would wipe the user's credentials on every pull.
  Future<void> _applyApiConfigs(Map<String, dynamic> data) async {
    final List<Map<String, dynamic>> items;
    if (data['__singleton'] == true) {
      items = (data['items'] as List).cast<Map<String, dynamic>>();
    } else if (data.containsKey('items')) {
      items = (data['items'] as List).cast<Map<String, dynamic>>();
    } else {
      items = [data];
    }

    final existing = await _apiRepo.getAll();
    final localById = {for (final a in existing) a.id: a};

    final cloudIds = <String>{};
    for (final item in items) {
      final cloudConfig = ApiConfig.fromJson(item);
      cloudIds.add(cloudConfig.id);

      final local = localById[cloudConfig.id];
      final merged = cloudConfig.copyWith(
        // Preserve local keys: use cloud key only when it is non-empty
        // (i.e. when includeApiKeys=true was used during push).
        apiKey: cloudConfig.apiKey.isNotEmpty
            ? cloudConfig.apiKey
            : (local?.apiKey ?? ''),
        embeddingApiKey: cloudConfig.embeddingApiKey.isNotEmpty
            ? cloudConfig.embeddingApiKey
            : (local?.embeddingApiKey ?? ''),
      );
      await _apiRepo.put(merged);
    }

    // Delete local configs that no longer exist in cloud.
    for (final local in existing) {
      if (!cloudIds.contains(local.id)) {
        await _apiRepo.delete(local.id);
      }
    }
  }

  Future<void> _applyUiThemes(Map<String, dynamic> data) async {
    final List<Map<String, dynamic>> items;
    if (data['__singleton'] == true) {
      items = (data['items'] as List).cast<Map<String, dynamic>>();
    } else if (data.containsKey('items')) {
      items = (data['items'] as List).cast<Map<String, dynamic>>();
    } else {
      items = [data];
    }
    final presets = items.map((j) => ThemePreset.fromJson(j)).toList();
    await _themePresetRepo.putAll(presets);
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
        case 'memory_book':
          await _memoryBookRepo.deleteBySessionId(id);
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
        case 'ui_themes':
          await _themePresetRepo.putAll([]);
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

      await _sanitizeInvalidAvatarPath(charId);
      final current = await _characterRepo.getById(charId);
      if (current == null) return;

      for (final ext in ['png', 'jpg', 'webp', 'gif']) {
        try {
          final imgCloudPath = galleryCloudPath(charId, 'avatar', ext);
          final bytes = await _adapter.downloadBinary(imgCloudPath);
          if (bytes.isNotEmpty) {
            final localPath = await _imageStorage.saveBytes(
              bytes, 'avatars', charId, ext,
            );
            await _characterRepo.put(current.copyWith(avatarPath: localPath));
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
