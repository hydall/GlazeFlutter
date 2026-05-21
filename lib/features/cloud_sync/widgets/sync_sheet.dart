import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/glaze_toast.dart';
import '../../../shared/widgets/sheet_view.dart';
import '../../../shared/widgets/glaze_bottom_sheet.dart';
import '../sync_provider.dart';
import '../sync_models.dart';
import '../services/sync_conflict.dart';
import '../services/sync_engine.dart';
import '../services/sync_service.dart';

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
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.get('gz_sync_include_api_keys');
    final val = raw is bool ? raw : false;
    if (!mounted) return;
    setState(() {
      _syncIncludeApiKeys = val;
    });
  }

  void _setIncludeApiKeys(bool val) async {
    final prefs = await SharedPreferences.getInstance();
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
        onBack: _goBack,
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!connected) ...[
                _buildSectionHeader('Connect a Cloud Provider'),
                const SizedBox(height: 4),
                _buildProviderSelectorButton(
                  icon: const DropboxIcon(size: 22, color: Colors.white),
                  label: _isConnecting ? 'Connecting...' : 'Dropbox',
                  color: context.colors.accent,
                  onPressed: _isConnecting || _isConnectingGdrive ? null : _connectDropbox,
                ),
                const SizedBox(height: 8),
                _buildProviderSelectorButton(
                  icon: const GDriveIcon(size: 22, color: Colors.white),
                  label: _isConnectingGdrive ? 'Connecting...' : 'Google Drive',
                  color: const Color(0xFF4285F4),
                  onPressed: _isConnecting || _isConnectingGdrive ? null : _connectGDrive,
                ),
                if (lastError != null) ...[
                  const SizedBox(height: 12),
                  _buildErrorCard(lastError),
                ],
              ] else ...[
                // Connected status card
                Container(
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
                            const _PulsingDot(color: Color(0xFFFF9800))
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
                ),

                // Folder ID row if GDrive
                if (provider == SyncProvider.gdrive && _gdriveFolderId != null)
                  Container(
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
                  ),

                // Conflict Banner / Resolve section
                if (conflicts.isNotEmpty)
                  Container(
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
                  ),

                // Sync result card
                if (_syncResult != null) ...[
                  _buildSyncResultCard(_syncResult!),
                ],

                // Linear Progress bar during Sync
                if ((status == SyncStatus.syncing || _isWiping) && progress != null) ...[
                  _buildProgressBar(progress),
                ],

                // Error Card if any
                if (lastError != null) ...[
                  const SizedBox(height: 12),
                  _buildErrorCard(lastError),
                ],

                // Manual Sync section
                const SizedBox(height: 16),
                _buildSectionHeader('Manual Sync'),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: _buildManualButton(
                        onPressed: isSyncing ? null : () => _doSync('push'),
                        icon: Icons.cloud_upload_outlined,
                        label: 'Push',
                        primary: false,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildManualButton(
                        onPressed: isSyncing ? null : () => _doSync('pull'),
                        icon: Icons.cloud_download_outlined,
                        label: 'Pull',
                        primary: true,
                      ),
                    ),
                  ],
                ),

                // Sync settings section
                const SizedBox(height: 16),
                _buildSectionHeader('Sync Settings'),
                const SizedBox(height: 4),
                // Auto Sync Toggle
                GestureDetector(
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
                ),
                // Auto sync threshold count picker
                if (autoEnabled && service != null) ...[
                  Container(
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
                        _buildCountButton(
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
                        _buildCountButton(
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
                  ),
                ],
                // Include API keys in sync
                GestureDetector(
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
                ),

                // Danger zone section
                const SizedBox(height: 16),
                Divider(color: Colors.white.withValues(alpha: 0.1), height: 1),
                const SizedBox(height: 16),
                _buildDangerButton(
                  icon: Icons.logout_rounded,
                  label: 'Disconnect',
                  onPressed: _isDisconnecting ? null : _disconnect,
                ),
                const SizedBox(height: 8),
                _buildDangerButton(
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
    );
  }

  void _goBack() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      context.go('/menu');
    }
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 12),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: context.cs.onSurfaceVariant.withValues(alpha: 0.7),
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildProviderSelectorButton({
    required Widget icon,
    required String label,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    final disabled = onPressed == null;
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onPressed,
        child: Opacity(
          opacity: disabled ? 0.7 : 1.0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                icon,
                const SizedBox(width: 10),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildManualButton({
    required VoidCallback? onPressed,
    required IconData icon,
    required String label,
    required bool primary,
  }) {
    final accent = context.colors.accent;
    final bg = primary ? accent : accent.withValues(alpha: 0.1);
    final fg = primary ? Colors.white : accent;
    final disabled = onPressed == null;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onPressed,
        child: Opacity(
          opacity: disabled ? 0.7 : 1.0,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 22, color: fg),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDangerButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    bool light = false,
  }) {
    final disabled = onPressed == null;
    final bg = light ? const Color(0xFFFF3B30).withValues(alpha: 0.05) : const Color(0xFFFF3B30).withValues(alpha: 0.1);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onPressed,
        child: Opacity(
          opacity: disabled ? 0.7 : 1.0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 22, color: const Color(0xFFFF3B30)),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFF3B30),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCountButton({required IconData icon, VoidCallback? onPressed}) {
    return Material(
      color: Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onPressed,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: onPressed == null ? Colors.white24 : Colors.white70),
        ),
      ),
    );
  }

  Widget _buildErrorCard(String error) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFF3B30).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFFF3B30), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              error,
              style: const TextStyle(color: Color(0xFFFF3B30), fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncResultCard(Map<String, dynamic> result) {
    final type = result['type'] as String;
    final pushed = result['pushed'] as int? ?? 0;
    final pulled = result['pulled'] as int? ?? 0;
    final deleted = result['deleted'] as int? ?? 0;
    final total = result['total'] as String?;
    final conflictsCount = result['conflictsCount'] as int? ?? 0;

    String message = '';
    Color cardColor = const Color(0xFF4CAF50).withValues(alpha: 0.1);
    Color textColor = const Color(0xFF4CAF50);

    if (type == 'push') {
      message = 'Pushed: $pushed items';
    } else if (type == 'pull') {
      message = 'Pulled: $pulled items';
      if (conflictsCount > 0) {
        message += ', $conflictsCount conflicts';
      }
      cardColor = context.colors.accent.withValues(alpha: 0.1);
      textColor = context.colors.accent;
    } else if (type == 'wipe') {
      message = (total == 'all') ? 'Cloud data wiped' : 'Deleted: $deleted/${total ?? "?"} items';
    } else {
      message = 'Full sync complete';
    }

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                color: textColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (type == 'pull' && conflictsCount > 0)
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                backgroundColor: Colors.orange.withValues(alpha: 0.15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              onPressed: () {
                // Focus / view conflicts
              },
              child: const Text(
                'Resolve',
                style: TextStyle(fontSize: 12, color: Colors.orangeAccent, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(SyncProgress p) {
    final indeterminate = p.total <= 0;
    final pct = indeterminate ? null : (p.current / p.total).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        if (p.message != null)
          Text(
            p.message!,
            style: TextStyle(
              fontSize: 12,
              color: context.cs.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: pct,
            backgroundColor: Colors.white.withValues(alpha: 0.1),
            valueColor: AlwaysStoppedAnimation<Color>(context.colors.accent),
            minHeight: 4,
          ),
        ),
        if (!indeterminate) ...[
          const SizedBox(height: 4),
          Text(
            '${p.current}/${p.total}',
            style: TextStyle(
              fontSize: 11,
              color: context.cs.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ],
    );
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

    // Step 1: Warning dialog
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

    // Step 2: Confirmation input dialog
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

          // Execute wipe!
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

class DropboxIcon extends StatelessWidget {
  final double size;
  final Color? color;
  const DropboxIcon({super.key, this.size = 22, this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _DropboxIconPainter(color ?? Colors.white),
    );
  }
}

class _DropboxIconPainter extends CustomPainter {
  final Color color;
  _DropboxIconPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final scaleX = size.width / 24.0;
    final scaleY = size.height / 24.0;

    void drawPath(List<Offset> points) {
      final path = Path();
      path.moveTo(points[0].dx * scaleX, points[0].dy * scaleY);
      for (var i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx * scaleX, points[i].dy * scaleY);
      }
      path.close();
      canvas.drawPath(path, paint);
    }

    drawPath([const Offset(6.5, 2), const Offset(2, 5), const Offset(6.5, 8), const Offset(11, 5)]);
    drawPath([const Offset(17.5, 2), const Offset(13, 5), const Offset(17.5, 8), const Offset(22, 5)]);
    drawPath([const Offset(6.5, 8), const Offset(2, 11), const Offset(6.5, 14), const Offset(11, 11)]);
    drawPath([const Offset(17.5, 8), const Offset(13, 11), const Offset(17.5, 14), const Offset(22, 11)]);
    drawPath([const Offset(12, 14), const Offset(7.5, 17), const Offset(12, 20), const Offset(16.5, 17)]);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class GDriveIcon extends StatelessWidget {
  final double size;
  final Color? color;
  const GDriveIcon({super.key, this.size = 22, this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _GDriveIconPainter(color ?? Colors.white),
    );
  }
}

class _GDriveIconPainter extends CustomPainter {
  final Color color;
  _GDriveIconPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final scaleX = size.width / 24.0;
    final scaleY = size.height / 24.0;

    final path = Path()
      ..moveTo(7.71 * scaleX, 3.5 * scaleY)
      ..lineTo(16.29 * scaleX, 3.5 * scaleY)
      ..lineTo(22.85 * scaleX, 15.0 * scaleY)
      ..lineTo(18.27 * scaleX, 22.5 * scaleY)
      ..lineTo(5.73 * scaleX, 22.5 * scaleY)
      ..lineTo(1.15 * scaleX, 15.0 * scaleY)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.3, end: 1.0).animate(_controller),
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: 0.4),
              blurRadius: 4,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}

