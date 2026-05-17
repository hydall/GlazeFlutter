import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/glaze_toast.dart';
import '../sync_provider.dart';
import '../sync_models.dart';
import '../services/sync_conflict.dart';
import '../services/sync_engine.dart';

class SyncSheet extends ConsumerStatefulWidget {
  const SyncSheet({super.key});

  @override
  ConsumerState<SyncSheet> createState() => _SyncSheetState();
}

class _SyncSheetState extends ConsumerState<SyncSheet> {
  @override
  Widget build(BuildContext context) {
    final status = ref.watch(syncStatusProvider);
    final provider = ref.watch(syncProviderProvider);
    final connected = ref.watch(syncConnectedProvider);
    final progress = ref.watch(syncProgressProvider);
    final conflicts = ref.watch(syncConflictsProvider);
    final lastError = ref.watch(syncLastErrorProvider);
    final autoEnabled = ref.watch(syncAutoEnabledProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        title: const Text('Cloud Sync'),
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
        backgroundColor: const Color(0xFF16213E),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ProviderSelector(
            provider: provider,
            onChanged: (p) => ref.read(syncProviderProvider.notifier).state = p,
          ),
          const SizedBox(height: 16),
          _ConnectButton(
            provider: provider,
            connected: connected,
            onConnect: _connect,
            onDisconnect: _disconnect,
          ),
          if (connected) ...[
            const SizedBox(height: 16),
            _SyncActions(
              status: status,
              onPush: () => _doSync('push'),
              onPull: () => _doSync('pull'),
              onFullSync: () => _doSync('full'),
            ),
          ],
          if (progress != null) ...[
            const SizedBox(height: 16),
            _ProgressBar(progress: progress),
          ],
          if (lastError != null) ...[
            const SizedBox(height: 16),
            _ErrorCard(error: lastError),
          ],
          if (conflicts.isNotEmpty) ...[
            const SizedBox(height: 16),
            _ConflictList(
              conflicts: conflicts,
              onResolve: _resolveConflict,
            ),
          ],
          const SizedBox(height: 16),
          _AutoSyncToggle(
            enabled: autoEnabled,
            onChanged: (v) => ref.read(syncAutoEnabledProvider.notifier).state = v,
          ),
        ],
      ),
    );
  }

  Future<void> _connect() async {
    final service = ref.read(syncServiceProvider).value;
    if (service == null) return;
    final provider = ref.read(syncProviderProvider);
    try {
      if (provider == SyncProvider.dropbox) {
        await service.connectDropbox();
      } else {
        await service.connectGDrive();
      }
      ref.read(syncConnectedProvider.notifier).state = true;
    } catch (e) {
      if (mounted) {
        GlazeToast.error(context, 'Connection failed: ', e);
      }
    }
  }

  Future<void> _disconnect() async {
    final service = ref.read(syncServiceProvider).value;
    if (service == null) return;
    await service.disconnect();
    ref.read(syncConnectedProvider.notifier).state = false;
  }

  Future<void> _doSync(String mode) async {
    final service = ref.read(syncServiceProvider).value;
    if (service == null) return;

    ref.read(syncStatusProvider.notifier).state = SyncStatus.syncing;
    ref.read(syncLastErrorProvider.notifier).state = null;

    try {
      switch (mode) {
        case 'push':
          await service.fullPush(
            onProgress: (p) => ref.read(syncProgressProvider.notifier).state = p,
          );
          break;
        case 'pull':
          await service.fullPull(
            onProgress: (p) => ref.read(syncProgressProvider.notifier).state = p,
          );
          break;
        case 'full':
          await service.fullSync(
            onProgress: (p) => ref.read(syncProgressProvider.notifier).state = p,
          );
          break;
      }
      ref.read(syncStatusProvider.notifier).state = service.status;
      ref.read(syncConflictsProvider.notifier).state = service.conflicts;
    } catch (e) {
      ref.read(syncLastErrorProvider.notifier).state = e.toString();
      ref.read(syncStatusProvider.notifier).state = SyncStatus.error;
    }
    ref.read(syncProgressProvider.notifier).state = null;
  }

  Future<void> _resolveConflict(SyncConflict conflict, String choice) async {
    final service = ref.read(syncServiceProvider).value;
    if (service == null) return;
    await service.resolveConflict(conflict, choice);
    ref.read(syncConflictsProvider.notifier).state = List.from(service.conflicts);
    if (service.conflicts.isEmpty) {
      ref.read(syncStatusProvider.notifier).state = SyncStatus.idle;
    }
  }
}

class _ProviderSelector extends StatelessWidget {
  final SyncProvider provider;
  final ValueChanged<SyncProvider> onChanged;

  const _ProviderSelector({required this.provider, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF16213E),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Provider', style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 8),
            Row(
              children: [
                _ProviderChip(
                  label: 'Dropbox',
                  selected: provider == SyncProvider.dropbox,
                  onTap: () => onChanged(SyncProvider.dropbox),
                ),
                const SizedBox(width: 8),
                _ProviderChip(
                  label: 'Google Drive',
                  selected: provider == SyncProvider.gdrive,
                  onTap: () => onChanged(SyncProvider.gdrive),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProviderChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ProviderChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: const Color(0xFF0F3460),
      backgroundColor: const Color(0xFF1A1A2E),
      labelStyle: TextStyle(color: selected ? Colors.white : Colors.white54),
    );
  }
}

class _ConnectButton extends StatelessWidget {
  final SyncProvider provider;
  final bool connected;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  const _ConnectButton({
    required this.provider,
    required this.connected,
    required this.onConnect,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    if (connected) {
      return OutlinedButton.icon(
        onPressed: onDisconnect,
        icon: const Icon(Icons.link_off, color: Colors.redAccent),
        label: const Text('Disconnect', style: TextStyle(color: Colors.redAccent)),
        style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.redAccent)),
      );
    }
    return FilledButton.icon(
      onPressed: onConnect,
      icon: const Icon(Icons.link),
      label: Text('Connect ${provider == SyncProvider.dropbox ? 'Dropbox' : 'Google Drive'}'),
      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F3460)),
    );
  }
}

class _SyncActions extends StatelessWidget {
  final SyncStatus status;
  final VoidCallback onPush;
  final VoidCallback onPull;
  final VoidCallback onFullSync;

  const _SyncActions({
    required this.status,
    required this.onPush,
    required this.onPull,
    required this.onFullSync,
  });

  @override
  Widget build(BuildContext context) {
    final syncing = status == SyncStatus.syncing;
    return Card(
      color: const Color(0xFF16213E),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: syncing ? null : onFullSync,
                icon: const Icon(Icons.sync),
                label: const Text('Full Sync (Push + Pull)'),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: syncing ? null : onPush,
                    icon: const Icon(Icons.cloud_upload),
                    label: const Text('Push'),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white70),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: syncing ? null : onPull,
                    icon: const Icon(Icons.cloud_download),
                    label: const Text('Pull'),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white70),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final SyncProgress progress;

  const _ProgressBar({required this.progress});

  @override
  Widget build(BuildContext context) {
    final pct = progress.total > 0 ? progress.current / progress.total : 0.0;
    return Card(
      color: const Color(0xFF16213E),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              progress.message ?? 'Syncing...',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: pct, backgroundColor: const Color(0xFF1A1A2E)),
            const SizedBox(height: 4),
            Text(
              '${progress.current}/${progress.total}',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String error;

  const _ErrorCard({required this.error});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.redAccent.withValues(alpha: 0.15),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(error, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConflictList extends StatelessWidget {
  final List<SyncConflict> conflicts;
  final Future<void> Function(SyncConflict, String) onResolve;

  const _ConflictList({required this.conflicts, required this.onResolve});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF16213E),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Conflicts (${conflicts.length})',
              style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...conflicts.map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(c.name, style: const TextStyle(color: Colors.white70)),
                      ),
                      TextButton(
                        onPressed: () => onResolve(c, 'local'),
                        child: const Text('Keep Local', style: TextStyle(color: Colors.blueAccent)),
                      ),
                      TextButton(
                        onPressed: () => onResolve(c, 'cloud'),
                        child: const Text('Use Cloud', style: TextStyle(color: Colors.greenAccent)),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

class _AutoSyncToggle extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _AutoSyncToggle({required this.enabled, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF16213E),
      child: SwitchListTile(
        title: const Text('Auto-sync after messages', style: TextStyle(color: Colors.white70)),
        subtitle: const Text('Automatically push after every 5 messages',
            style: TextStyle(color: Colors.white38, fontSize: 12)),
        value: enabled,
        onChanged: onChanged,
        activeThumbColor: const Color(0xFF0F3460),
      ),
    );
  }
}
