import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/api_config.dart';
import '../../../core/llm/model_fetcher.dart';
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
import 'studio_slot_settings_dialog.dart';

/// Studio Settings as a bottom sheet. Single scrollable page.
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
            value: pipeline.studioAgent.studioFinalModelOverride,
            apiConfigId: config.expensiveApiConfigId,
            onChanged: (model) => _savePipelineModel(
              (p) => p.copyWith(
                studioAgent: p.studioAgent.copyWith(
                  studioFinalModelOverride: model,
                ),
              ),
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
            value: pipeline.studioAgent.studioTrackerModelOverride,
            apiConfigId: config.cheapApiConfigId,
            onChanged: (model) => _savePipelineModel(
              (p) => p.copyWith(
                studioAgent: p.studioAgent.copyWith(
                  studioTrackerModelOverride: model,
                ),
              ),
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
            value: pipeline.cleaner.postCleanerModel,
            apiConfigId: config.cleanerApiConfigId,
            onChanged: (model) =>
                _savePipelineModel(
                  (p) => p.copyWith(
                    cleaner: p.cleaner.copyWith(postCleanerModel: model),
                  ),
                ),
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
                  selected: pipeline.studioAgent.studioPostTrackerContextSize == value,
                  onSelected: (_) => _savePipelineModel(
                    (p) => p.copyWith(
                    studioAgent: p.studioAgent.copyWith(
                      studioPostTrackerContextSize: value,
                    ),
                  ),
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
      final ids = await ModelFetcher.fetchModelIds(
        endpoint: config.endpoint,
        apiKey: config.apiKey,
        fallbackModel: config.model,
      );
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
      builder: (c) => StudioSlotSettingsDialog(
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


