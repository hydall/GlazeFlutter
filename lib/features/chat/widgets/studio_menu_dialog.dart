import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/llm/studio_decomposition_service.dart';
import '../../../core/llm/transport/transport_factory.dart';
import '../../../core/models/api_config.dart';
import '../../../core/models/preset.dart';
import '../../../core/models/studio_config.dart';
import '../../../core/state/active_selection_provider.dart';
import '../../../core/state/db_provider.dart';
import '../../../core/state/memory_agent_providers.dart';
import '../../../core/utils/time_helpers.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/glaze_error_dialog.dart';
import '../../settings/api_list_provider.dart';
import '../chat_provider.dart';

/// Studio Mode menu dialog. Session-bound.
///
/// Flow:
/// 1. User opens from MagicDrawer "Studio" item.
/// 2. If no config exists → shows "Build Studio" button.
/// 3. User clicks "Build Studio" → LLM decomposes the active preset into agents.
/// 4. Menu shows: agent list with editable prompts + per-agent model config.
/// 5. Toggle to enable/disable Studio for this session.
class StudioMenuDialog extends ConsumerStatefulWidget {
  final String charId;
  final String sessionId;

  const StudioMenuDialog({
    super.key,
    required this.charId,
    required this.sessionId,
  });

  @override
  ConsumerState<StudioMenuDialog> createState() => _StudioMenuDialogState();
}

class _StudioMenuDialogState extends ConsumerState<StudioMenuDialog> {
  StudioConfig? _config;
  _StudioContextInfo _contextInfo = const _StudioContextInfo();
  String? _selectedPresetId;
  String? _selectedFinalPresetId;
  String? _selectedBuildApiConfigId;
  String? _selectedRunApiConfigId;
  bool _loading = true;
  bool _building = false;
  final Map<String, List<String>> _modelsByApiConfigId = {};
  final Set<String> _fetchingModelConfigIds = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      final config = await ref
          .read(studioConfigRepoProvider)
          .getBySessionId(widget.sessionId);
      final contextInfo = await _loadContextInfo(config: config);
      if (mounted) {
        setState(() {
          _config = config;
          _contextInfo = contextInfo;
          _selectedPresetId = contextInfo.preset?.id;
          _selectedFinalPresetId = contextInfo.finalPreset?.id;
          _selectedBuildApiConfigId = contextInfo.buildApiConfig?.id;
          _selectedRunApiConfigId = contextInfo.runApiConfig?.id;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _buildStudio() async {
    setState(() {
      _building = true;
      _error = null;
    });

    try {
      final contextInfo = await _loadContextInfo(config: _config);
      final preset = contextInfo.preset;
      if (preset == null) {
        throw Exception(
          'No preset available. Create or select a preset first.',
        );
      }
      final buildApiConfig = contextInfo.buildApiConfig;
      if (buildApiConfig == null) {
        throw Exception('No model selected for Studio build.');
      }

      final decompositionService = ref.read(studioDecompositionServiceProvider);
      final agents = await decompositionService.decompose(
        preset: preset,
        sessionId: widget.sessionId,
        apiConfig: buildApiConfig,
      );

      if (agents.isEmpty) {
        throw Exception('Decomposition returned no agents');
      }

      final now = currentTimestampSeconds();
      final newConfig = StudioConfig(
        sessionId: widget.sessionId,
        enabled: true,
        agents: agents,
        sourcePresetId: preset.id,
        finalPresetId: contextInfo.finalPreset?.id ?? preset.id,
        sourcePresetHash: StudioDecompositionService.computePresetHash(
          preset.blocks.where((b) => b.enabled).toList(),
        ),
        buildApiConfigId: buildApiConfig.id,
        runApiConfigId: contextInfo.runApiConfig?.id ?? '',
        createdAt: now,
        updatedAt: now,
      );

      await ref.read(studioConfigRepoProvider).upsert(newConfig);

      if (mounted) {
        setState(() {
          _config = newConfig;
          _contextInfo = contextInfo;
          _building = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _building = false;
        });
      }
    }
  }

  Future<_StudioContextInfo> _loadContextInfo({StudioConfig? config}) async {
    final chatState = ref.read(chatProvider(widget.charId)).value;
    final session = chatState?.session;
    final charId = session?.characterId ?? widget.charId;

    final presetRepo = ref.read(presetRepoProvider);
    final presets = await presetRepo.getAll();
    final effectivePreset = getEffectivePreset(
      presets,
      charId,
      session?.id ?? widget.sessionId,
      ref.read(activePresetIdProvider),
      ref.read(presetConnectionsProvider),
    );

    final selectedPresetId =
        _selectedPresetId ??
        (config?.sourcePresetId.isNotEmpty == true
            ? config!.sourcePresetId
            : null) ??
        effectivePreset?.id;
    final preset =
        presets.where((p) => p.id == selectedPresetId).firstOrNull ??
        effectivePreset;
    final selectedFinalPresetId =
        _selectedFinalPresetId ??
        (config?.finalPresetId.isNotEmpty == true
            ? config!.finalPresetId
            : null) ??
        selectedPresetId;
    final finalPreset =
        presets.where((p) => p.id == selectedFinalPresetId).firstOrNull ??
        preset;

    final apiConfigs = await ref.read(apiListProvider.future);
    final activeApi = ref.read(activeApiConfigProvider);
    final selectedBuildId =
        _selectedBuildApiConfigId ??
        (config?.buildApiConfigId.isNotEmpty == true
            ? config!.buildApiConfigId
            : null) ??
        activeApi?.id;
    final selectedRunId =
        _selectedRunApiConfigId ??
        (config?.runApiConfigId.isNotEmpty == true
            ? config!.runApiConfigId
            : null) ??
        activeApi?.id;
    final buildApiConfig =
        apiConfigs
            .where((c) => c.id == selectedBuildId && c.mode != 'embedding')
            .firstOrNull ??
        activeApi;
    final runApiConfig =
        apiConfigs
            .where((c) => c.id == selectedRunId && c.mode != 'embedding')
            .firstOrNull ??
        activeApi;

    return _StudioContextInfo(
      presets: presets,
      apiConfigs: apiConfigs.where((c) => c.mode != 'embedding').toList(),
      preset: preset,
      finalPreset: finalPreset,
      presetLabel: preset?.name ?? 'No preset available',
      buildApiConfig: buildApiConfig,
      runApiConfig: runApiConfig,
      buildModelLabel: _apiLabel(buildApiConfig),
      runModelLabel: _apiLabel(runApiConfig),
    );
  }

  String _apiLabel(ApiConfig? config) {
    if (config == null) return 'No chat model selected';
    final name = config.name.isNotEmpty ? config.name : config.model;
    return config.model.isNotEmpty ? '$name (${config.model})' : name;
  }

  Future<void> _refreshContextInfo({bool persistSelection = false}) async {
    final contextInfo = await _loadContextInfo(config: _config);
    if (!mounted) return;
    setState(() => _contextInfo = contextInfo);
    if (persistSelection && _config != null) {
      final updated = _config!.copyWith(
        sourcePresetId: contextInfo.preset?.id ?? '',
        buildApiConfigId: contextInfo.buildApiConfig?.id ?? '',
        runApiConfigId: contextInfo.runApiConfig?.id ?? '',
        finalPresetId: contextInfo.finalPreset?.id ?? '',
        updatedAt: currentTimestampSeconds(),
      );
      await ref.read(studioConfigRepoProvider).upsert(updated);
      if (mounted) setState(() => _config = updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 650,
        height: 600,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildBody(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(Icons.movie_filter_outlined, color: context.cs.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'menu_studio'.tr(),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (_config != null)
            Switch(
              value: _config!.enabled,
              onChanged: (v) async {
                final updated = _config!.copyWith(enabled: v);
                await ref.read(studioConfigRepoProvider).upsert(updated);
                setState(() => _config = updated);
              },
            ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => setState(() => _error = null),
                child: const Text('OK'),
              ),
            ],
          ),
        ),
      );
    }

    if (_config == null || _config!.agents.isEmpty) {
      return _buildEmptyState();
    }

    return _buildAgentList();
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildContextInfoCard(),
            const SizedBox(height: 24),
            Icon(
              Icons.movie_filter_outlined,
              size: 64,
              color: context.cs.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            Text(
              'Studio Mode decomposes your preset into agent tasks.\n'
              'Each agent gets its own instructions and model config.\n'
              'Agents collaborate to produce the final RP response.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.cs.onSurfaceVariant,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _building ? null : _buildStudio,
              icon: _building
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome),
              label: Text(_building ? 'Building...' : 'Build Studio'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAgentList() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: _buildContextInfoCard(),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(
                '${_config!.agents.length} agents',
                style: TextStyle(
                  color: context.cs.onSurfaceVariant,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: _building ? null : _buildStudio,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Rebuild'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            itemCount: _config!.agents.length,
            onReorderItem: (oldIndex, newIndex) {
              final agents = List<StudioAgent>.from(_config!.agents);
              final item = agents.removeAt(oldIndex);
              agents.insert(newIndex, item);
              for (var i = 0; i < agents.length; i++) {
                agents[i] = agents[i].copyWith(order: i);
              }
              final updated = _config!.copyWith(agents: agents);
              ref.read(studioConfigRepoProvider).upsert(updated);
              setState(() => _config = updated);
            },
            itemBuilder: (context, index) {
              final agent = _config!.agents[index];
              return _buildAgentTile(agent, index);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildContextInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: context.cs.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _presetSelector(),
          const SizedBox(height: 8),
          _finalPresetSelector(),
          const SizedBox(height: 8),
          _apiSelector(
            label: 'Build model',
            value: _selectedBuildApiConfigId,
            fallback: _contextInfo.buildModelLabel,
            onChanged: (value) async {
              setState(() => _selectedBuildApiConfigId = value);
              await _refreshContextInfo();
            },
          ),
          const SizedBox(height: 8),
          _apiSelector(
            label: 'Run model',
            value: _selectedRunApiConfigId,
            fallback: _contextInfo.runModelLabel,
            onChanged: (value) async {
              setState(() => _selectedRunApiConfigId = value);
              await _refreshContextInfo(persistSelection: true);
            },
          ),
        ],
      ),
    );
  }

  Widget _presetSelector() {
    final effectiveValue =
        _contextInfo.presets.any((preset) => preset.id == _selectedPresetId)
        ? _selectedPresetId
        : null;
    return DropdownButtonFormField<String>(
      initialValue: effectiveValue,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Agent preset',
        isDense: true,
        border: OutlineInputBorder(),
      ),
      items: _contextInfo.presets
          .map(
            (preset) =>
                DropdownMenuItem(value: preset.id, child: Text(preset.name)),
          )
          .toList(),
      hint: Text(_contextInfo.presetLabel),
      onChanged: (value) async {
        setState(() => _selectedPresetId = value);
        await _refreshContextInfo(persistSelection: true);
      },
    );
  }

  Widget _finalPresetSelector() {
    final effectiveValue =
        _contextInfo.presets.any(
          (preset) => preset.id == _selectedFinalPresetId,
        )
        ? _selectedFinalPresetId
        : null;
    return DropdownButtonFormField<String>(
      initialValue: effectiveValue,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Final preset',
        isDense: true,
        border: OutlineInputBorder(),
      ),
      items: _contextInfo.presets
          .map(
            (preset) =>
                DropdownMenuItem(value: preset.id, child: Text(preset.name)),
          )
          .toList(),
      hint: Text(_contextInfo.finalPreset?.name ?? _contextInfo.presetLabel),
      onChanged: (value) async {
        setState(() => _selectedFinalPresetId = value);
        await _refreshContextInfo(persistSelection: true);
      },
    );
  }

  Widget _apiSelector({
    required String label,
    required String? value,
    required String fallback,
    required Future<void> Function(String?) onChanged,
  }) {
    final effectiveValue = _contextInfo.apiConfigs.any((c) => c.id == value)
        ? value
        : null;
    return DropdownButtonFormField<String>(
      initialValue: effectiveValue,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      items: _contextInfo.apiConfigs
          .map(
            (config) => DropdownMenuItem(
              value: config.id,
              child: Text(_apiLabel(config)),
            ),
          )
          .toList(),
      hint: Text(fallback),
      onChanged: (value) {
        onChanged(value);
      },
    );
  }

  Widget _modelHint(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: context.cs.onSurfaceVariant),
      ),
    );
  }

  Widget _customApiSelector(StudioAgent agent) {
    return DropdownButtonFormField<String>(
      initialValue: _contextInfo.apiConfigs.any((c) => c.id == agent.model)
          ? agent.model
          : null,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'API config',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: _contextInfo.apiConfigs
          .map(
            (config) => DropdownMenuItem(
              value: config.id,
              child: Text(_apiLabel(config)),
            ),
          )
          .toList(),
      onChanged: (id) {
        final config = _contextInfo.apiConfigs
            .where((c) => c.id == id)
            .firstOrNull;
        if (config == null) return;
        _updateAgent(
          agent.copyWith(
            model: config.id,
            modelOverride: '',
            endpoint: config.endpoint,
          ),
        );
      },
    );
  }

  ApiConfig? _agentApiConfig(StudioAgent agent) {
    if (agent.modelSource == 'custom') {
      return _contextInfo.apiConfigs
          .where((c) => c.id == agent.model)
          .firstOrNull;
    }
    return _contextInfo.runApiConfig;
  }

  String _agentApiConfigLabel(StudioAgent agent) {
    final config = _agentApiConfig(agent);
    if (config != null) {
      final label = _apiLabel(config);
      return agent.modelOverride.isNotEmpty
          ? '$label -> ${agent.modelOverride}'
          : label;
    }
    if (agent.modelSource == 'custom') return 'custom not set';
    return _contextInfo.runModelLabel;
  }

  Future<void> _fetchProviderModels(ApiConfig config) async {
    setState(() => _fetchingModelConfigIds.add(config.id));
    try {
      final models = await pickChatTransport(
        config.protocol,
      ).fetchModels(endpoint: config.endpoint, apiKey: config.apiKey);
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
      setState(() => _modelsByApiConfigId[config.id] = ids);
    } catch (e) {
      if (mounted) GlazeErrorDialog.show(context, e, prefix: 'Fetch models');
    } finally {
      if (mounted) setState(() => _fetchingModelConfigIds.remove(config.id));
    }
  }

  Widget _providerModelSelector(StudioAgent agent) {
    final config = _agentApiConfig(agent);
    if (config == null) return const SizedBox.shrink();
    final fetched = _modelsByApiConfigId[config.id] ?? const <String>[];
    final models = <String>[
      if (config.model.isNotEmpty) config.model,
      ...fetched,
      if (agent.modelOverride.isNotEmpty) agent.modelOverride,
    ].where((m) => m.trim().isNotEmpty).toSet().toList()..sort();
    final selectedModel = agent.modelOverride.isNotEmpty
        ? agent.modelOverride
        : config.model.isNotEmpty
        ? config.model
        : null;
    final isFetching = _fetchingModelConfigIds.contains(config.id);

    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue:
                selectedModel != null && models.contains(selectedModel)
                ? selectedModel
                : null,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Provider model',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: models
                .map(
                  (model) => DropdownMenuItem(
                    value: model,
                    child: Text(model, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            hint: Text(config.model.isNotEmpty ? config.model : 'Fetch models'),
            onChanged: (model) {
              _updateAgent(
                agent.copyWith(
                  modelOverride: model == config.model ? '' : model ?? '',
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Fetch models',
          onPressed: isFetching ? null : () => _fetchProviderModels(config),
          icon: isFetching
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh, size: 18),
        ),
      ],
    );
  }

  Widget _buildAgentTile(StudioAgent agent, int index) {
    final isLast = index == _config!.agents.length - 1;
    return Card(
      key: ValueKey(agent.id),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ExpansionTile(
        title: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(Icons.drag_handle, size: 20),
              ),
            ),
            Icon(
              isLast
                  ? Icons.edit_outlined
                  : index == 0
                  ? Icons.psychology_outlined
                  : Icons.tune_outlined,
              size: 20,
              color: context.cs.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                agent.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (isLast)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: context.cs.primaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'FINAL',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: context.cs.onPrimaryContainer,
                  ),
                ),
              ),
            Switch(
              value: agent.enabled,
              onChanged: (v) => _updateAgent(agent.copyWith(enabled: v)),
            ),
          ],
        ),
        subtitle: Text(
          agent.sourceBlockNames.isNotEmpty
              ? 'From: ${agent.sourceBlockNames} • Model: ${_agentApiConfigLabel(agent)}'
              : 'Order: ${agent.order} • Model: ${_agentApiConfigLabel(agent)}',
          style: TextStyle(fontSize: 11, color: context.cs.onSurfaceVariant),
        ),
        children: [_buildAgentDetails(agent)],
      ),
    );
  }

  Widget _buildAgentDetails(StudioAgent agent) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Prompt shard:',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          TextFormField(
            initialValue: agent.promptShard,
            maxLines: 6,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.all(12),
            ),
            style: const TextStyle(fontSize: 12),
            onChanged: (value) =>
                _updateAgent(agent.copyWith(promptShard: value)),
          ),
          const SizedBox(height: 16),
          Text(
            'Model:',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'current', label: Text('Current')),
              ButtonSegment(value: 'custom', label: Text('Custom')),
            ],
            selected: {agent.modelSource},
            onSelectionChanged: (s) =>
                _updateAgent(agent.copyWith(modelSource: s.first)),
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
          ),
          _modelHint(
            agent.modelSource == 'custom'
                ? 'Uses selected API config for this agent only.'
                : 'Uses Studio Run model: ${_contextInfo.runModelLabel}',
          ),
          if (agent.modelSource == 'custom') ...[
            const SizedBox(height: 8),
            _customApiSelector(agent),
            const SizedBox(height: 8),
            _providerModelSelector(agent),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: agent.temperature.toString(),
                  decoration: const InputDecoration(
                    labelText: 'Temp',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 12),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (v) {
                    final temp = double.tryParse(v);
                    if (temp != null) {
                      _updateAgent(agent.copyWith(temperature: temp));
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  initialValue: agent.maxTokens.toString(),
                  decoration: const InputDecoration(
                    labelText: 'Max tokens',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 12),
                  keyboardType: TextInputType.number,
                  onChanged: (v) {
                    final tokens = int.tryParse(v);
                    if (tokens != null) {
                      _updateAgent(agent.copyWith(maxTokens: tokens));
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  initialValue: agent.timeoutMs.toString(),
                  decoration: const InputDecoration(
                    labelText: 'Timeout ms',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 12),
                  keyboardType: TextInputType.number,
                  onChanged: (v) {
                    final ms = int.tryParse(v);
                    if (ms != null) {
                      _updateAgent(agent.copyWith(timeoutMs: ms));
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _updateAgent(StudioAgent updated) {
    final agents = _config!.agents.map((a) {
      return a.id == updated.id ? updated : a;
    }).toList();
    final newConfig = _config!.copyWith(
      agents: agents,
      updatedAt: currentTimestampSeconds(),
    );
    ref.read(studioConfigRepoProvider).upsert(newConfig);
    setState(() => _config = newConfig);
  }
}

class _StudioContextInfo {
  final List<Preset> presets;
  final List<ApiConfig> apiConfigs;
  final Preset? preset;
  final Preset? finalPreset;
  final ApiConfig? buildApiConfig;
  final ApiConfig? runApiConfig;
  final String presetLabel;
  final String buildModelLabel;
  final String runModelLabel;

  const _StudioContextInfo({
    this.presets = const [],
    this.apiConfigs = const [],
    this.preset,
    this.finalPreset,
    this.buildApiConfig,
    this.runApiConfig,
    this.presetLabel = 'Loading preset...',
    this.buildModelLabel = 'Loading model...',
    this.runModelLabel = 'Loading model...',
  });
}
