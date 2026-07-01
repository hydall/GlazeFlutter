import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/llm/sse_client.dart';
import '../../../core/models/api_config.dart';
import '../../../core/models/studio_config.dart';
import '../../../core/state/db_provider.dart';
import '../../../shared/widgets/glaze_bottom_sheet.dart';
import '../../../shared/widgets/glaze_toast.dart';
import '../../settings/api_list_provider.dart';
import '../state/recovery_state_provider.dart';
import '../services/tracker_memory_recovery_service.dart';
import 'studio_preset_editor_sheet.dart';

/// Studio Settings as a bottom sheet — replaces the full-screen
/// [StudioSettingsScreen]. Single scrollable page.
///
/// Contents:
/// - Studio enable/disable toggle
/// - 3 API config dropdowns (expensive/cheap/cleaner) with model dropdowns
///   that fetch /v1/models from the selected provider on refresh
/// - Edit Preset Blocks button → opens [StudioPresetEditorSheet]
/// - Recovery button (re-run tracker/memory cycles)
class StudioSettingsSheet extends ConsumerStatefulWidget {
  final String charId;
  final String sessionId;

  const StudioSettingsSheet({
    super.key,
    required this.charId,
    required this.sessionId,
  });

  /// Convenience launcher.
  static Future<void> show(
    BuildContext context, {
    required String charId,
    required String sessionId,
  }) {
    return GlazeBottomSheet.show<void>(
      context,
      title: 'Studio',
      child: StudioSettingsSheet(charId: charId, sessionId: sessionId),
    );
  }

  @override
  ConsumerState<StudioSettingsSheet> createState() =>
      _StudioSettingsSheetState();
}

class _StudioSettingsSheetState extends ConsumerState<StudioSettingsSheet> {
  StudioConfig? _config;
  List<ApiConfig> _apiConfigs = const [];
  bool _loading = true;

  // Fetched models per API config id.
  final Map<String, List<String>> _modelsByApiConfigId = {};
  final Set<String> _fetchingModelConfigIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await ref.read(apiListProvider.future);
    final repo = ref.read(studioConfigRepoProvider);
    final config = await repo.getBySessionId(widget.sessionId);
    final apiConfigs =
        ref.read(apiListProvider).value ?? const <ApiConfig>[];
    if (!mounted) return;
    setState(() {
      _config = config;
      _apiConfigs = apiConfigs;
      _loading = false;
    });
  }

  Future<void> _save(StudioConfig config) async {
    final repo = ref.read(studioConfigRepoProvider);
    await repo.upsert(config);
    setState(() => _config = config);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_config == null) {
      return _buildNoConfig();
    }
    return _buildBody();
  }

  Widget _buildNoConfig() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('No Studio configuration for this session.'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _createDefaultConfig,
            icon: const Icon(Icons.auto_mode),
            label: const Text('Enable Studio'),
          ),
        ],
      ),
    );
  }

  Future<void> _createDefaultConfig() async {
    final config = StudioConfig(
      sessionId: widget.sessionId,
      enabled: true,
    );
    await _save(config);
  }

  Widget _buildBody() {
    final config = _config!;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Studio Enabled'),
            value: config.enabled,
            onChanged: (v) => _save(config.copyWith(enabled: v)),
          ),
          const Divider(),
          Text('API Configuration',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          _buildApiConfigDropdown(
            label: 'Expensive (Final Generator)',
            value: config.expensiveApiConfigId,
            onChanged: (v) =>
                _save(config.copyWith(expensiveApiConfigId: v)),
          ),
          const SizedBox(height: 8),
          _buildApiConfigDropdown(
            label: 'Cheap (Trackers)',
            value: config.cheapApiConfigId,
            onChanged: (v) => _save(config.copyWith(cheapApiConfigId: v)),
          ),
          const SizedBox(height: 8),
          _buildApiConfigDropdown(
            label: 'Cleaner (Post-Processing)',
            value: config.cleanerApiConfigId,
            onChanged: (v) => _save(config.copyWith(cleanerApiConfigId: v)),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.edit_note),
            title: const Text('Edit Preset Blocks'),
            subtitle: const Text(
              'Trackers, Final Agent, Cleaner, Ledger',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final presetId = config.studioPresetId;
              await GlazeBottomSheet.show<void>(
                context,
                title: 'Preset Blocks',
                child: StudioPresetEditorSheet(presetId: presetId),
              );
            },
          ),
          const Divider(),
          _buildRecoverySection(),
        ],
      ),
    );
  }

  Widget _buildApiConfigDropdown({
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue:
              value.isNotEmpty && _apiConfigs.any((c) => c.id == value)
                  ? value
                  : '',
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            const DropdownMenuItem<String>(
              value: '',
              child: Text('Use active chat API'),
            ),
            ..._apiConfigs.map(
              (c) => DropdownMenuItem<String>(
                value: c.id,
                child: Text(
                  c.name.isNotEmpty ? c.name : c.id,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
          onChanged: (v) => onChanged(v ?? ''),
        ),
        if (value.isNotEmpty && _apiConfigs.any((c) => c.id == value)) ...[
          const SizedBox(height: 8),
          _buildModelDropdown(apiConfigId: value, label: 'Model'),
        ],
      ],
    );
  }

  Widget _buildModelDropdown({
    required String apiConfigId,
    required String label,
  }) {
    final config = _apiConfigs.where((c) => c.id == apiConfigId).firstOrNull;
    if (config == null) return const SizedBox.shrink();

    final fetched = _modelsByApiConfigId[apiConfigId] ?? const <String>[];
    final isFetching = _fetchingModelConfigIds.contains(apiConfigId);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: fetched.isNotEmpty ? config.model : null,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: label,
              helperText: fetched.isEmpty
                  ? 'Tap refresh to load models'
                  : '${fetched.length} models available',
              helperMaxLines: 2,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            items: fetched
                .map(
                  (m) => DropdownMenuItem<String>(
                    value: m,
                    child: Text(m, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: (m) {
              if (m == null) return;
            },
          ),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: IconButton.filledTonal(
            tooltip: 'Fetch models',
            onPressed: isFetching ? null : () => _fetchModels(config),
            icon: isFetching
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh, size: 18),
          ),
        ),
      ],
    );
  }

  Future<void> _fetchModels(ApiConfig config) async {
    if (_fetchingModelConfigIds.contains(config.id)) return;
    setState(() => _fetchingModelConfigIds.add(config.id));
    try {
      final models = await SseClient().fetchModels(
        endpoint: config.endpoint,
        apiKey: config.apiKey,
      );
      final ids = models
          .map((m) => m['id'])
          .whereType<String>()
          .where((id) => id.trim().isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      if (config.model.isNotEmpty && !ids.contains(config.model)) {
        ids.insert(0, config.model);
      }
      if (!mounted) return;
      setState(() => _modelsByApiConfigId[config.id] = ids);
    } catch (e) {
      if (mounted) {
        GlazeToast.show(context, 'Failed to fetch models: $e');
      }
    } finally {
      if (mounted) setState(() => _fetchingModelConfigIds.remove(config.id));
    }
  }

  Widget _buildRecoverySection() {
    final state = ref.watch(recoveryStateProvider);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isRunning = state.isActive;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Recovery', style: tt.titleSmall),
        const SizedBox(height: 4),
        Text(
          'Re-runs Studio tracker cycle + memory write-loop for all assistant '
          'messages in this session.',
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        if (isRunning) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  state.totalMessages > 0
                      ? 'Processing message ${state.processedMessages} of ${state.totalMessages}'
                      : 'Starting...',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: state.totalMessages > 0
                  ? state.processedMessages / state.totalMessages
                  : null,
              minHeight: 6,
              backgroundColor: cs.surfaceContainerHighest,
              color: cs.primary,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () =>
                  ref.read(trackerMemoryRecoveryServiceProvider).cancel(),
              icon: const Icon(Icons.stop_circle_outlined, size: 16),
              label: const Text('Cancel'),
              style: TextButton.styleFrom(foregroundColor: cs.error),
            ),
          ),
        ] else if (state.isDone) ...[
          Row(
            children: [
              Icon(Icons.check_circle_outline, size: 16, color: cs.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Done: ${state.trackersWritten} trackers, '
                  '${state.memoriesWritten} memories, '
                  '${state.failedMessages} failed',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: () => _startRecovery(),
            icon: const Icon(Icons.restore, size: 16),
            label: const Text('Run Recovery'),
          ),
        ] else ...[
          FilledButton.tonalIcon(
            onPressed: () => _startRecovery(),
            icon: const Icon(Icons.restore, size: 16),
            label: const Text('Run Recovery'),
          ),
        ],
      ],
    );
  }

  Future<void> _startRecovery() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Recovery'),
        content: const Text(
          'This will re-run the Studio tracker cycle and memory write-loop '
          'for every assistant message in this session. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Run Recovery'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    unawaited(
      ref
          .read(trackerMemoryRecoveryServiceProvider)
          .recover(sessionId: widget.sessionId, charId: widget.charId),
    );
  }
}
