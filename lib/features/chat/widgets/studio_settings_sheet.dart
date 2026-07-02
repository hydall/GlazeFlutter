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
    final pipeline = ref.watch(pipelineSettingsProvider);
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
          _buildModelSlot(
            label: 'Final Generator',
            description: 'Expensive — high-quality prose generation',
            emptyLabel: 'Use active chat model',
            value: pipeline.generationModel,
            onChanged: (model) => _savePipelineModel(
              (p) => p.copyWith(generationModel: model),
            ),
            onSettings: () => _openSlotSettings(
              slot: StudioSlot.finalGenerator,
            ),
          ),
          const SizedBox(height: 12),
          _buildModelSlot(
            label: 'Trackers',
            description: 'Cheap — compact JSON briefs, fast',
            emptyLabel: 'Use active chat model',
            value: pipeline.studioTrackerModelOverride,
            onChanged: (model) => _savePipelineModel(
              (p) => p.copyWith(studioTrackerModelOverride: model),
            ),
            onSettings: () => _openSlotSettings(
              slot: StudioSlot.tracker,
            ),
          ),
          const SizedBox(height: 12),
          _buildModelSlot(
            label: 'Cleaner (Post-Processing)',
            description: 'Semi-expensive — prose rewrite + continuity audit',
            emptyLabel: 'Use tracker/chat model',
            value: pipeline.postCleanerModel,
            onChanged: (model) => _savePipelineModel(
              (p) => p.copyWith(postCleanerModel: model),
            ),
            onSettings: () => _openSlotSettings(
              slot: StudioSlot.cleaner,
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

  Widget _buildModelSlot({
    required String label,
    required String description,
    required String value,
    required String emptyLabel,
    required ValueChanged<String> onChanged,
    required VoidCallback onSettings,
  }) {
    final models = <String>{
      ..._fetchedModels,
      if (value.isNotEmpty) value,
    }.toList()..sort();

    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: tt.titleSmall),
            ),
            IconButton(
              icon: const Icon(Icons.tune, size: 18),
              tooltip: 'Settings',
              onPressed: onSettings,
              style: IconButton.styleFrom(
                padding: const EdgeInsets.all(4),
                minimumSize: const Size(28, 28),
              ),
            ),
          ],
        ),
        Text(
          description,
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          initialValue: models.contains(value) || value.isEmpty ? value : null,
          isExpanded: true,
          decoration: InputDecoration(
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
        ),
      ],
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

  Future<void> _openSlotSettings({required StudioSlot slot}) async {
    final updated = await showDialog<StudioSlotSettings>(
      context: context,
      builder: (c) => _StudioSlotSettingsDialog(
        slot: slot,
        pipeline: ref.read(pipelineSettingsProvider),
      ),
    );
    if (!mounted || updated == null) return;
    final pipeline = ref.read(pipelineSettingsProvider);
    await ref
        .read(pipelineSettingsProvider.notifier)
        .save(updated.applyTo(pipeline, slot));
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

/// Which Studio model slot is being configured.
enum StudioSlot { finalGenerator, tracker, cleaner }

/// Snapshot of per-slot settings captured in the dialog.
class StudioSlotSettings {
  final double temperature;
  final bool requestReasoning;
  final bool omitReasoning;
  final bool omitReasoningEffort;
  final int maxTokens;
  final int timeoutMs;

  const StudioSlotSettings({
    required this.temperature,
    required this.requestReasoning,
    required this.omitReasoning,
    required this.omitReasoningEffort,
    required this.maxTokens,
    required this.timeoutMs,
  });

  PipelineSettings applyTo(
    PipelineSettings pipeline,
    StudioSlot slot,
  ) {
    switch (slot) {
      case StudioSlot.finalGenerator:
        return pipeline.copyWith(
          studioFinalTemperature: temperature,
          studioFinalRequestReasoning: requestReasoning,
          studioFinalOmitReasoning: omitReasoning,
          studioFinalOmitReasoningEffort: omitReasoningEffort,
          studioFinalMaxTokens: maxTokens,
          studioFinalTimeoutMs: timeoutMs,
        );
      case StudioSlot.tracker:
        return pipeline.copyWith(
          studioTrackerTemperature: temperature,
          studioTrackerRequestReasoning: requestReasoning,
          studioTrackerOmitReasoning: omitReasoning,
          studioTrackerOmitReasoningEffort: omitReasoningEffort,
          studioTrackerMaxTokens: maxTokens,
          studioTrackerTimeoutMs: timeoutMs,
        );
      case StudioSlot.cleaner:
        return pipeline.copyWith(
          postCleanerTemperature: temperature,
          postCleanerRequestReasoning: requestReasoning,
          postCleanerOmitReasoning: omitReasoning,
          postCleanerOmitReasoningEffort: omitReasoningEffort,
          postCleanerMaxTokens: maxTokens,
          postCleanerTimeoutMs: timeoutMs,
        );
    }
  }
}

class _StudioSlotSettingsDialog extends StatefulWidget {
  final StudioSlot slot;
  final PipelineSettings pipeline;

  const _StudioSlotSettingsDialog({
    required this.slot,
    required this.pipeline,
  });

  @override
  State<_StudioSlotSettingsDialog> createState() =>
      _StudioSlotSettingsDialogState();
}

class _StudioSlotSettingsDialogState extends State<_StudioSlotSettingsDialog> {
  late double _temperature;
  late bool _requestReasoning;
  late bool _omitReasoning;
  late bool _omitReasoningEffort;
  late TextEditingController _maxTokensCtrl;
  late TextEditingController _timeoutCtrl;

  @override
  void initState() {
    super.initState();
    final p = widget.pipeline;
    switch (widget.slot) {
      case StudioSlot.finalGenerator:
        _temperature = p.studioFinalTemperature;
        _requestReasoning = p.studioFinalRequestReasoning;
        _omitReasoning = p.studioFinalOmitReasoning;
        _omitReasoningEffort = p.studioFinalOmitReasoningEffort;
        _maxTokensCtrl = TextEditingController(
          text: p.studioFinalMaxTokens > 0 ? '${p.studioFinalMaxTokens}' : '',
        );
        _timeoutCtrl = TextEditingController(
          text: p.studioFinalTimeoutMs > 0
              ? '${p.studioFinalTimeoutMs ~/ 1000}'
              : '',
        );
      case StudioSlot.tracker:
        _temperature = p.studioTrackerTemperature;
        _requestReasoning = p.studioTrackerRequestReasoning;
        _omitReasoning = p.studioTrackerOmitReasoning;
        _omitReasoningEffort = p.studioTrackerOmitReasoningEffort;
        _maxTokensCtrl = TextEditingController(
          text: p.studioTrackerMaxTokens > 0
              ? '${p.studioTrackerMaxTokens}'
              : '',
        );
        _timeoutCtrl = TextEditingController(
          text: p.studioTrackerTimeoutMs > 0
              ? '${p.studioTrackerTimeoutMs ~/ 1000}'
              : '',
        );
      case StudioSlot.cleaner:
        _temperature = p.postCleanerTemperature;
        _requestReasoning = p.postCleanerRequestReasoning;
        _omitReasoning = p.postCleanerOmitReasoning;
        _omitReasoningEffort = p.postCleanerOmitReasoningEffort;
        _maxTokensCtrl = TextEditingController(
          text: p.postCleanerMaxTokens > 0 ? '${p.postCleanerMaxTokens}' : '',
        );
        _timeoutCtrl = TextEditingController(
          text: p.postCleanerTimeoutMs > 0
              ? '${p.postCleanerTimeoutMs ~/ 1000}'
              : '',
        );
    }
  }

  @override
  void dispose() {
    _maxTokensCtrl.dispose();
    _timeoutCtrl.dispose();
    super.dispose();
  }

  String get _slotTitle {
    switch (widget.slot) {
      case StudioSlot.finalGenerator:
        return 'Final Generator';
      case StudioSlot.tracker:
        return 'Trackers';
      case StudioSlot.cleaner:
        return 'Cleaner';
    }
  }

  String get _maxTokensLabel {
    switch (widget.slot) {
      case StudioSlot.finalGenerator:
        return 'Max response length (0 = default)';
      case StudioSlot.tracker:
        return 'Max response length (0 = default)';
      case StudioSlot.cleaner:
        return 'Max response length (0 = default)';
    }
  }

  String get _maxTokensHint {
    switch (widget.slot) {
      case StudioSlot.finalGenerator:
        return '8000';
      case StudioSlot.tracker:
        return '1600';
      case StudioSlot.cleaner:
        return '0';
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text('$_slotTitle Settings'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Temperature', style: tt.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  )),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: _temperature,
                      min: 0,
                      max: 2,
                      divisions: 200,
                      label: _temperature.toStringAsFixed(1),
                      onChanged: (v) => setState(() => _temperature = v),
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text(
                      _temperature.toStringAsFixed(1),
                      style: tt.bodySmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Request Reasoning', style: tt.bodySmall),
                value: _requestReasoning,
                onChanged: (v) => setState(() => _requestReasoning = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Omit Reasoning', style: tt.bodySmall),
                value: _omitReasoning,
                onChanged: (v) => setState(() => _omitReasoning = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Omit Reasoning Effort', style: tt.bodySmall),
                value: _omitReasoningEffort,
                onChanged: (v) => setState(() => _omitReasoningEffort = v),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _maxTokensCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: _maxTokensLabel,
                  hintText: _maxTokensHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _timeoutCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Timeout (seconds, 0 = default)',
                  hintText: '0',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final maxTokens = int.tryParse(_maxTokensCtrl.text.trim()) ?? 0;
            final seconds = int.tryParse(_timeoutCtrl.text.trim()) ?? 0;
            final timeoutMs = seconds > 0 ? seconds * 1000 : 0;
            Navigator.of(context).pop(
              StudioSlotSettings(
                temperature: _temperature,
                requestReasoning: _requestReasoning,
                omitReasoning: _omitReasoning,
                omitReasoningEffort: _omitReasoningEffort,
                maxTokens: maxTokens,
                timeoutMs: timeoutMs,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
