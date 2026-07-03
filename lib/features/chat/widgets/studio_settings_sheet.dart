import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/api_config.dart';
import '../../../core/llm/sse_client.dart';
import '../../../core/llm/studio_controller_ontology.dart';
import '../../../core/models/pipeline_settings.dart';
import '../../../core/models/studio_config.dart';
import '../../../core/state/db_provider.dart';
import '../../../core/utils/time_helpers.dart';
import '../../../shared/widgets/menu_group.dart';
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

  final Map<String, List<String>> _fetchedModelsBySlot = {};
  final Set<String> _fetchingModelSlots = {};
  List<StudioPreset> _studioPresets = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await ref.read(apiListProvider.future);
    final repo = ref.read(studioConfigRepoProvider);
    final presetRepo = ref.read(studioPresetRepoProvider);
    final config = await repo.getBySessionId(widget.sessionId);
    final presets = await presetRepo.getAll();
    if (!mounted) return;
    setState(() {
      _config = config;
      _studioPresets = presets..sort((a, b) => a.name.compareTo(b.name));
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
          _buildPresetSelector(config),
          const Divider(),
          Text('Models', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          _buildModelSlot(
            slot: StudioSlot.finalGenerator,
            label: 'Final Generator',
            description: 'Expensive — high-quality prose generation',
            emptyLabel: 'Use active chat model',
            value: pipeline.studioFinalModelOverride,
            apiConfigId: config.expensiveApiConfigId,
            onChanged: (model) => _savePipelineModel(
              (p) => p.copyWith(studioFinalModelOverride: model),
            ),
            onApiConfigChanged: (apiConfigId) =>
                _save(config.copyWith(expensiveApiConfigId: apiConfigId)),
            onSettings: () =>
                _openSlotSettings(slot: StudioSlot.finalGenerator),
          ),
          const SizedBox(height: 12),
          _buildModelSlot(
            slot: StudioSlot.tracker,
            label: 'Trackers',
            description: 'Cheap — compact JSON briefs, fast',
            emptyLabel: 'Use active chat model',
            value: pipeline.studioTrackerModelOverride,
            apiConfigId: config.cheapApiConfigId,
            onChanged: (model) => _savePipelineModel(
              (p) => p.copyWith(studioTrackerModelOverride: model),
            ),
            onApiConfigChanged: (apiConfigId) =>
                _save(config.copyWith(cheapApiConfigId: apiConfigId)),
            onSettings: () => _openSlotSettings(slot: StudioSlot.tracker),
          ),
          const SizedBox(height: 12),
          _buildModelSlot(
            slot: StudioSlot.cleaner,
            label: 'Cleaner (Post-Processing)',
            description: 'Semi-expensive — prose rewrite + continuity audit',
            emptyLabel: 'Use tracker/chat model',
            value: pipeline.postCleanerModel,
            apiConfigId: config.cleanerApiConfigId,
            onChanged: (model) =>
                _savePipelineModel((p) => p.copyWith(postCleanerModel: model)),
            onApiConfigChanged: (apiConfigId) =>
                _save(config.copyWith(cleanerApiConfigId: apiConfigId)),
            onSettings: () => _openSlotSettings(slot: StudioSlot.cleaner),
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
          _buildPostTrackerContextSetting(pipeline),
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

  Widget _buildPresetSelector(StudioConfig config) {
    final current = _studioPresets
        .where((p) => p.id == config.studioPresetId)
        .firstOrNull;
    final label = current?.name.isNotEmpty == true
        ? current!.name
        : config.studioPresetId;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.view_module_outlined),
      title: const Text('Studio Preset'),
      subtitle: Text(
        label.isEmpty ? 'Default' : label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.arrow_drop_down),
      onTap: () => _openStudioPresetSelector(config),
    );
  }

  Future<void> _openStudioPresetSelector(StudioConfig config) async {
    final items = <BottomSheetItem>[
      BottomSheetItem(
        label: 'Create new preset',
        hint: 'Copy the current full block set',
        icon: Icons.add,
        iconColor: Theme.of(context).colorScheme.primary,
        onTap: () {
          Navigator.of(context, rootNavigator: true).pop();
          unawaited(_createStudioPreset(config));
        },
      ),
      ..._studioPresets.map((preset) {
        final active = preset.id == config.studioPresetId;
        final name = preset.name.isNotEmpty ? preset.name : preset.id;
        final sections =
            preset.blocks
                .where((b) => b.enabled)
                .map((b) => b.section)
                .toSet()
                .toList()
              ..sort();
        return BottomSheetItem(
          label: name,
          hint: sections.isEmpty ? preset.id : sections.join(', '),
          icon: active ? Icons.check : null,
          iconColor: Theme.of(context).colorScheme.primary,
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            _save(config.copyWith(studioPresetId: preset.id));
          },
        );
      }),
    ];
    await GlazeBottomSheet.show<void>(
      context,
      title: 'Studio Presets',
      items: items,
    );
  }

  Future<void> _createStudioPreset(StudioConfig config) async {
    final nameCtrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New Studio Preset'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Preset name',
            hintText: 'My Studio Preset',
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(nameCtrl.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    nameCtrl.dispose();
    final trimmedName = name?.trim() ?? '';
    if (!mounted || trimmedName.isEmpty) return;

    final source =
        _studioPresets
            .where((preset) => preset.id == config.studioPresetId)
            .firstOrNull ??
        _studioPresets.firstOrNull;
    if (source == null) {
      GlazeToast.show(context, 'No Studio preset to copy.');
      return;
    }

    final now = currentTimestampSeconds();
    final preset = StudioPreset(
      id: 'studio_$now',
      name: trimmedName,
      blocks: source.blocks,
      updatedAt: now,
    );
    await ref.read(studioPresetRepoProvider).upsert(preset);
    if (!mounted) return;
    final nextPresets = await ref.read(studioPresetRepoProvider).getAll();
    nextPresets.sort((a, b) => a.name.compareTo(b.name));
    setState(() => _studioPresets = nextPresets);
    await _save(config.copyWith(studioPresetId: preset.id));
  }

  Widget _buildPostTrackerContextSetting(PipelineSettings pipeline) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Post-Processing', style: tt.titleSmall),
        const SizedBox(height: 4),
        Text(
          'How many chat messages post-processing trackers receive '
          '(last turn + the response to edit).',
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final value in const [1, 2, 3, 5])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text('$value'),
                  selected: pipeline.studioPostTrackerContextSize == value,
                  onSelected: (_) => _savePipelineModel(
                    (p) => p.copyWith(studioPostTrackerContextSize: value),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildModelSlot({
    required StudioSlot slot,
    required String label,
    required String description,
    required String value,
    required String apiConfigId,
    required String emptyLabel,
    required ValueChanged<String> onChanged,
    required ValueChanged<String> onApiConfigChanged,
    required VoidCallback onSettings,
  }) {
    final apiConfigs = ref.watch(apiListProvider).value ?? const <ApiConfig>[];
    final apiConfig = _slotApiConfig(apiConfigId, apiConfigs);
    final modelCacheKey = _modelCacheKey(slot, apiConfigId, apiConfigs);
    final fetchedModels =
        _fetchedModelsBySlot[modelCacheKey] ?? const <String>[];
    final fetchingModels = _fetchingModelSlots.contains(modelCacheKey);
    final models = <String>{
      ...fetchedModels,
      if (value.isNotEmpty) value,
      if (apiConfig?.model.isNotEmpty == true) apiConfig!.model,
    }.toList()..sort();

    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final usesOtherApi = apiConfigId.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: tt.titleSmall)),
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
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('Другой API'),
          subtitle: Text(
            usesOtherApi
                ? _apiConfigLabel(apiConfigId, apiConfigs)
                : 'Use active chat API',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          value: usesOtherApi,
          onChanged: (checked) {
            if (checked == true) {
              _openApiConfigSelector(
                currentId: apiConfigId,
                onSelected: onApiConfigChanged,
              );
            } else {
              onApiConfigChanged('');
              setState(() => _clearSlotModelCache(slot));
            }
          },
        ),
        if (usesOtherApi)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _openApiConfigSelector(
                currentId: apiConfigId,
                onSelected: onApiConfigChanged,
              ),
              icon: const Icon(Icons.api, size: 16),
              label: const Text('Select API preset'),
            ),
          ),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          initialValue: models.contains(value) || value.isEmpty ? value : null,
          isExpanded: true,
          decoration: InputDecoration(
            helperText: fetchingModels
                ? 'Loading models...'
                : fetchedModels.isEmpty
                ? 'Open this field to load models from ${usesOtherApi ? 'the selected API config' : 'the active API config'}'
                : '${fetchedModels.length} models available',
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
          onTap: fetchingModels
              ? null
              : () => unawaited(_fetchModels(slot, apiConfigId)),
          onChanged: (model) => onChanged(model ?? ''),
        ),
      ],
    );
  }

  ApiConfig? _slotApiConfig(String apiConfigId, List<ApiConfig> apiConfigs) {
    if (apiConfigId.isNotEmpty) {
      final selected = apiConfigs.where((c) => c.id == apiConfigId).firstOrNull;
      if (selected != null) return selected;
    }
    return ref.read(activeApiConfigProvider);
  }

  String _modelCacheKey(
    StudioSlot slot,
    String apiConfigId,
    List<ApiConfig> apiConfigs,
  ) {
    final config = _slotApiConfig(apiConfigId, apiConfigs);
    final apiKey = config == null
        ? apiConfigId
        : '${config.id}|${config.endpoint}|${config.model}';
    return '${slot.name}:$apiKey';
  }

  void _clearSlotModelCache(StudioSlot slot) {
    final prefix = '${slot.name}:';
    _fetchedModelsBySlot.removeWhere((key, _) => key.startsWith(prefix));
    _fetchingModelSlots.removeWhere((key) => key.startsWith(prefix));
  }

  String _apiConfigLabel(String apiConfigId, List<ApiConfig> apiConfigs) {
    final config = apiConfigs.where((c) => c.id == apiConfigId).firstOrNull;
    if (config == null) return 'Missing API preset';
    if (config.name.isNotEmpty) return config.name;
    if (config.model.isNotEmpty) return config.model;
    return config.endpoint.isNotEmpty ? config.endpoint : config.id;
  }

  Future<void> _openApiConfigSelector({
    required String currentId,
    required ValueChanged<String> onSelected,
  }) async {
    final apiConfigs = ref.read(apiListProvider).value ?? const <ApiConfig>[];
    if (apiConfigs.isEmpty) {
      GlazeToast.show(context, 'No API configs found.');
      return;
    }
    await GlazeBottomSheet.show<void>(
      context,
      title: 'API Preset',
      items: apiConfigs.map((config) {
        final active = config.id == currentId;
        final label = config.name.isNotEmpty
            ? config.name
            : config.model.isNotEmpty
            ? config.model
            : config.id;
        return BottomSheetItem(
          label: label,
          hint: config.endpoint,
          icon: active ? Icons.check : null,
          iconColor: Theme.of(context).colorScheme.primary,
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            onSelected(config.id);
          },
        );
      }).toList(),
    );
  }

  Future<void> _fetchModels(StudioSlot slot, String apiConfigId) async {
    final apiConfigs = ref.read(apiListProvider).value ?? const <ApiConfig>[];
    final modelCacheKey = _modelCacheKey(slot, apiConfigId, apiConfigs);
    if (_fetchingModelSlots.contains(modelCacheKey)) return;
    final config = _slotApiConfig(apiConfigId, apiConfigs);
    if (config == null) {
      GlazeToast.show(context, 'No API configs found.');
      return;
    }
    setState(() => _fetchingModelSlots.add(modelCacheKey));
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
      setState(() => _fetchedModelsBySlot[modelCacheKey] = ids);
    } catch (e) {
      if (mounted) {
        GlazeToast.show(context, 'Failed to fetch models: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _fetchingModelSlots.remove(modelCacheKey));
      }
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
  final double topP;
  final int topK;
  final double frequencyPenalty;
  final double presencePenalty;
  final bool requestReasoning;
  final String reasoningEffort;
  final bool omitTemperature;
  final bool omitTopP;
  final bool omitReasoning;
  final bool omitReasoningEffort;
  final int maxTokens;
  final int timeoutMs;

  const StudioSlotSettings({
    required this.temperature,
    required this.topP,
    required this.topK,
    required this.frequencyPenalty,
    required this.presencePenalty,
    required this.requestReasoning,
    required this.reasoningEffort,
    required this.omitTemperature,
    required this.omitTopP,
    required this.omitReasoning,
    required this.omitReasoningEffort,
    required this.maxTokens,
    required this.timeoutMs,
  });

  PipelineSettings applyTo(PipelineSettings pipeline, StudioSlot slot) {
    switch (slot) {
      case StudioSlot.finalGenerator:
        return pipeline.copyWith(
          studioFinalTemperature: temperature,
          studioFinalTopP: topP,
          studioFinalTopK: topK,
          studioFinalFrequencyPenalty: frequencyPenalty,
          studioFinalPresencePenalty: presencePenalty,
          studioFinalRequestReasoning: requestReasoning,
          studioFinalReasoningEffort: reasoningEffort,
          studioFinalOmitTemperature: omitTemperature,
          studioFinalOmitTopP: omitTopP,
          studioFinalOmitReasoning: omitReasoning,
          studioFinalOmitReasoningEffort: omitReasoningEffort,
          studioFinalMaxTokens: maxTokens,
          studioFinalTimeoutMs: timeoutMs,
        );
      case StudioSlot.tracker:
        return pipeline.copyWith(
          studioTrackerTemperature: temperature,
          studioTrackerTopP: topP,
          studioTrackerTopK: topK,
          studioTrackerFrequencyPenalty: frequencyPenalty,
          studioTrackerPresencePenalty: presencePenalty,
          studioTrackerRequestReasoning: requestReasoning,
          studioTrackerReasoningEffort: reasoningEffort,
          studioTrackerOmitTemperature: omitTemperature,
          studioTrackerOmitTopP: omitTopP,
          studioTrackerOmitReasoning: omitReasoning,
          studioTrackerOmitReasoningEffort: omitReasoningEffort,
          studioTrackerMaxTokens: maxTokens,
          studioTrackerTimeoutMs: timeoutMs,
        );
      case StudioSlot.cleaner:
        return pipeline.copyWith(
          postCleanerTemperature: temperature,
          postCleanerTopP: topP,
          postCleanerTopK: topK,
          postCleanerFrequencyPenalty: frequencyPenalty,
          postCleanerPresencePenalty: presencePenalty,
          postCleanerRequestReasoning: requestReasoning,
          postCleanerReasoningEffort: reasoningEffort,
          postCleanerOmitTemperature: omitTemperature,
          postCleanerOmitTopP: omitTopP,
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

  const _StudioSlotSettingsDialog({required this.slot, required this.pipeline});

  @override
  State<_StudioSlotSettingsDialog> createState() =>
      _StudioSlotSettingsDialogState();
}

class _StudioSlotSettingsDialogState extends State<_StudioSlotSettingsDialog> {
  late double _temperature;
  late double _topP;
  late int _topK;
  late double _frequencyPenalty;
  late double _presencePenalty;
  late bool _requestReasoning;
  late String _reasoningEffort;
  late bool _omitTemperature;
  late bool _omitTopP;
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
        _topP = p.studioFinalTopP;
        _topK = p.studioFinalTopK;
        _frequencyPenalty = p.studioFinalFrequencyPenalty;
        _presencePenalty = p.studioFinalPresencePenalty;
        _requestReasoning = p.studioFinalRequestReasoning;
        _reasoningEffort = p.studioFinalReasoningEffort;
        _omitTemperature = p.studioFinalOmitTemperature;
        _omitTopP = p.studioFinalOmitTopP;
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
        _topP = p.studioTrackerTopP;
        _topK = p.studioTrackerTopK;
        _frequencyPenalty = p.studioTrackerFrequencyPenalty;
        _presencePenalty = p.studioTrackerPresencePenalty;
        _requestReasoning = p.studioTrackerRequestReasoning;
        _reasoningEffort = p.studioTrackerReasoningEffort;
        _omitTemperature = p.studioTrackerOmitTemperature;
        _omitTopP = p.studioTrackerOmitTopP;
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
        _topP = p.postCleanerTopP;
        _topK = p.postCleanerTopK;
        _frequencyPenalty = p.postCleanerFrequencyPenalty;
        _presencePenalty = p.postCleanerPresencePenalty;
        _requestReasoning = p.postCleanerRequestReasoning;
        _reasoningEffort = p.postCleanerReasoningEffort;
        _omitTemperature = p.postCleanerOmitTemperature;
        _omitTopP = p.postCleanerOmitTopP;
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

  String _reasoningEffortLabel(String effort) {
    return switch (effort) {
      'auto' => 'Auto',
      'min' => 'Min',
      'low' => 'Low',
      'medium' => 'Medium',
      'high' => 'High',
      'max' => 'Max',
      _ => effort,
    };
  }

  Future<void> _openReasoningEffortSelector() async {
    const options = ['auto', 'min', 'low', 'medium', 'high', 'max'];
    await GlazeBottomSheet.show<void>(
      context,
      title: 'Reasoning Effort',
      items: options.map((option) {
        final active = option == _reasoningEffort;
        return BottomSheetItem(
          label: _reasoningEffortLabel(option),
          icon: active ? Icons.check : null,
          iconColor: Theme.of(context).colorScheme.primary,
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            setState(() => _reasoningEffort = option);
          },
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('$_slotTitle Settings'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MenuGroup(
                compact: true,
                header: 'Параметры генерации',
                items: [
                  MenuRangeItem(
                    label: 'Temperature',
                    value: _temperature,
                    min: 0,
                    max: 2,
                    divisions: 200,
                    onChanged: (v) => setState(() => _temperature = v),
                  ),
                  MenuRangeItem(
                    label: 'Top P',
                    value: _topP,
                    min: 0,
                    max: 1,
                    divisions: 100,
                    onChanged: (v) => setState(() => _topP = v),
                  ),
                  MenuRangeItem(
                    label: 'Top K',
                    value: _topK.toDouble(),
                    min: 0,
                    max: 200,
                    divisions: 200,
                    onChanged: (v) => setState(() => _topK = v.round()),
                  ),
                  MenuRangeItem(
                    label: 'Частотный штраф',
                    value: _frequencyPenalty,
                    min: -2,
                    max: 2,
                    divisions: 80,
                    onChanged: (v) => setState(() => _frequencyPenalty = v),
                  ),
                  MenuRangeItem(
                    label: 'Штраф присутствия',
                    value: _presencePenalty,
                    min: -2,
                    max: 2,
                    divisions: 80,
                    onChanged: (v) => setState(() => _presencePenalty = v),
                  ),
                  MenuFieldItem(
                    label: _maxTokensLabel,
                    controller: _maxTokensCtrl,
                    placeholder: _maxTokensHint,
                    keyboardType: TextInputType.number,
                  ),
                  MenuFieldItem(
                    label: 'Timeout seconds (0 = default)',
                    controller: _timeoutCtrl,
                    placeholder: '0',
                    keyboardType: TextInputType.number,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              MenuGroup(
                compact: true,
                header: 'Мышление',
                items: [
                  MenuSwitchItem(
                    label: 'Запросить нативное мышление',
                    description: 'Показывает блок нативного мышления модели',
                    value: _requestReasoning,
                    onChanged: (v) => setState(() => _requestReasoning = v),
                  ),
                  MenuSelectorItem(
                    label: 'Уровень мышления',
                    currentValue: _reasoningEffortLabel(_reasoningEffort),
                    onTap: _openReasoningEffortSelector,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              MenuGroup(
                compact: true,
                header: 'Пропуск параметров',
                items: [
                  MenuSwitchItem(
                    label: 'Пропустить Temperature',
                    description: 'Не отправлять temperature в API',
                    value: _omitTemperature,
                    onChanged: (v) => setState(() => _omitTemperature = v),
                  ),
                  MenuSwitchItem(
                    label: 'Пропустить Top P',
                    description: 'Не отправлять top_p в API',
                    value: _omitTopP,
                    onChanged: (v) => setState(() => _omitTopP = v),
                  ),
                  MenuSwitchItem(
                    label: 'Пропустить Reasoning',
                    description: 'Не отправлять параметры reasoning в API',
                    value: _omitReasoning,
                    onChanged: (v) => setState(() => _omitReasoning = v),
                  ),
                  MenuSwitchItem(
                    label: 'Пропустить Reasoning Effort',
                    description: 'Не отправлять reasoning_effort в API',
                    value: _omitReasoningEffort,
                    onChanged: (v) => setState(() => _omitReasoningEffort = v),
                  ),
                ],
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
                topP: _topP,
                topK: _topK,
                frequencyPenalty: _frequencyPenalty,
                presencePenalty: _presencePenalty,
                requestReasoning: _requestReasoning,
                reasoningEffort: _reasoningEffort,
                omitTemperature: _omitTemperature,
                omitTopP: _omitTopP,
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
