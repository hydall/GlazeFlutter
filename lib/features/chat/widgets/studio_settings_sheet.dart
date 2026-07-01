import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/llm/sse_client.dart';
import '../../../core/llm/studio_controller_ontology.dart';
import '../../../core/models/pipeline_settings.dart';
import '../../../core/models/studio_config.dart';
import '../../../core/state/db_provider.dart';
import '../../../core/utils/time_helpers.dart';
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
/// - 3 model dropdowns (final/tracker/cleaner) fetched from the active API
///   provider and stored in PipelineSettings
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
  bool _loading = true;

  List<String> _fetchedModels = const [];
  bool _fetchingModels = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await ref.read(apiListProvider.future);
    final repo = ref.read(studioConfigRepoProvider);
    final config = await repo.getBySessionId(widget.sessionId);
    if (!mounted) return;
    setState(() {
      _config = config;
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
    final now = currentTimestampSeconds();
    final config = StudioConfig(
      sessionId: widget.sessionId,
      enabled: true,
      agents: StudioControllerOntology.buildDefaultAgents(
        sessionId: widget.sessionId,
        now: now,
      ),
      createdAt: now,
      updatedAt: now,
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
          Text('Models', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          _buildModelSelector(
            label: 'Final Generator',
            emptyLabel: 'Use active chat model',
            value: ref.watch(pipelineSettingsProvider).generationModel,
            onChanged: (model) => _savePipelineModel(
              (pipeline) => pipeline.copyWith(generationModel: model),
            ),
          ),
          const SizedBox(height: 8),
          _buildModelSelector(
            label: 'Trackers',
            emptyLabel: 'Use active chat model',
            value: ref
                .watch(pipelineSettingsProvider)
                .studioTrackerModelOverride,
            onChanged: (model) => _savePipelineModel(
              (pipeline) =>
                  pipeline.copyWith(studioTrackerModelOverride: model),
            ),
          ),
          const SizedBox(height: 8),
          _buildModelSelector(
            label: 'Cleaner (Post-Processing)',
            emptyLabel: 'Use tracker/chat model',
            value: ref.watch(pipelineSettingsProvider).postCleanerModel,
            onChanged: (model) => _savePipelineModel(
              (pipeline) => pipeline.copyWith(postCleanerModel: model),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.edit_note),
            title: const Text('Edit Preset Blocks'),
            subtitle: const Text('Trackers, Final Agent, Cleaner, Ledger'),
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

  Future<void> _savePipelineModel(
    PipelineSettings Function(PipelineSettings pipeline) mutate,
  ) async {
    final pipeline = ref.read(pipelineSettingsProvider);
    await ref.read(pipelineSettingsProvider.notifier).save(mutate(pipeline));
  }

  Widget _buildModelSelector({
    required String label,
    required String value,
    required String emptyLabel,
    required ValueChanged<String> onChanged,
  }) {
    final models = <String>{
      ..._fetchedModels,
      if (value.isNotEmpty) value,
    }.toList()..sort();

    return DropdownButtonFormField<String>(
      initialValue: models.contains(value) || value.isEmpty ? value : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        helperText: _fetchingModels
            ? 'Loading models...'
            : _fetchedModels.isEmpty
            ? 'Open this field to load models from the active API config'
            : '${_fetchedModels.length} models available',
        helperMaxLines: 2,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        DropdownMenuItem<String>(
          value: '',
          child: Text(emptyLabel, overflow: TextOverflow.ellipsis),
        ),
        ...models.map(
          (model) => DropdownMenuItem<String>(
            value: model,
            child: Text(model, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onTap: _fetchingModels ? null : () => unawaited(_fetchModels()),
      onChanged: (model) => onChanged(model ?? ''),
    );
  }

  Future<void> _fetchModels() async {
    if (_fetchingModels) return;
    final config = ref.read(activeApiConfigProvider);
    if (config == null) {
      GlazeToast.show(context, 'No API configs found.');
      return;
    }
    setState(() => _fetchingModels = true);
    try {
      final models = await SseClient().fetchModels(
        endpoint: config.endpoint,
        apiKey: config.apiKey,
      );
      final ids =
          models
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
      setState(() => _fetchedModels = ids);
    } catch (e) {
      if (mounted) {
        GlazeToast.show(context, 'Failed to fetch models: $e');
      }
    } finally {
      if (mounted) setState(() => _fetchingModels = false);
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
