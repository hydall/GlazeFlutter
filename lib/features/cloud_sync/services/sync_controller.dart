import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/character_provider.dart';
import '../../../core/state/chat_session_ops_provider.dart';
import '../../../core/state/lorebook_provider.dart';
import '../../../core/state/shared_prefs_provider.dart';
import '../../../shared/theme/theme_provider.dart';
import '../../personas/persona_list_provider.dart';
import '../../settings/api_list_provider.dart';
import '../sync_provider.dart';
import '../sync_models.dart';
import 'sync_engine.dart';
import 'sync_service.dart';
import 'sync_conflict.dart';

/// Controller for cloud sync operations, separating business logic from UI.
class SyncController {
  final WidgetRef _ref;

  bool _isConnecting = false;
  bool _isConnectingGdrive = false;
  bool _isDisconnecting = false;
  bool _isWiping = false;
  Map<String, dynamic>? _syncResult;
  bool _syncIncludeApiKeys = false;
  String? _gdriveFolderId;

  SyncController(this._ref);

  bool get isConnecting => _isConnecting;
  bool get isConnectingGdrive => _isConnectingGdrive;
  bool get isDisconnecting => _isDisconnecting;
  bool get isWiping => _isWiping;
  Map<String, dynamic>? get syncResult => _syncResult;
  bool get syncIncludeApiKeys => _syncIncludeApiKeys;
  String? get gdriveFolderId => _gdriveFolderId;

  Future<void> loadIncludeApiKeys() async {
    final prefs = await _ref.read(sharedPreferencesProvider.future);
    final raw = prefs.get('gz_sync_include_api_keys');
    _syncIncludeApiKeys = raw is bool ? raw : false;
  }

  Future<void> setIncludeApiKeys(bool val) async {
    final prefs = await _ref.read(sharedPreferencesProvider.future);
    if (prefs.get('gz_sync_include_api_keys') is! bool) {
      await prefs.remove('gz_sync_include_api_keys');
    }
    await prefs.setBool('gz_sync_include_api_keys', val);
    _syncIncludeApiKeys = val;
  }

  Future<void> resolveFolderIdIfNeeded() async {
    final service = _ref.read(syncServiceProvider).value;
    if (service != null && service.provider == SyncProvider.gdrive && service.isConnected()) {
      if (service.gdriveFolderId != null) {
        _gdriveFolderId = service.gdriveFolderId;
      } else {
        _gdriveFolderId = await service.resolveGDriveFolderId();
      }
    }
  }

  void initStateFromService() {
    final service = _ref.read(syncServiceProvider).value;
    if (service != null) {
      _ref.read(syncStatusProvider.notifier).state = service.status;
      _ref.read(syncConnectedProvider.notifier).state = service.isConnected();
      _ref.read(syncProviderProvider.notifier).state = service.provider;
      _ref.read(syncAutoEnabledProvider.notifier).state = service.autoSyncEnabled;
    }
  }

  /// Returns error message or null on success.
  Future<String?> connectDropbox() async {
    _isConnecting = true;
    try {
      final service = await _ref.read(syncServiceProvider.future);
      await service.connectDropbox();
      _ref.read(syncConnectedProvider.notifier).state = true;
      _ref.read(syncProviderProvider.notifier).state = SyncProvider.dropbox;
      _ref.read(syncStatusProvider.notifier).state = service.status;
      _ref.read(syncLastErrorProvider.notifier).state = null;
      await resolveFolderIdIfNeeded();
      return null;
    } catch (e) {
      return 'Dropbox connection failed: $e';
    } finally {
      _isConnecting = false;
    }
  }

  Future<String?> connectGDrive() async {
    _isConnectingGdrive = true;
    try {
      final service = await _ref.read(syncServiceProvider.future);
      await service.connectGDrive();
      _ref.read(syncConnectedProvider.notifier).state = true;
      _ref.read(syncProviderProvider.notifier).state = SyncProvider.gdrive;
      _ref.read(syncStatusProvider.notifier).state = service.status;
      _ref.read(syncLastErrorProvider.notifier).state = null;
      await resolveFolderIdIfNeeded();
      return null;
    } catch (e) {
      return 'Google Drive connection failed: $e';
    } finally {
      _isConnectingGdrive = false;
    }
  }

  Future<String?> disconnect() async {
    final service = _ref.read(syncServiceProvider).valueOrNull;
    if (service == null) return null;

    _isDisconnecting = true;
    try {
      await service.disconnect();
      _ref.read(syncConnectedProvider.notifier).state = false;
      _ref.read(syncProviderProvider.notifier).state = SyncProvider.dropbox;
      _ref.read(syncStatusProvider.notifier).state = service.status;
      _syncResult = null;
      _gdriveFolderId = null;
      return null;
    } catch (e) {
      return 'Disconnect failed: $e';
    } finally {
      _isDisconnecting = false;
    }
  }

  /// Returns a result map or throws.
  Future<Map<String, dynamic>?> wipeCloudData({
    required void Function(SyncProgress p) onProgress,
    required String providerLabel,
  }) async {
    final service = _ref.read(syncServiceProvider).value;
    if (service == null) return null;

    _isWiping = true;
    _syncResult = null;
    _ref.read(syncStatusProvider.notifier).state = SyncStatus.syncing;

    try {
      await service.wipeCloudData(onProgress: onProgress);
      _ref.read(syncStatusProvider.notifier).state = service.status;
      _syncResult = {'type': 'wipe', 'total': 'all'};
      return _syncResult;
    } catch (e) {
      _ref.read(syncStatusProvider.notifier).state = SyncStatus.error;
      rethrow;
    } finally {
      _isWiping = false;
      _ref.read(syncProgressProvider.notifier).state = null;
      _ref.read(syncStatusProvider.notifier).state =
          _ref.read(syncServiceProvider).value?.status ?? SyncStatus.idle;
    }
  }

  Future<String?> doSync(String mode) async {
    _ref.read(syncStatusProvider.notifier).state = SyncStatus.syncing;
    _ref.read(syncLastErrorProvider.notifier).state = null;
    _syncResult = null;

    int itemsCount = 0;
    late final SyncService service;
    try {
      service = await _ref.read(syncServiceProvider.future);
      switch (mode) {
        case 'push':
          await service.fullPush(
            includeApiKeys: _syncIncludeApiKeys,
            onProgress: (p) {
              _ref.read(syncProgressProvider.notifier).state = p;
              itemsCount = p.total;
            },
          );
          _syncResult = {'type': 'push', 'pushed': itemsCount};
          _ref.read(syncStatusProvider.notifier).state = service.status;
          _ref.read(syncConflictsProvider.notifier).state = service.conflicts;
          return 'Push completed ($itemsCount items)';

        case 'pull':
          await service.fullPull(
            onProgress: (p) {
              _ref.read(syncProgressProvider.notifier).state = p;
              itemsCount = p.total;
            },
          );
          _syncResult = {
            'type': 'pull',
            'pulled': itemsCount,
            'conflictsCount': service.conflicts.length,
          };
          invalidateDataProviders();
          _ref.read(syncStatusProvider.notifier).state = service.status;
          _ref.read(syncConflictsProvider.notifier).state = service.conflicts;
          if (service.conflicts.isNotEmpty) {
            return 'Pull completed with ${service.conflicts.length} conflicts';
          }
          return 'Pull completed ($itemsCount items)';

        case 'full':
          await service.fullSync(
            includeApiKeys: _syncIncludeApiKeys,
            onProgress: (p) {
              _ref.read(syncProgressProvider.notifier).state = p;
              itemsCount = p.total;
            },
          );
          _syncResult = {'type': 'full'};
          invalidateDataProviders();
          _ref.read(syncStatusProvider.notifier).state = service.status;
          _ref.read(syncConflictsProvider.notifier).state = service.conflicts;
          return 'Full sync completed';
      }
    } catch (e) {
      _ref.read(syncLastErrorProvider.notifier).state = e.toString();
      _ref.read(syncStatusProvider.notifier).state = service.status;
      _ref.read(syncConflictsProvider.notifier).state = service.conflicts;
      return 'Sync failed: $e';
    } finally {
      _ref.read(syncProgressProvider.notifier).state = null;
    }
    return null;
  }

  Future<String?> resolveConflict(SyncConflict conflict, String choice) async {
    final service = _ref.read(syncServiceProvider).valueOrNull;
    if (service == null) return null;
    try {
      await service.resolveConflict(conflict, choice);
      _ref.read(syncConflictsProvider.notifier).state = List.from(service.conflicts);
      _ref.read(syncStatusProvider.notifier).state = service.status;
      if (service.conflicts.isEmpty) {
        invalidateDataProviders();
        return choice == 'cloud' ? 'Cloud version applied' : 'Local version kept';
      }
      return null;
    } catch (e) {
      _ref.read(syncLastErrorProvider.notifier).state = e.toString();
      _ref.read(syncStatusProvider.notifier).state = service.status;
      _ref.read(syncConflictsProvider.notifier).state = List.from(service.conflicts);
      return 'Could not resolve conflict: $e';
    }
  }

  Future<String?> resolveAllConflicts(String choice) async {
    final service = _ref.read(syncServiceProvider).valueOrNull;
    if (service == null) return null;
    _ref.read(syncStatusProvider.notifier).state = SyncStatus.syncing;
    try {
      await service.resolveAllConflicts(choice);
      _ref.read(syncConflictsProvider.notifier).state = List.from(service.conflicts);
      _ref.read(syncStatusProvider.notifier).state = service.status;
      invalidateDataProviders();
      return choice == 'cloud'
          ? 'All conflicts resolved: cloud versions applied'
          : 'All conflicts resolved: local versions kept';
    } catch (e) {
      _ref.read(syncLastErrorProvider.notifier).state = e.toString();
      _ref.read(syncConflictsProvider.notifier).state = List.from(service.conflicts);
      return 'Could not resolve conflicts: $e';
    } finally {
      _ref.read(syncStatusProvider.notifier).state = service.status;
      _ref.read(syncConflictsProvider.notifier).state = List.from(service.conflicts);
    }
  }

  void invalidateDataProviders() {
    _ref.invalidate(charactersProvider);
    _ref.invalidate(personaListProvider);
    _ref.invalidate(apiListProvider);
    _ref.invalidate(lorebooksProvider);
    _ref.invalidate(chatSessionOpsProvider);
    _ref.read(themeProvider.notifier).reload();
  }

  Future<void> setAutoSync(bool val) async {
    final service = _ref.read(syncServiceProvider).value;
    if (service != null) {
      await service.setAutoSync(val, messageCount: service.autoSyncMessageCount);
      _ref.read(syncAutoEnabledProvider.notifier).state = val;
    }
  }

  Future<void> updateAutoSyncThreshold(int count) async {
    final service = _ref.read(syncServiceProvider).value;
    if (service != null) {
      await service.setAutoSync(service.autoSyncEnabled, messageCount: count);
    }
  }
}
