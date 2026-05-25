import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/state/shared_prefs_provider.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/glaze_toast.dart';
import '../../../shared/widgets/sheet_view.dart';
import '../../../shared/widgets/glaze_bottom_sheet.dart';
import '../sync_provider.dart';
import '../sync_models.dart';
import '../services/sync_conflict.dart';
import '../services/sync_service.dart';
import 'sync_icons.dart';
import 'sync_sheet_widgets.dart';

class SyncSheet extends ConsumerStatefulWidget {
  const SyncSheet({super.key});

  @override
  ConsumerState<SyncSheet> createState() => _SyncSheetState();
}

class _SyncSheetState extends ConsumerState<SyncSheet> {
  bool _isConnecting = false;
  bool _isConnectingGdrive = false;
  bool _isDisconnecting = false;
  bool _isWiping = false;
  Map<String, dynamic>? _syncResult;
  bool _syncIncludeApiKeys = false;
  String? _gdriveFolderId;

  @override
  void initState() {
    super.initState();
    _loadIncludeApiKeys();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final service = ref.read(syncServiceProvider).value;
      if (service != null) {
        ref.read(syncStatusProvider.notifier).state = service.status;
        ref.read(syncConnectedProvider.notifier).state = service.isConnected();
        ref.read(syncProviderProvider.notifier).state = service.provider;
        ref.read(syncAutoEnabledProvider.notifier).state = service.autoSyncEnabled;
        _resolveFolderIdIfNeeded();
      }
    });
  }

  void _loadIncludeApiKeys() async {
    final prefs = await ref.read(sharedPreferencesProvider.future);
    final raw = prefs.get('gz_sync_include_api_keys');
    final val = raw is bool ? raw : false;
    if (!mounted) return;
    setState(() {
      _syncIncludeApiKeys = val;
    });
  }

  void _setIncludeApiKeys(bool val) async {
    final prefs = await ref.read(sharedPreferencesProvider.future);
    if (prefs.get('gz_sync_include_api_keys') is! bool) {
      await prefs.remove('gz_sync_include_api_keys');
    }
    await prefs.setBool('gz_sync_include_api_keys', val);
    if (!mounted) return;
    setState(() {
      _syncIncludeApiKeys = val;
    });
  }

  void _resolveFolderIdIfNeeded() async {
    final service = ref.read(syncServiceProvider).value;
    if (service != null && service.provider == SyncProvider.gdrive && service.isConnected()) {
      if (service.gdriveFolderId != null) {
        setState(() => _gdriveFolderId = service.gdriveFolderId);
      } else {
        final id = await service.resolveGDriveFolderId();
        if (mounted) {
          setState(() => _gdriveFolderId = id);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(syncServiceProvider);
    final status = ref.watch(syncStatusProvider);
    final provider = ref.watch(syncProviderProvider);
    final connected = ref.watch(syncConnectedProvider);
    final progress = ref.watch(syncProgressProvider);
    final conflicts = ref.watch(syncConflictsProvider);
    final lastError = ref.watch(syncLastErrorProvider);
    final autoEnabled = ref.watch(syncAutoEnabledProvider);
    final service = ref.watch(syncServiceProvider).value;

    final isSyncing = status == SyncStatus.syncing || _isWiping;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _goBack();
      },
      child: SheetView(
        title: 'Cloud Sync',
        showBack: true,
        fitContent: true,
        onBack: _goBack,
        body: Builder(
          builder: (innerContext) => SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16, 12 + MediaQuery.paddingOf(innerContext).top, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!connected) ...[
                buildSyncSectionHeader(context, 'Connect a Cloud Provider'),
                const SizedBox(height: 4),
                buildSyncProviderButton(
                  icon: const DropboxIcon(size: 22, color: Colors.white),
                  label: _isConnecting ? 'Connecting...' : 'Dropbox',
                  color: context.colors.accent,
                  onPressed: _isConnecting || _isConnectingGdrive ? null : _connectDropbox,
                ),
                const SizedBox(height: 8),
                buildSyncProviderButton(
                  icon: const GDriveIcon(size: 22, color: Colors.white),
                  label: _isConnectingGdrive ? 'Connecting...' : 'Google Drive',
                  color: const Color(0xFF4285F4),
                  onPressed: _isConnecting || _isConnectingGdrive ? null : _connectGDrive,
                ),
                if (lastError != null) ...[
                  const SizedBox(height: 12),
                  buildSyncErrorCard(lastError),
                ],
              ] else ...[
                _buildConnectedCard(context, status, provider, service),
                if (provider == SyncProvider.gdrive && _gdriveFolderId != null)
                  _buildFolderIdRow(context),
                if (conflicts.isNotEmpty)
                  _buildConflictBanner(context, conflicts),
                if (_syncResult != null)
                  buildSyncResultCard(context, _syncResult!),
                if ((status == SyncStatus.syncing || _isWiping) && progress != null)
                  buildSyncProgressBar(context, progress),
                if (lastError != null) ...[
                  const SizedBox(height: 12),
                  buildSyncErrorCard(lastError),
                ],
                const SizedBox(height: 16),
                buildSyncSectionHeader(context, 'Manual Sync'),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: buildSyncManualButton(
                        context: context,
                        onPressed: isSyncing ? null : () => _doSync('push'),
                        icon: Icons.cloud_upload_outlined,
                        label: 'Push',
                        primary: false,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: buildSyncManualButton(
                        context: context,
                        onPressed: isSyncing ? null : () => _doSync('pull'),
                        icon: Icons.cloud_download_outlined,
                        label: 'Pull',
                        primary: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                buildSyncSectionHeader(context, 'Sync Settings'),
                const SizedBox(height: 4),
                _buildAutoSyncToggle(context, autoEnabled, service),
                if (autoEnabled && service != null)
                  _buildAutoSyncThresholdRow(context, service),
                _buildIncludeApiKeysToggle(context),
                const SizedBox(height: 16),
                Divider(color: Colors.white.withValues(alpha: 0.1), height: 1),
                const SizedBox(height: 16),
                buildSyncDangerButton(
                  icon: Icons.logout_rounded,
                  label: 'Disconnect',
                  onPressed: _isDisconnecting ? null : _disconnect,
                ),
                const SizedBox(height: 8),
                buildSyncDangerButton(
                  icon: Icons.delete_outline_rounded,
                  label: _isWiping ? 'Wiping...' : 'Wipe Cloud Data',
                  onPressed: _isWiping ? null : _wipeCloudData,
                  light: true,
                ),
              ],
            ],
          ),
        ),
        ),

      ),
    );
  }

  Widget _buildConnectedCard(BuildContext context, SyncStatus status, SyncProvider provider, SyncService? service) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.accent.withValues(alpha: 0.05),
        border: Border.all(color: context.colors.accent.withValues(alpha: 0.15)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (provider == SyncProvider.dropbox)
                DropboxIcon(size: 24, color: context.colors.accent)
              else
                const GDriveIcon(size: 24, color: Color(0xFF4285F4)),
              const SizedBox(width: 8),
              Text(
                provider == SyncProvider.dropbox ? 'Dropbox' : 'Google Drive',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: context.cs.onSurface,
                ),
              ),
              const Spacer(),
              if (status == SyncStatus.syncing)
                const PulsingDot(color: Color(0xFFFF9800))
              else if (status == SyncStatus.error)
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFF3B30),
                    shape: BoxShape.circle,
                  ),
                )
              else
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Color(0xFF4CAF50),
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
          if (service?.accountInfo != null && service!.accountInfo!['email'] != null) ...[
            const SizedBox(height: 6),
            Text(
              service.accountInfo!['email'] as String,
              style: TextStyle(
                fontSize: 13,
                color: context.cs.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            _getStatusLabel(status, service),
            style: TextStyle(
              fontSize: 13,
              color: context.cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderIdRow(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text(
            'Folder ID',
            style: TextStyle(
              fontSize: 12,
              color: context.cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _gdriveFolderId!,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: Colors.white70,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.copy, size: 16, color: Colors.white54),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _gdriveFolderId!));
              GlazeToast.show(context, 'Folder ID copied');
            },
          ),
        ],
      ),
    );
  }

  Widget _buildConflictBanner(BuildContext context, List<SyncConflict> conflicts) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.05),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.15)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 20),
              const SizedBox(width: 8),
              Text(
                'Sync Conflicts (${conflicts.length})',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.orangeAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => _resolveAllConflicts('local'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    backgroundColor: Colors.blueAccent.withValues(alpha: 0.15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Keep All Local', style: TextStyle(color: Colors.blueAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextButton(
                  onPressed: () => _resolveAllConflicts('cloud'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    backgroundColor: Colors.greenAccent.withValues(alpha: 0.15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Use All Cloud', style: TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...conflicts.map((c) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      c.name,
                      style: const TextStyle(fontSize: 13, color: Colors.white70),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _resolveConflict(c, 'local'),
                    child: const Text('Keep Local', style: TextStyle(color: Colors.blueAccent)),
                  ),
                  TextButton(
                    onPressed: () => _resolveConflict(c, 'cloud'),
                    child: const Text('Use Cloud', style: TextStyle(color: Colors.greenAccent)),
                  ),
                ],
              ),
            )),
        ],
      ),
    );
  }

  Widget _buildAutoSyncToggle(BuildContext context, bool autoEnabled, SyncService? service) {
    return GestureDetector(
      onTap: () {
        _setAutoSync(!autoEnabled);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        color: Colors.transparent,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Enable Auto-Sync',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: context.cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Automatically sync after every N messages',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: autoEnabled,
              onChanged: _setAutoSync,
              activeThumbColor: context.colors.accent,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAutoSyncThresholdRow(BuildContext context, SyncService service) {
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      child: Row(
        children: [
          Text(
            'Every ',
            style: TextStyle(
              fontSize: 14,
              color: context.cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          buildSyncCountButton(
            icon: Icons.remove,
            onPressed: service.autoSyncMessageCount > 1
                ? () => _updateAutoSyncThreshold(service.autoSyncMessageCount - 1)
                : null,
          ),
          Container(
            width: 50,
            alignment: Alignment.center,
            child: Text(
              '${service.autoSyncMessageCount}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: context.cs.onSurface,
              ),
            ),
          ),
          buildSyncCountButton(
            icon: Icons.add,
            onPressed: service.autoSyncMessageCount < 50
                ? () => _updateAutoSyncThreshold(service.autoSyncMessageCount + 1)
                : null,
          ),
          const SizedBox(width: 8),
          Text(
            ' messages',
            style: TextStyle(
              fontSize: 14,
              color: context.cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIncludeApiKeysToggle(BuildContext context) {
    return GestureDetector(
      onTap: () {
        _setIncludeApiKeys(!_syncIncludeApiKeys);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        color: Colors.transparent,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Include API Keys in Sync',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: context.cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Send provider API keys to cloud backup',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: _syncIncludeApiKeys,
              onChanged: _setIncludeApiKeys,
              activeThumbColor: context.colors.accent,
            ),
          ],
        ),
      ),
    );
  }

  void _goBack() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      context.go('/menu');
    }
  }

  String _getStatusLabel(SyncStatus status, SyncService? service) {
    if (_isWiping) return 'Wiping cloud data...';
    if (status == SyncStatus.syncing) return 'Syncing...';
    if (status == SyncStatus.error) return 'Error';
    if (status == SyncStatus.conflict) return 'Conflict detected';
    if (service?.lastSyncTime != null) {
      return 'Last sync: ${_formatTimeAgo(service!.lastSyncTime!)}';
    }
    return 'Ready';
  }

  String _formatTimeAgo(int ts) {
    final diff = (DateTime.now().millisecondsSinceEpoch - ts) ~/ 1000;
    if (diff < 60) return 'just now';
    if (diff < 3600) return '${diff ~/ 60}m ago';
    if (diff < 86400) return '${diff ~/ 3600}h ago';
    return '${diff ~/ 86400}d ago';
  }

  Future<void> _connectDropbox() async {
    setState(() => _isConnecting = true);
    try {
      final service = await ref.read(syncServiceProvider.future);
      await service.connectDropbox();
      ref.read(syncConnectedProvider.notifier).state = true;
      ref.read(syncProviderProvider.notifier).state = SyncProvider.dropbox;
      ref.read(syncStatusProvider.notifier).state = service.status;
      ref.read(syncLastErrorProvider.notifier).state = null;
      _resolveFolderIdIfNeeded();
    } catch (e) {
      if (mounted) {
        GlazeToast.error(context, 'Dropbox connection failed: ', e);
      }
    } finally {
      if (mounted) {
        setState(() => _isConnecting = false);
      }
    }
  }

  Future<void> _connectGDrive() async {
    setState(() => _isConnectingGdrive = true);
    try {
      final service = await ref.read(syncServiceProvider.future);
      await service.connectGDrive();
      ref.read(syncConnectedProvider.notifier).state = true;
      ref.read(syncProviderProvider.notifier).state = SyncProvider.gdrive;
      ref.read(syncStatusProvider.notifier).state = service.status;
      ref.read(syncLastErrorProvider.notifier).state = null;
      _resolveFolderIdIfNeeded();
    } catch (e) {
      if (mounted) {
        GlazeToast.error(context, 'Google Drive connection failed: ', e);
      }
    } finally {
      if (mounted) {
        setState(() => _isConnectingGdrive = false);
      }
    }
  }

  Future<void> _disconnect() async {
    final service = ref.read(syncServiceProvider).valueOrNull;
    if (service == null) return;

    final confirmed = await GlazeBottomSheet.show<bool>(
      context,
      title: 'Disconnect',
      bigInfo: const BottomSheetBigInfo(
        icon: Icons.link_off_rounded,
        description: 'Disconnect cloud sync? Your local data will remain intact.',
      ),
      items: [
        BottomSheetItem(
          label: 'Disconnect',
          isDestructive: true,
          centered: true,
          onTap: () => Navigator.of(context, rootNavigator: true).pop(true),
        ),
        BottomSheetItem(
          label: 'Cancel',
          centered: true,
          onTap: () => Navigator.of(context, rootNavigator: true).pop(false),
        ),
      ],
    );

    if (confirmed != true) return;

    setState(() => _isDisconnecting = true);
    try {
      await service.disconnect();
      ref.read(syncConnectedProvider.notifier).state = false;
      ref.read(syncProviderProvider.notifier).state = SyncProvider.dropbox;
      ref.read(syncStatusProvider.notifier).state = service.status;
      setState(() {
        _syncResult = null;
        _gdriveFolderId = null;
      });
    } catch (e) {
      if (mounted) {
        GlazeToast.error(context, 'Disconnect failed: ', e);
      }
    } finally {
      if (mounted) {
        setState(() => _isDisconnecting = false);
      }
    }
  }

  Future<void> _wipeCloudData() async {
    final service = ref.read(syncServiceProvider).value;
    if (service == null) return;

    final providerLabel = service.provider == SyncProvider.dropbox ? 'Dropbox' : 'Google Drive';

    final confirmed = await GlazeBottomSheet.show<bool>(
      context,
      title: 'Wipe Cloud Data',
      bigInfo: const BottomSheetBigInfo(
        icon: Icons.warning_amber_rounded,
        description: 'Delete ALL data from cloud? This cannot be undone. Your local data will remain intact.',
      ),
      items: [
        BottomSheetItem(
          label: 'Wipe Cloud Data',
          isDestructive: true,
          centered: true,
          onTap: () => Navigator.of(context, rootNavigator: true).pop(true),
        ),
        BottomSheetItem(
          label: 'Cancel',
          centered: true,
          onTap: () => Navigator.of(context, rootNavigator: true).pop(false),
        ),
      ],
    );

    if (confirmed != true) return;

    if (!mounted) return;
    await GlazeBottomSheet.show<void>(
      context,
      title: 'Wipe Cloud Data',
      bigInfo: BottomSheetBigInfo(
        icon: Icons.delete_forever_rounded,
        description: 'Are you sure? Type "$providerLabel" to confirm.',
      ),
      input: BottomSheetInput(
        placeholder: providerLabel,
        confirmLabel: 'Confirm',
        onConfirm: (typed) async {
          if (typed.trim().toLowerCase() != providerLabel.toLowerCase()) {
            if (context.mounted) {
              GlazeToast.show(context, 'Wipe cancelled: Provider name did not match.', isError: true);
            }
            return;
          }

          setState(() {
            _isWiping = true;
            _syncResult = null;
          });
          ref.read(syncStatusProvider.notifier).state = SyncStatus.syncing;

          try {
            await service.wipeCloudData(
              onProgress: (p) {
                if (mounted) {
                  ref.read(syncProgressProvider.notifier).state = p;
                }
              },
            );
            if (!mounted) return;
            ref.read(syncStatusProvider.notifier).state = service.status;
            setState(() {
              _syncResult = {
                'type': 'wipe',
                'total': 'all',
              };
            });
            GlazeToast.show(context, 'Cloud data wiped successfully.');
          } catch (e) {
            if (!mounted) return;
            ref.read(syncStatusProvider.notifier).state = SyncStatus.error;
            GlazeToast.error(context, 'Wipe failed: ', e);
          } finally {
            if (mounted) {
              setState(() => _isWiping = false);
              ref.read(syncProgressProvider.notifier).state = null;
              ref.read(syncStatusProvider.notifier).state =
                  ref.read(syncServiceProvider).value?.status ?? SyncStatus.idle;
            }
          }
        },
      ),
    );
  }

  Future<void> _doSync(String mode) async {
    ref.read(syncStatusProvider.notifier).state = SyncStatus.syncing;
    ref.read(syncLastErrorProvider.notifier).state = null;
    setState(() => _syncResult = null);

    int itemsCount = 0;
    late final SyncService service;
    try {
      service = await ref.read(syncServiceProvider.future);
      switch (mode) {
        case 'push':
          await service.fullPush(
            includeApiKeys: _syncIncludeApiKeys,
            onProgress: (p) {
              if (mounted) {
                ref.read(syncProgressProvider.notifier).state = p;
                itemsCount = p.total;
              }
            },
          );
          if (mounted) {
            setState(() {
              _syncResult = {
                'type': 'push',
                'pushed': itemsCount,
              };
            });
            GlazeToast.show(context, 'Push completed ($itemsCount items)');
          }
          break;
        case 'pull':
          await service.fullPull(
            onProgress: (p) {
              if (mounted) {
                ref.read(syncProgressProvider.notifier).state = p;
                itemsCount = p.total;
              }
            },
          );
          if (mounted) {
            setState(() {
              _syncResult = {
                'type': 'pull',
                'pulled': itemsCount,
                'conflictsCount': service.conflicts.length,
              };
            });
            if (service.conflicts.isNotEmpty) {
              GlazeToast.show(context, 'Pull completed with ${service.conflicts.length} conflicts');
            } else {
              GlazeToast.show(context, 'Pull completed ($itemsCount items)');
            }
          }
          break;
        case 'full':
          await service.fullSync(
            includeApiKeys: _syncIncludeApiKeys,
            onProgress: (p) {
              if (mounted) {
                ref.read(syncProgressProvider.notifier).state = p;
                itemsCount = p.total;
              }
            },
          );
          if (mounted) {
            setState(() {
              _syncResult = {
                'type': 'full',
              };
            });
            GlazeToast.show(context, 'Full sync completed');
          }
          break;
      }
      ref.read(syncStatusProvider.notifier).state = service.status;
      ref.read(syncConflictsProvider.notifier).state = service.conflicts;
    } catch (e) {
      ref.read(syncLastErrorProvider.notifier).state = e.toString();
      ref.read(syncStatusProvider.notifier).state = service.status;
      ref.read(syncConflictsProvider.notifier).state = service.conflicts;
      if (mounted) {
        GlazeToast.errorWithCopy(context, 'Sync failed: ', e);
      }
    } finally {
      ref.read(syncProgressProvider.notifier).state = null;
    }
  }

  Future<void> _resolveConflict(SyncConflict conflict, String choice) async {
    final service = ref.read(syncServiceProvider).valueOrNull;
    if (service == null) return;
    await service.resolveConflict(conflict, choice);
    ref.read(syncConflictsProvider.notifier).state = List.from(service.conflicts);
    if (service.conflicts.isEmpty) {
      ref.read(syncStatusProvider.notifier).state = SyncStatus.idle;
    }
  }

  Future<void> _resolveAllConflicts(String choice) async {
    final service = ref.read(syncServiceProvider).valueOrNull;
    if (service == null) return;
    ref.read(syncStatusProvider.notifier).state = SyncStatus.syncing;
    await service.resolveAllConflicts(choice);
    ref.read(syncConflictsProvider.notifier).state = List.from(service.conflicts);
    ref.read(syncStatusProvider.notifier).state = service.status;
    if (mounted) {
      GlazeToast.show(context, choice == 'cloud' ? 'All conflicts resolved: cloud versions applied' : 'All conflicts resolved: local versions kept');
    }
  }

  void _setAutoSync(bool val) async {
    final service = ref.read(syncServiceProvider).value;
    if (service != null) {
      await service.setAutoSync(val, messageCount: service.autoSyncMessageCount);
      ref.read(syncAutoEnabledProvider.notifier).state = val;
    }
  }

  void _updateAutoSyncThreshold(int count) async {
    final service = ref.read(syncServiceProvider).value;
    if (service != null) {
      await service.setAutoSync(service.autoSyncEnabled, messageCount: count);
      setState(() {});
    }
  }
}
