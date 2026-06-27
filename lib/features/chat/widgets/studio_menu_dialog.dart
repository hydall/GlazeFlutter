import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/llm/studio_decomposition_service.dart';
import '../../../core/llm/transport/transport_factory.dart';
import '../../../core/models/api_config.dart';
import '../../../core/models/studio_config.dart';
import '../../../core/models/tracker.dart';
import '../../../core/state/db_provider.dart';
import '../../../core/state/memory_agent_providers.dart';
import '../../../core/state/preset_resolution.dart';
import '../../../core/utils/time_helpers.dart';
import '../../../shared/widgets/glaze_bottom_sheet.dart';
import '../../../shared/widgets/glaze_toast.dart';
import '../../settings/api_list_provider.dart';
import 'post_building_menu_dialog.dart';

/// Lightweight Studio tracker dialog (Phase 7.1).
///
/// Shows the Studio/tracker enable toggle, a compact list of active trackers
/// with their `contextSize` / `runInterval` / model-override badges and the
/// tracker's current value (if any), and a link to the advanced pipeline
/// configuration in the Post-Building menu.
///
/// The full 8-controller editor that previously lived here was removed in
/// Phase 2 of docs/PLAN_AGENTIC_STUDIO.md. Per Phase 7.1 this dialog is
/// deliberately lightweight: it does NOT duplicate any LLM/pipeline settings
/// (POST-cleaner, write-loop sidecar, model selectors) — those stay in
/// [PostBuildingMenuDialog]. This dialog only surfaces tracker state and
/// quick toggles.
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
  List<Tracker> _trackers = const [];
  bool _loading = true;
  bool _loadingModels = false;
  bool _building = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(studioConfigRepoProvider);
    final trackerRepo = ref.read(trackerRepoProvider);
    // Warm the API list so model suggestions are available when the user taps
    // a tracker's model chip.
    await ref.read(apiListProvider.future);
    final config = await repo.getBySessionId(widget.sessionId);
    final trackers = await trackerRepo.getBySessionId(widget.sessionId);
    if (!mounted) return;
    setState(() {
      _config = config;
      _trackers = trackers;
      _loading = false;
    });
  }

  Future<void> _toggleEnabled(bool enabled) async {
    final repo = ref.read(studioConfigRepoProvider);
    final current = _config;
    if (current == null) return;
    final updated = current.copyWith(enabled: enabled);
    await repo.upsert(updated);
    if (!mounted) return;
    setState(() => _config = updated);
  }

  Future<void> _toggleAgent(StudioAgent agent, bool enabled) async {
    final repo = ref.read(studioConfigRepoProvider);
    final current = _config;
    if (current == null) return;
    final agents = current.agents.map((a) {
      if (a.id == agent.id) return a.copyWith(enabled: enabled);
      return a;
    }).toList();
    final updated = current.copyWith(agents: agents);
    await repo.upsert(updated);
    if (!mounted) return;
    setState(() => _config = updated);
  }

  /// Resolve the [ApiConfig] a tracker runs against, mirroring
  /// [AgentRunner]'s resolution: the Studio's `runApiConfigId` if set,
  /// otherwise the chat's active API config. Trackers reuse this config's
  /// provider/endpoint/key — only the model id is overridden per agent — so
  /// the model list must come from this exact provider.
  ApiConfig? _resolveTrackerApiConfig() {
    final apiConfigs = ref.read(apiListProvider).value ?? const <ApiConfig>[];
    final runId = _config?.runApiConfigId ?? '';
    if (runId.isNotEmpty) {
      final byRunId = apiConfigs.where((c) => c.id == runId).firstOrNull;
      if (byRunId != null) return byRunId;
    }
    return ref.read(activeApiConfigProvider);
  }

  /// Resolve the [ApiConfig] used for the one-shot build-time decomposition
  /// LLM call. Mirrors the old `_loadContextInfo.buildApiConfig` resolution:
  /// the Studio's `buildApiConfigId` if set, otherwise the chat's active API
  /// config. The Studio's `buildModelOverride` is applied on top when set so
  /// the user can run the builder on a different model than chat.
  ApiConfig? _resolveBuildApiConfig() {
    final apiConfigs = ref.read(apiListProvider).value ?? const <ApiConfig>[];
    final buildId = _config?.buildApiConfigId ?? '';
    final override = _config?.buildModelOverride ?? '';
    if (buildId.isNotEmpty) {
      final byBuildId = apiConfigs.where((c) => c.id == buildId).firstOrNull;
      if (byBuildId != null) {
        return override.isNotEmpty
            ? byBuildId.copyWith(model: override)
            : byBuildId;
      }
    }
    final active = ref.read(activeApiConfigProvider);
    if (active == null) return null;
    return override.isNotEmpty ? active.copyWith(model: override) : active;
  }

  /// Build Studio trackers from the chat's effective preset (auto
  /// decomposition). Runs the [StudioDecompositionService] against the
  /// resolved build API, then persists the resulting agents + broadcast
  /// blocks + preset hash. The last agent (highest order) is the generator;
  /// all earlier agents are pre-generation trackers — the exact shape
  /// [MemoryStudioService.runTrackerCycle] consumes.
  Future<void> _buildStudio() async {
    final preset = ref.read(
      effectivePresetForChatProvider(
        (charId: widget.charId, sessionId: widget.sessionId),
      ),
    );
    if (preset == null) {
      GlazeToast.show(
        context,
        'No preset available. Create or select a preset first.',
      );
      return;
    }
    final apiConfig = _resolveBuildApiConfig();
    if (apiConfig == null) {
      GlazeToast.show(
        context,
        'No API configured. Set one up in API settings first.',
      );
      return;
    }

    setState(() => _building = true);
    try {
      final decompositionService = ref.read(studioDecompositionServiceProvider);
      final routingMode = (_config?.routingMode.isNotEmpty ?? false)
          ? _config!.routingMode
          : 'verbatim';
      final agents = await decompositionService.decompose(
        preset: preset,
        sessionId: widget.sessionId,
        apiConfig: apiConfig,
        builderPromptTemplate: _config?.builderPromptTemplate ?? '',
        routingMode: routingMode,
      );
      if (agents.isEmpty) {
        throw Exception('Decomposition returned no agents');
      }

      // Capture cross-cutting "broadcast" blocks (output language + prose
      // guards) verbatim so the POST-cleaner can apply the user's own rules.
      final broadcastBlocks = decompositionService
          .collectBroadcastBlocks(preset)
          .map((b) {
            final name = b.name.isNotEmpty ? b.name : b.id;
            return '[Block: $name]\n${b.content.trim()}';
          })
          .where((s) => s.trim().isNotEmpty)
          .toList();

      final now = currentTimestampSeconds();
      final existing = _config;
      final newConfig = (existing ?? StudioConfig(sessionId: widget.sessionId))
          .copyWith(
            agents: agents,
            enabled: true,
            sourcePresetId: preset.id,
            sourcePresetHash: StudioDecompositionService.computePresetHash(
              preset.blocks.where((b) => b.enabled).toList(),
            ),
            buildApiConfigId: apiConfig.id,
            broadcastBlocks: broadcastBlocks,
            updatedAt: now,
            createdAt: existing?.createdAt ?? now,
          );

      await ref.read(studioConfigRepoProvider).upsert(newConfig);
      if (!mounted) return;
      setState(() {
        _config = newConfig;
        _building = false;
      });
      GlazeToast.show(
        context,
        'Studio built: ${agents.length} agents from "${preset.name}".',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _building = false);
      GlazeToast.show(context, 'Build failed: $e');
    }
  }

  /// Edit a tracker's model override by picking from the provider's live model
  /// list. Trackers run on the chat's resolved run API; the override only swaps
  /// the model id (empty = use the chat model). We fetch the available models
  /// from that provider's `/models` endpoint, exactly like the API settings
  /// screen, and present them in a bottom sheet.
  Future<void> _editAgentModel(StudioAgent agent) async {
    final apiConfig = _resolveTrackerApiConfig();
    if (apiConfig == null) {
      GlazeToast.show(
        context,
        'No chat API configured. Set one up in API settings first.',
      );
      return;
    }
    final endpoint = apiConfig.endpoint.trim();
    final apiKey = apiConfig.apiKey.trim();

    // Fetch the live model list from the provider behind a blocking spinner.
    setState(() => _loadingModels = true);
    List<String> models;
    try {
      final fetched = await pickChatTransport(
        apiConfig.protocol,
      ).fetchModels(endpoint: endpoint, apiKey: apiKey);
      models =
          fetched
              .map((m) => (m['id'] ?? '').toString())
              .where((id) => id.isNotEmpty)
              .toList()
            ..sort();
    } catch (_) {
      models = const [];
    }
    if (!mounted) return;
    setState(() => _loadingModels = false);

    if (models.isEmpty) {
      GlazeToast.show(
        context,
        'Could not fetch models from ${apiConfig.name.isEmpty ? "the provider" : apiConfig.name}. '
        'Check the API endpoint and key in settings.',
      );
      return;
    }

    // Surface the current override (and the chat's own model) so the user sees
    // what is active and can pin it even if it is missing from the live list.
    final current = agent.modelOverride;
    final chatModel = apiConfig.model;
    if (current.isNotEmpty && !models.contains(current)) {
      models.insert(0, current);
    }
    final selectedIndex = current.isNotEmpty ? models.indexOf(current) : -1;

    if (!mounted) return;
    await GlazeBottomSheet.show<void>(
      context,
      title: agent.name.isEmpty ? agent.id : agent.name,
      scrollToIndex: selectedIndex >= 0 ? selectedIndex : null,
      items: [
        // Sentinel option: clear the override and fall back to the chat model.
        BottomSheetItem(
          label: 'Use chat model',
          hint: chatModel.isEmpty ? null : chatModel,
          icon: current.isEmpty ? Icons.check : Icons.chat_bubble_outline,
          iconColor: Theme.of(context).colorScheme.primary,
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            _setAgentModelOverride(agent, '');
          },
        ),
        ...models.map(
          (m) => BottomSheetItem(
            label: m,
            icon: m == current ? Icons.check : null,
            iconColor: Theme.of(context).colorScheme.primary,
            onTap: () {
              Navigator.of(context, rootNavigator: true).pop();
              _setAgentModelOverride(agent, m);
            },
          ),
        ),
      ],
    );
  }

  Future<void> _setAgentModelOverride(
    StudioAgent agent,
    String modelOverride,
  ) async {
    final repo = ref.read(studioConfigRepoProvider);
    final current = _config;
    if (current == null) return;
    final agents = current.agents.map((a) {
      if (a.id == agent.id) return a.copyWith(modelOverride: modelOverride);
      return a;
    }).toList();
    final updated = current.copyWith(agents: agents);
    await repo.upsert(updated);
    if (!mounted) return;
    setState(() => _config = updated);
  }

  Future<void> _openAdvanced() async {
    Navigator.of(context).pop();
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (_) => PostBuildingMenuDialog(
        charId: widget.charId,
        sessionId: widget.sessionId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final agents = _config?.agents ?? const <StudioAgent>[];
    final activeAgents = agents.where((a) => a.enabled).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    final disabledAgents = agents.where((a) => !a.enabled).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.tune, color: cs.primary),
                        const SizedBox(width: 8),
                        Text('Studio', style: tt.titleMedium),
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close, size: 20),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_loading)
                      const Center(child: CircularProgressIndicator())
                    else ...[
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Enable Studio trackers'),
                        subtitle: Text(
                          'Trackers run alongside the main generator. Batched by '
                          '(provider, model). Configure prompts in the Post-Building menu.',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        value: _config?.enabled ?? false,
                        onChanged: (v) => _toggleEnabled(v),
                      ),
                      const SizedBox(height: 12),
                      if (activeAgents.isEmpty && disabledAgents.isEmpty)
                        Text(
                          'No trackers configured. Tap "Build Studio" to '
                          'decompose the active preset into trackers, or add '
                          'agents in the Post-Building menu.',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        )
                      else ...[
                        Text(
                          'Active trackers (${activeAgents.length})',
                          style: tt.labelMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (activeAgents.isEmpty)
                          Text(
                            '— none —',
                            style: tt.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          )
                        else
                          ...activeAgents.map(
                            (a) => _TrackerRow(
                              agent: a,
                              value: _trackerValueFor(a.name),
                              onToggle: (v) => _toggleAgent(a, v),
                              onEditModel: () => _editAgentModel(a),
                            ),
                          ),
                        if (disabledAgents.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            'Disabled (${disabledAgents.length})',
                            style: tt.labelMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          ...disabledAgents.map(
                            (a) => _TrackerRow(
                              agent: a,
                              value: _trackerValueFor(a.name),
                              onToggle: (v) => _toggleAgent(a, v),
                              onEditModel: () => _editAgentModel(a),
                            ),
                          ),
                        ],
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: _building ? null : _buildStudio,
                            icon: const Icon(Icons.auto_fix_high, size: 16),
                            label: const Text('Build Studio'),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: _openAdvanced,
                            icon: const Icon(Icons.open_in_new, size: 16),
                            label: const Text('Advanced'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // Blocking overlay while models are fetched or Studio is built.
            if (_loadingModels || _building)
              Positioned.fill(
                child: ColoredBox(
                  color: cs.scrim.withValues(alpha: 0.4),
                  child: Center(
                    child: _building
                        ? const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 12),
                              Text('Building Studio…'),
                            ],
                          )
                        : const CircularProgressIndicator(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Find the current [Tracker.value] for [name], truncated for display.
  /// Returns `null` if no tracker with this name exists for the session —
  /// the agent may be configured but not yet have run.
  String? _trackerValueFor(String name) {
    final match = _trackers.where((t) => t.name == name).toList();
    if (match.isEmpty) return null;
    final value = match.first.value.trim();
    if (value.isEmpty) return null;
    if (value.length <= 80) return value;
    return '${value.substring(0, 77)}...';
  }
}

/// Compact per-tracker row in the lightweight Studio dialog (Phase 7.1).
/// Shows: enable switch (leading), name + role badge, compact status chips
/// (`ctx:N`, `every:N`, model override), and the current tracker value
/// (truncated) when present.
class _TrackerRow extends StatelessWidget {
  final StudioAgent agent;
  final String? value;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEditModel;

  const _TrackerRow({
    required this.agent,
    required this.value,
    required this.onToggle,
    required this.onEditModel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final chips = <_StatusChip>[
      _StatusChip(label: 'ctx:${agent.contextSize}'),
      if (agent.runInterval != 1)
        _StatusChip(label: 'every ${agent.runInterval}'),
      if (agent.runIndividually) _StatusChip(label: 'solo', emphasize: true),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Switch(value: agent.enabled, onChanged: onToggle),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        agent.name.isEmpty ? agent.id : agent.name,
                        style: tt.bodyMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (agent.role.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(
                        agent.role,
                        style: tt.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ...chips.map((c) => _chip(context, c.label, c.emphasize)),
                      // Tappable model chip — the one piece of per-tracker
                      // config the lightweight dialog edits inline.
                      _modelChip(context),
                    ],
                  ),
                ),
                if (value != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      value!,
                      style: tt.bodySmall?.copyWith(
                        color: cs.primary,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _modelChip(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasOverride = agent.modelOverride.isNotEmpty;
    final label = hasOverride ? agent.modelOverride : 'chat model';
    return InkWell(
      onTap: onEditModel,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: hasOverride ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: cs.primary.withValues(alpha: 0.4),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.edit,
              size: 11,
              color: hasOverride ? cs.onPrimaryContainer : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 3),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: hasOverride
                    ? cs.onPrimaryContainer
                    : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, String label, bool emphasize) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: emphasize ? cs.primaryContainer : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: emphasize ? cs.onPrimaryContainer : cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _StatusChip {
  final String label;
  final bool emphasize;
  const _StatusChip({required this.label, this.emphasize = false});
}
