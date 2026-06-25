import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/llm/studio_decomposition_service.dart';
import '../../../core/llm/studio_request_preset.dart';
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
  List<StudioConfig> _profiles = const [];
  _StudioContextInfo _contextInfo = const _StudioContextInfo();
  String? _selectedProfileId;
  String? _selectedAgentStudioPresetId;
  String? _selectedFinalStudioPresetId;
  String? _selectedBuildApiConfigId;
  String? _selectedRunApiConfigId;
  List<StudioPresetOverride> _studioPresetOverrides = const [];
  String _builderPromptTemplate = '';
  bool _loading = true;
  bool _building = false;
  final Set<String> _regeneratingAgentIds = {};
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
      final profiles = await ref.read(studioConfigRepoProvider).getProfiles();
      final contextInfo = await _loadContextInfo(config: config);
      if (mounted) {
        setState(() {
          _config = config;
          _profiles = profiles;
          _selectedProfileId = config?.profileId;
          _contextInfo = contextInfo;
          _selectedAgentStudioPresetId = contextInfo.agentStudioPresetId;
          _selectedFinalStudioPresetId = contextInfo.finalStudioPresetId;
          _selectedBuildApiConfigId = contextInfo.buildApiConfig?.id;
          _selectedRunApiConfigId = contextInfo.runApiConfig?.id;
          _studioPresetOverrides = config?.studioPresetOverrides ?? const [];
          _builderPromptTemplate = config?.builderPromptTemplate ?? '';
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
        builderPromptTemplate: _builderPromptTemplate,
      );

      if (agents.isEmpty) {
        throw Exception('Decomposition returned no agents');
      }

      final now = currentTimestampSeconds();
      final profileId = _config?.profileId.isNotEmpty == true
          ? _config!.profileId
          : 'studio_${widget.sessionId}_$now';
      final newConfig = StudioConfig(
        sessionId: widget.sessionId,
        profileId: profileId,
        profileName: preset.name.isNotEmpty
            ? 'Studio: ${preset.name}'
            : 'Studio Profile',
        enabled: true,
        agents: agents,
        sourcePresetId: preset.id,
        finalPresetId: '',
        agentStudioPresetId: contextInfo.agentStudioPresetId,
        finalStudioPresetId: contextInfo.finalStudioPresetId,
        studioPresetOverrides: _studioPresetOverrides,
        sourcePresetHash: StudioDecompositionService.computePresetHash(
          preset.blocks.where((b) => b.enabled).toList(),
        ),
        buildApiConfigId: buildApiConfig.id,
        runApiConfigId: contextInfo.runApiConfig?.id ?? '',
        builderPromptTemplate: _builderPromptTemplate,
        createdAt: now,
        updatedAt: now,
      );

      await ref.read(studioConfigRepoProvider).upsert(newConfig);
      final profiles = await ref.read(studioConfigRepoProvider).getProfiles();

      if (mounted) {
        setState(() {
          _config = newConfig;
          _profiles = profiles;
          _selectedProfileId = profileId;
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

  Future<void> _regenerateAgentInstruction(StudioAgent agent) async {
    if (_config == null || _regeneratingAgentIds.contains(agent.id)) return;
    setState(() {
      _regeneratingAgentIds.add(agent.id);
      _error = null;
    });

    try {
      final contextInfo = await _loadContextInfo(config: _config);
      final preset = contextInfo.preset;
      final buildApiConfig = contextInfo.buildApiConfig;
      if (preset == null) {
        throw Exception(
          'No preset available. Create or select a preset first.',
        );
      }
      if (buildApiConfig == null) {
        throw Exception('No model selected for Studio build.');
      }

      final decompositionService = ref.read(studioDecompositionServiceProvider);
      final updatedAgent = await decompositionService
          .regenerateAgentInstruction(
            preset: preset,
            agent: agent,
            apiConfig: buildApiConfig,
            builderPromptTemplate: _builderPromptTemplate,
          );

      if (!mounted || _config == null) return;
      final agents = _config!.agents.map((a) {
        return a.id == agent.id ? updatedAgent.copyWith(order: a.order) : a;
      }).toList();
      final updatedConfig = _config!.copyWith(
        agents: agents,
        sourcePresetHash: StudioDecompositionService.computePresetHash(
          preset.blocks.where((b) => b.enabled).toList(),
        ),
        buildApiConfigId: buildApiConfig.id,
        builderPromptTemplate: _builderPromptTemplate,
        updatedAt: currentTimestampSeconds(),
      );
      await ref.read(studioConfigRepoProvider).upsert(updatedConfig);
      if (!mounted) return;
      setState(() {
        _config = updatedConfig;
        _contextInfo = contextInfo;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _regeneratingAgentIds.remove(agent.id));
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

    final preset = effectivePreset;
    final agentStudioPresetId =
        _selectedAgentStudioPresetId ??
        (config?.agentStudioPresetId.isNotEmpty == true
            ? config!.agentStudioPresetId
            : null) ??
        defaultAgentStudioPresetId;
    final finalStudioPresetId =
        _selectedFinalStudioPresetId ??
        (config?.finalStudioPresetId.isNotEmpty == true
            ? config!.finalStudioPresetId
            : null) ??
        defaultFinalStudioPresetId;

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
      apiConfigs: apiConfigs.where((c) => c.mode != 'embedding').toList(),
      preset: preset,
      presetLabel: preset?.name ?? 'No preset available',
      agentStudioPresetId: agentStudioPresetId,
      finalStudioPresetId: finalStudioPresetId,
      buildApiConfig: buildApiConfig,
      runApiConfig: runApiConfig,
      buildModelLabel: _apiLabel(buildApiConfig),
      runModelLabel: _apiLabel(runApiConfig),
    );
  }

  Future<void> _applyProfile(String? profileId) async {
    if (profileId == null || profileId.isEmpty) return;
    final repo = ref.read(studioConfigRepoProvider);
    await repo.bindSessionToProfile(
      sessionId: widget.sessionId,
      profileId: profileId,
    );
    final config = await repo.getBySessionId(widget.sessionId);
    final profiles = await repo.getProfiles();
    final contextInfo = await _loadContextInfo(config: config);
    if (!mounted) return;
    setState(() {
      _config = config;
      _profiles = profiles;
      _selectedProfileId = profileId;
      _contextInfo = contextInfo;
      _studioPresetOverrides = config?.studioPresetOverrides ?? const [];
    });
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
        buildApiConfigId: contextInfo.buildApiConfig?.id ?? '',
        runApiConfigId: contextInfo.runApiConfig?.id ?? '',
        builderPromptTemplate: _builderPromptTemplate,
        agentStudioPresetId: contextInfo.agentStudioPresetId,
        finalStudioPresetId: contextInfo.finalStudioPresetId,
        studioPresetOverrides: _studioPresetOverrides,
        updatedAt: currentTimestampSeconds(),
      );
      await ref.read(studioConfigRepoProvider).upsert(updated);
      if (mounted) setState(() => _config = updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 650, maxHeight: size.height - 48),
        child: SizedBox(
          width: size.width < 650 ? size.width - 32 : 650,
          height: size.height < 648 ? size.height - 48 : 600,
          child: Stack(
            children: [
              Column(
                children: [
                  _buildHeader(),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _buildBody(),
                  ),
                ],
              ),
              if (_building) _buildBuildingOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBuildingOverlay() {
    return Positioned.fill(
      child: AbsorbPointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Center(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Building Studio...',
                      style: TextStyle(
                        color: context.cs.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
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
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Center(
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
          _buildSourcePresetInfo(),
          if (_profiles.isNotEmpty) ...[
            const SizedBox(height: 8),
            _profileSelector(),
          ],
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
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _showBuilderPromptDialog,
              icon: const Icon(Icons.article_outlined, size: 18),
              label: const Text('Builder prompt'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showBuilderPromptDialog() async {
    final controller = TextEditingController(
      text: _builderPromptTemplate.trim().isNotEmpty
          ? _builderPromptTemplate
          : StudioDecompositionService.defaultBuilderPromptTemplate,
    );
    var useDefault = _builderPromptTemplate.trim().isEmpty;

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (dialogContext, dialogSetState) {
              return AlertDialog(
                title: const Text('Studio builder prompt'),
                content: SizedBox(
                  width: 760,
                  height: 620,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'This template is sent to the build model when you rebuild Studio. Keep {{blocksSummary}} where the source preset blocks should be inserted.',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        value: useDefault,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Use default prompt'),
                        subtitle: const Text(
                          'Turn off to save a custom builder prompt in this Studio profile.',
                        ),
                        onChanged: (value) {
                          dialogSetState(() {
                            useDefault = value;
                            if (value) {
                              controller.text = StudioDecompositionService
                                  .defaultBuilderPromptTemplate;
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: TextFormField(
                          controller: controller,
                          enabled: !useDefault,
                          expands: true,
                          maxLines: null,
                          minLines: null,
                          textAlignVertical: TextAlignVertical.top,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                            labelText: 'Prompt template',
                          ),
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () async {
                      final next = useDefault ? '' : controller.text;
                      setState(() => _builderPromptTemplate = next);
                      if (_config != null) {
                        final updated = _config!.copyWith(
                          builderPromptTemplate: next,
                          updatedAt: currentTimestampSeconds(),
                        );
                        await ref
                            .read(studioConfigRepoProvider)
                            .upsert(updated);
                        if (mounted) setState(() => _config = updated);
                      }
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop();
                      }
                    },
                    child: const Text('Save'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  Widget _profileSelector() {
    final value = _profiles.any((p) => p.profileId == _selectedProfileId)
        ? _selectedProfileId
        : null;
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Studio profile',
        isDense: true,
        border: OutlineInputBorder(),
      ),
      items: _profiles
          .map(
            (profile) => DropdownMenuItem(
              value: profile.profileId,
              child: Text(
                profile.profileName.isNotEmpty
                    ? profile.profileName
                    : profile.sourcePresetId.isNotEmpty
                    ? 'Studio: ${profile.sourcePresetId}'
                    : profile.profileId,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: _applyProfile,
    );
  }

  Widget _buildSourcePresetInfo() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Build source preset',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            child: Text(
              _contextInfo.presetLabel,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Preset settings',
          onPressed: _showPresetSettingsDialog,
          icon: const Icon(Icons.tune, size: 20),
        ),
      ],
    );
  }

  Future<void> _showPresetSettingsDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, dialogSetState) {
            final presets = resolvedStudioRequestPresets(
              _studioPresetOverrides,
            );
            return AlertDialog(
              title: const Text('Studio preset settings'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _studioRequestPresetSelector(
                      label: 'Agent Studio preset',
                      value: _selectedAgentStudioPresetId,
                      fallbackId: _contextInfo.agentStudioPresetId,
                      presets: presets,
                      onChanged: (value) async {
                        setState(() => _selectedAgentStudioPresetId = value);
                        dialogSetState(() {});
                        await _refreshContextInfo(persistSelection: true);
                      },
                    ),
                    const SizedBox(height: 12),
                    _studioRequestPresetSelector(
                      label: 'Final Studio preset',
                      value: _selectedFinalStudioPresetId,
                      fallbackId: _contextInfo.finalStudioPresetId,
                      presets: presets,
                      onChanged: (value) async {
                        setState(() => _selectedFinalStudioPresetId = value);
                        dialogSetState(() {});
                        await _refreshContextInfo(persistSelection: true);
                      },
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => _showStudioPresetEditorDialog(
                        parentDialogContext: dialogContext,
                        parentSetState: dialogSetState,
                      ),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Edit Studio presets'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showStudioPresetEditorDialog({
    required BuildContext parentDialogContext,
    required StateSetter parentSetState,
  }) async {
    final presets = resolvedStudioRequestPresets(_studioPresetOverrides);
    var editingId = _selectedFinalStudioPresetId?.isNotEmpty == true
        ? _selectedFinalStudioPresetId!
        : defaultFinalStudioPresetId;
    var editing = presets.firstWhere(
      (preset) => preset.id == editingId,
      orElse: () => presets.first,
    );
    var editingBlocks = _orderedStudioBlocks(editing.blocks);
    final nameController = TextEditingController(text: editing.name);

    void loadPreset(StudioRequestPreset preset) {
      editingId = preset.id;
      editing = preset;
      editingBlocks = _orderedStudioBlocks(preset.blocks);
      nameController.text = preset.name;
    }

    try {
      await showDialog<void>(
        context: parentDialogContext,
        builder: (editorContext) {
          return StatefulBuilder(
            builder: (editorContext, editorSetState) {
              final available = resolvedStudioRequestPresets(
                _studioPresetOverrides,
              );
              return AlertDialog(
                title: const Text('Edit Studio preset'),
                content: SizedBox(
                  width: 720,
                  height: 620,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: editingId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Studio preset',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: available
                            .map(
                              (preset) => DropdownMenuItem(
                                value: preset.id,
                                child: Text(preset.name),
                              ),
                            )
                            .toList(),
                        onChanged: (id) {
                          final preset = available.firstWhere(
                            (p) => p.id == id,
                            orElse: () => available.first,
                          );
                          editorSetState(() => loadPreset(preset));
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Text(
                            'Prompt blocks',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () {
                              editorSetState(() {
                                editingBlocks = _reorderStudioBlocks([
                                  _newCustomStudioBlock(editingBlocks.length),
                                  ...editingBlocks,
                                ]);
                              });
                            },
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add block'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ReorderableListView.builder(
                          buildDefaultDragHandles: false,
                          itemCount: editingBlocks.length,
                          onReorderItem: (oldIndex, newIndex) {
                            editorSetState(() {
                              final blocks = [...editingBlocks];
                              final item = blocks.removeAt(oldIndex);
                              blocks.insert(newIndex, item);
                              editingBlocks = _reorderStudioBlocks(blocks);
                            });
                          },
                          itemBuilder: (context, index) {
                            final block = editingBlocks[index];
                            return Card(
                              key: ValueKey(block.id),
                              child: ExpansionTile(
                                leading: ReorderableDragStartListener(
                                  index: index,
                                  child: const Icon(Icons.drag_handle),
                                ),
                                title: Text(
                                  block.title.isNotEmpty
                                      ? block.title
                                      : block.kind,
                                ),
                                subtitle: Text('${block.kind} • ${block.role}'),
                                trailing: Switch(
                                  value: block.enabled,
                                  onChanged: (value) {
                                    editorSetState(() {
                                      editingBlocks = _updateStudioBlock(
                                        editingBlocks,
                                        block.id,
                                        (current) =>
                                            current.copyWith(enabled: value),
                                      );
                                    });
                                  },
                                ),
                                childrenPadding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  16,
                                ),
                                children: [
                                  TextFormField(
                                    key: ValueKey('${block.id}_title'),
                                    initialValue: block.title,
                                    decoration: const InputDecoration(
                                      labelText: 'Block title',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    onChanged: (value) {
                                      editingBlocks = _updateStudioBlock(
                                        editingBlocks,
                                        block.id,
                                        (current) =>
                                            current.copyWith(title: value),
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: DropdownButtonFormField<String>(
                                          initialValue: block.kind,
                                          isExpanded: true,
                                          decoration: const InputDecoration(
                                            labelText: 'Kind',
                                            border: OutlineInputBorder(),
                                            isDense: true,
                                          ),
                                          items: _studioBlockKinds
                                              .map(
                                                (kind) => DropdownMenuItem(
                                                  value: kind,
                                                  child: Text(kind),
                                                ),
                                              )
                                              .toList(),
                                          onChanged: (value) {
                                            if (value == null) return;
                                            editorSetState(() {
                                              editingBlocks =
                                                  _updateStudioBlock(
                                                    editingBlocks,
                                                    block.id,
                                                    (current) => current
                                                        .copyWith(kind: value),
                                                  );
                                            });
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        width: 150,
                                        child: DropdownButtonFormField<String>(
                                          initialValue: block.role,
                                          decoration: const InputDecoration(
                                            labelText: 'Role',
                                            border: OutlineInputBorder(),
                                            isDense: true,
                                          ),
                                          items: const [
                                            DropdownMenuItem(
                                              value: 'system',
                                              child: Text('system'),
                                            ),
                                            DropdownMenuItem(
                                              value: 'user',
                                              child: Text('user'),
                                            ),
                                            DropdownMenuItem(
                                              value: 'assistant',
                                              child: Text('assistant'),
                                            ),
                                          ],
                                          onChanged: (value) {
                                            if (value == null) return;
                                            editorSetState(() {
                                              editingBlocks =
                                                  _updateStudioBlock(
                                                    editingBlocks,
                                                    block.id,
                                                    (current) => current
                                                        .copyWith(role: value),
                                                  );
                                            });
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    key: ValueKey('${block.id}_content'),
                                    initialValue: block.content,
                                    decoration: const InputDecoration(
                                      labelText: 'Content',
                                      alignLabelWithHint: true,
                                      border: OutlineInputBorder(),
                                      helperText:
                                          'Used by agent_instruction/custom_text. Context kinds inject live prompt data.',
                                    ),
                                    minLines: 3,
                                    maxLines: 8,
                                    onChanged: (value) {
                                      editingBlocks = _updateStudioBlock(
                                        editingBlocks,
                                        block.id,
                                        (current) =>
                                            current.copyWith(content: value),
                                      );
                                    },
                                  ),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton.icon(
                                      onPressed: () {
                                        editorSetState(() {
                                          editingBlocks = _reorderStudioBlocks(
                                            editingBlocks
                                                .where((b) => b.id != block.id)
                                                .toList(),
                                          );
                                        });
                                      },
                                      icon: const Icon(Icons.delete_outline),
                                      label: const Text('Delete'),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      final base = defaultStudioRequestPresetById(editingId);
                      editorSetState(() => loadPreset(base));
                    },
                    child: const Text('Reset'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(editorContext).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () async {
                      final updated = StudioPresetOverride(
                        id: editingId,
                        name: nameController.text.trim(),
                        blocks: _reorderStudioBlocks(editingBlocks),
                      );
                      await _saveStudioPresetOverride(updated);
                      if (!mounted) return;
                      parentSetState(() {});
                      if (!editorContext.mounted) return;
                      Navigator.of(editorContext).pop();
                    },
                    child: const Text('Save'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      nameController.dispose();
    }
  }

  List<StudioPresetBlock> _orderedStudioBlocks(List<StudioPresetBlock> blocks) {
    final next = [...blocks]..sort((a, b) => a.order.compareTo(b.order));
    return _reorderStudioBlocks(next);
  }

  List<StudioPresetBlock> _reorderStudioBlocks(List<StudioPresetBlock> blocks) {
    return [
      for (var i = 0; i < blocks.length; i++) blocks[i].copyWith(order: i),
    ];
  }

  StudioPresetBlock _newCustomStudioBlock(int existingCount) {
    final id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return StudioPresetBlock(
      id: 'custom_$id',
      title: 'Custom block ${existingCount + 1}',
      kind: 'custom_text',
      role: 'system',
      content: '',
    );
  }

  List<StudioPresetBlock> _updateStudioBlock(
    List<StudioPresetBlock> blocks,
    String id,
    StudioPresetBlock Function(StudioPresetBlock current) update,
  ) {
    return [for (final block in blocks) block.id == id ? update(block) : block];
  }

  static const _studioBlockKinds = [
    'agent_instruction',
    'previous_agents',
    'user_persona',
    'char_card',
    'scenario',
    'char_personality',
    'example_dialogue',
    'authors_note',
    'chat_history',
    'worldInfoBefore',
    'worldInfoAfter',
    'memory',
    'summary',
    'guided_generation',
    'static_context',
    'dynamic_context',
    'custom_text',
  ];

  Future<void> _saveStudioPresetOverride(StudioPresetOverride override) async {
    final next = <StudioPresetOverride>[];
    var replaced = false;
    for (final item in _studioPresetOverrides) {
      if (item.id == override.id) {
        next.add(override);
        replaced = true;
      } else {
        next.add(item);
      }
    }
    if (!replaced) next.add(override);

    setState(() => _studioPresetOverrides = next);
    if (_config != null) {
      final updated = _config!.copyWith(
        studioPresetOverrides: next,
        updatedAt: currentTimestampSeconds(),
      );
      await ref.read(studioConfigRepoProvider).upsert(updated);
      if (mounted) setState(() => _config = updated);
    }
  }

  Widget _studioRequestPresetSelector({
    required String label,
    required String? value,
    required String fallbackId,
    required List<StudioRequestPreset> presets,
    required Future<void> Function(String?) onChanged,
  }) {
    final effectiveValue = presets.any((preset) => preset.id == value)
        ? value
        : fallbackId;
    return DropdownButtonFormField<String>(
      initialValue: effectiveValue,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      items: presets
          .map(
            (preset) =>
                DropdownMenuItem(value: preset.id, child: Text(preset.name)),
          )
          .toList(),
      onChanged: onChanged,
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
              ? 'From: ${agent.sourceBlockNames} • Policy: ${isLast ? 'turn' : _normalizedRefreshPolicy(agent.refreshPolicy)} • Model: ${_agentApiConfigLabel(agent)}'
              : 'Order: ${agent.order} • Policy: ${isLast ? 'turn' : _normalizedRefreshPolicy(agent.refreshPolicy)} • Model: ${_agentApiConfigLabel(agent)}',
          style: TextStyle(fontSize: 11, color: context.cs.onSurfaceVariant),
        ),
        children: [_buildAgentDetails(agent)],
      ),
    );
  }

  Widget _buildAgentDetails(StudioAgent agent) {
    final isFinal = _config?.agents.lastOrNull?.id == agent.id;
    final regenerating = _regeneratingAgentIds.contains(agent.id);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Prompt shard:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.cs.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: regenerating
                    ? null
                    : () => _regenerateAgentInstruction(agent),
                icon: regenerating
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_fix_high, size: 16),
                label: Text(regenerating ? 'Regenerating...' : 'Regenerate'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          TextFormField(
            key: ValueKey('${agent.id}_${agent.promptShard.hashCode}'),
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
            'Refresh policy:',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'static', label: Text('Static')),
              ButtonSegment(value: 'scene', label: Text('Scene')),
              ButtonSegment(value: 'turn', label: Text('Turn')),
            ],
            selected: {
              isFinal ? 'turn' : _normalizedRefreshPolicy(agent.refreshPolicy),
            },
            onSelectionChanged: isFinal
                ? null
                : (s) => _updateAgent(agent.copyWith(refreshPolicy: s.first)),
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
          ),
          _modelHint(
            isFinal
                ? 'Final responder always runs every turn.'
                : agent.invalidationSignals.isNotEmpty
                ? 'Invalidates on: ${agent.invalidationSignals.join(', ')}'
                : 'Static and scene agents may reuse cached briefs.',
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

  String _normalizedRefreshPolicy(String policy) {
    return switch (policy.trim().toLowerCase()) {
      'static' || 'scene' || 'turn' => policy.trim().toLowerCase(),
      _ => 'turn',
    };
  }
}

class _StudioContextInfo {
  final List<ApiConfig> apiConfigs;
  final Preset? preset;
  final ApiConfig? buildApiConfig;
  final ApiConfig? runApiConfig;
  final String presetLabel;
  final String agentStudioPresetId;
  final String finalStudioPresetId;
  final String buildModelLabel;
  final String runModelLabel;

  const _StudioContextInfo({
    this.apiConfigs = const [],
    this.preset,
    this.buildApiConfig,
    this.runApiConfig,
    this.presetLabel = 'Loading preset...',
    this.agentStudioPresetId = defaultAgentStudioPresetId,
    this.finalStudioPresetId = defaultFinalStudioPresetId,
    this.buildModelLabel = 'Loading model...',
    this.runModelLabel = 'Loading model...',
  });
}
