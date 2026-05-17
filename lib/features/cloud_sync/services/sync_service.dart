import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/db/repositories/character_repo.dart';
import '../../../core/db/repositories/chat_repo.dart';
import '../../../core/db/repositories/persona_repo.dart';
import '../../../core/db/repositories/preset_repo.dart';
import '../../../core/db/repositories/api_config_repo.dart';
import '../../../core/db/repositories/lorebook_repo.dart';
import '../../../core/db/repositories/embedding_repo.dart';
import '../../../core/services/image_storage_service.dart';
import 'dropbox/dropbox_adapter.dart';
import 'dropbox/dropbox_auth.dart';
import 'gdrive/gdrive_adapter.dart';
import 'gdrive/gdrive_auth.dart';
import 'sync_conflict.dart';
import 'sync_engine.dart';
import 'sync_manifest.dart';
import '../cloud_adapter.dart';
import '../sync_models.dart';

class SyncService {
  final CharacterRepo _characterRepo;
  final ChatRepo _chatRepo;
  final PersonaRepo _personaRepo;
  final PresetRepo _presetRepo;
  final ApiConfigRepo _apiRepo;
  final LorebookRepo _lorebookRepo;
  final EmbeddingRepo _embeddingRepo;
  final ImageStorageService _imageStorage;

  SyncProvider _provider = SyncProvider.dropbox;
  SyncStatus _status = SyncStatus.idle;
  String? _lastError;
  int? _lastSyncTime;
  List<SyncConflict> _conflicts = [];
  Map<String, dynamic>? _accountInfo;
  bool _autoSyncEnabled = false;
  int _autoSyncMessageCount = 5;
  int _messageCounter = 0;

  final DropboxAuth _dropboxAuth = DropboxAuth();
  final GDriveAuth _gdriveAuth = GDriveAuth();

  SyncProvider get provider => _provider;
  SyncStatus get status => _status;
  String? get lastError => _lastError;
  int? get lastSyncTime => _lastSyncTime;
  List<SyncConflict> get conflicts => _conflicts;
  Map<String, dynamic>? get accountInfo => _accountInfo;
  bool get autoSyncEnabled => _autoSyncEnabled;
  int get autoSyncMessageCount => _autoSyncMessageCount;
  bool get isSyncing => _status == SyncStatus.syncing;
  bool get hasConflicts => _conflicts.isNotEmpty;

  SyncService({
    required CharacterRepo characterRepo,
    required ChatRepo chatRepo,
    required PersonaRepo personaRepo,
    required PresetRepo presetRepo,
    required ApiConfigRepo apiRepo,
    required LorebookRepo lorebookRepo,
    required EmbeddingRepo embeddingRepo,
    required ImageStorageService imageStorage,
  })  : _characterRepo = characterRepo,
        _chatRepo = chatRepo,
        _personaRepo = personaRepo,
        _presetRepo = presetRepo,
        _apiRepo = apiRepo,
        _lorebookRepo = lorebookRepo,
        _embeddingRepo = embeddingRepo,
        _imageStorage = imageStorage;

  CloudAdapter get _adapter {
    switch (_provider) {
      case SyncProvider.dropbox:
        return DropboxAdapter(_dropboxAuth);
      case SyncProvider.gdrive:
        return GDriveAdapter(_gdriveAuth);
    }
  }

  SyncManifestBuilder get _manifestBuilder => SyncManifestBuilder(
        characterRepo: _characterRepo,
        chatRepo: _chatRepo,
        personaRepo: _personaRepo,
        presetRepo: _presetRepo,
        apiRepo: _apiRepo,
        lorebookRepo: _lorebookRepo,
      );

  SyncEngine get _engine => SyncEngine(
        _adapter,
        _manifestBuilder,
        _characterRepo,
        _chatRepo,
        _personaRepo,
        _presetRepo,
        _apiRepo,
        _lorebookRepo,
        _embeddingRepo,
        _imageStorage,
      );

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final providerStr = prefs.getString('gz_sync_provider');
    if (providerStr == 'gdrive') _provider = SyncProvider.gdrive;
    _autoSyncEnabled = prefs.getBool('gz_sync_auto') ?? false;
    _autoSyncMessageCount = prefs.getInt('gz_sync_auto_count') ?? 5;
    _lastSyncTime = prefs.getInt('gz_sync_last');

    final tokensRaw = prefs.getString('gz_sync_tokens');
    if (tokensRaw != null) {
      final tokens = jsonDecode(tokensRaw) as Map<String, dynamic>;
      _dropboxAuth.loadTokens(tokens);
      _gdriveAuth.loadTokens(tokens);
    }

    _accountInfo = await _adapter.getAccountInfo();
  }

  Future<void> setProvider(SyncProvider p) async {
    _provider = p;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gz_sync_provider', p.name);
    _accountInfo = await _adapter.getAccountInfo();
  }

  Future<void> fullPush({
    void Function(SyncProgress)? onProgress,
  }) async {
    if (_status == SyncStatus.syncing) return;
    _status = SyncStatus.syncing;
    _lastError = null;

    try {
      final engine = _engine;
      await engine.pushEntities(
        onProgress: onProgress ?? (_) {},
      );
      _lastSyncTime = DateTime.now().millisecondsSinceEpoch;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('gz_sync_last', _lastSyncTime!);
      _status = SyncStatus.idle;
    } catch (e) {
      _lastError = e.toString();
      _status = SyncStatus.error;
    }
  }

  Future<void> fullPull({
    void Function(SyncProgress)? onProgress,
  }) async {
    if (_status == SyncStatus.syncing) return;
    _status = SyncStatus.syncing;
    _lastError = null;
    _conflicts.clear();

    try {
      final engine = _engine;
      await engine.pullEntities(
        onProgress: onProgress ?? (_) {},
        onConflict: (c) => _conflicts.add(c),
      );
      if (_conflicts.isNotEmpty) {
        _status = SyncStatus.conflict;
      } else {
        _lastSyncTime = DateTime.now().millisecondsSinceEpoch;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('gz_sync_last', _lastSyncTime!);
        _status = SyncStatus.idle;
      }
    } catch (e) {
      _lastError = e.toString();
      _status = SyncStatus.error;
    }
  }

  Future<void> fullSync({
    void Function(SyncProgress)? onProgress,
  }) async {
    await fullPush(onProgress: onProgress);
    if (_status != SyncStatus.error) {
      await fullPull(onProgress: onProgress);
    }
  }

  Future<void> resolveConflict(SyncConflict conflict, String choice) async {
    final engine = SyncEngine(
      _adapter,
      _manifestBuilder,
      _characterRepo,
      _chatRepo,
      _personaRepo,
      _presetRepo,
      _apiRepo,
      _lorebookRepo,
      _embeddingRepo,
      _imageStorage,
    );
    await engine.resolveConflict(conflict, choice);
    _conflicts.removeWhere((c) => c.key == conflict.key);
    if (_conflicts.isEmpty && _status == SyncStatus.conflict) {
      _status = SyncStatus.idle;
    }
  }

  Future<void> connectDropbox() async {
    await _dropboxAuth.connect();
    await _saveTokens();
  }

  Future<void> connectGDrive() async {
    await _gdriveAuth.connect();
    await _saveTokens();
  }

  Future<void> disconnect() async {
    switch (_provider) {
      case SyncProvider.dropbox:
        await _dropboxAuth.disconnect();
        break;
      case SyncProvider.gdrive:
        await _gdriveAuth.disconnect();
        break;
    }
    _accountInfo = null;
    await _saveTokens();
  }

  Future<void> setAutoSync(bool enabled, {int messageCount = 5}) async {
    _autoSyncEnabled = enabled;
    _autoSyncMessageCount = messageCount;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('gz_sync_auto', enabled);
    await prefs.setInt('gz_sync_auto_count', messageCount);
  }

  Future<void> incrementMessageCounter() async {
    if (!_autoSyncEnabled) return;
    _messageCounter++;
    if (_messageCounter >= _autoSyncMessageCount) {
      _messageCounter = 0;
      await fullPush();
    }
  }

  bool isConnected() {
    switch (_provider) {
      case SyncProvider.dropbox:
        return _dropboxAuth.isConnected;
      case SyncProvider.gdrive:
        return _gdriveAuth.isConnected;
    }
  }

  Future<void> _saveTokens() async {
    final prefs = await SharedPreferences.getInstance();
    final dbTokens = _dropboxAuth.saveTokens();
    final gdTokens = _gdriveAuth.saveTokens();
    final merged = <String, dynamic>{};
    if (dbTokens != null) merged.addAll(dbTokens);
    if (gdTokens != null) merged.addAll(gdTokens);
    await prefs.setString('gz_sync_tokens', jsonEncode(merged));
  }
}
