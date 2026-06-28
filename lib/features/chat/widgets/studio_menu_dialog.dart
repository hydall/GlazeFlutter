import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/studio_config.dart';
import '../../../core/state/db_provider.dart';
import '../../../shared/widgets/glaze_bottom_sheet.dart';
import '../../../shared/widgets/glaze_toast.dart';
import '../controllers/studio_menu_controller.dart';
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
///
/// Business logic (config load, read-modify-write, build/regenerate pipeline,
/// API-config resolution) lives in [StudioMenuController]. The widget keeps
/// `build`, the private `_TrackerRow`/`_StatusChip` widgets, and the
/// bottom-sheet / dialog interactions (`_editAgentModel`, `_editAgentShard`,
/// `_openAdvanced`).
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
  late final StudioMenuController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = StudioMenuController(ref, widget.sessionId, widget.charId);
    _load();
  }

  Future<void> _load() async {
    await _ctrl.load();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _toggleEnabled(bool enabled) async {
    await _ctrl.toggleEnabled(enabled);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _toggleAgent(StudioAgent agent, bool enabled) async {
    await _ctrl.toggleAgent(agent, enabled);
    if (!mounted) return;
    setState(() {});
  }

  /// Edit a tracker's model override by picking from the provider's live model
  /// list. Trackers run on the chat's resolved run API; the override only swaps
  /// the model id (empty = use the chat model). We fetch the available models
  /// from that provider's `/models` endpoint, exactly like the API settings
  /// screen, and present them in a bottom sheet.
  Future<void> _editAgentModel(StudioAgent agent) async {
    final apiConfig = _ctrl.resolveTrackerApiConfig();
    if (apiConfig == null) {
      GlazeToast.show(
        context,
        'No chat API configured. Set one up in API settings first.',
      );
      return;
    }

    final models = await _ctrl.fetchModelsForTrackerConfig();
    if (!mounted) return;
    setState(() {});

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
    await _ctrl.setAgentModelOverride(agent, modelOverride);
    if (!mounted) return;
    setState(() {});
  }

  /// Open a multi-line editor for one tracker's `promptShard` (manual shard
  /// editing). Persists on Save; Cancel discards. This complements the auto
  /// [StudioDecompositionService.decompose] build — the user can hand-tune
  /// any agent's instruction after a build.
  Future<void> _editAgentShard(StudioAgent agent) async {
    final controller = TextEditingController(text: agent.promptShard);
    final result = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (context) {
        return AlertDialog(
          title: Text(
            agent.name.isEmpty ? 'Edit prompt shard' : 'Edit "${agent.name}"',
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: TextField(
              controller: controller,
              maxLines: 12,
              autofocus: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Prompt shard for this tracker…',
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (result == null) return;
    await _setAgentPromptShard(agent, result);
  }

  Future<void> _setAgentPromptShard(StudioAgent agent, String shard) async {
    await _ctrl.setAgentPromptShard(agent, shard);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _buildStudio() async {
    setState(() {}); // show "Building Studio…" overlay immediately
    final message = await _ctrl.buildStudio();
    if (!mounted) return;
    setState(() {});
    if (message.isNotEmpty) GlazeToast.show(context, message);
  }

  /// Regenerate one tracker's `promptShard` from its source preset blocks via
  /// [StudioDecompositionService.regenerateAgentInstruction]. Uses the same
  /// build API config as [_buildStudio]. Single-agent regen reuses the
  /// deterministic keyword bucketing (no LLM router call); the build-time LLM
  /// map only matters for a full decompose.
  Future<void> _regenerateAgentInstruction(StudioAgent agent) async {
    setState(() {}); // show regenerating chip immediately
    final message = await _ctrl.regenerateAgentInstruction(agent);
    if (!mounted) return;
    setState(() {});
    if (message.isNotEmpty) GlazeToast.show(context, message);
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
    final agents = _ctrl.config?.agents ?? const <StudioAgent>[];
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
                    if (_ctrl.loading)
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
                        value: _ctrl.config?.enabled ?? false,
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
                              value: _ctrl.trackerValueFor(a.name),
                              onToggle: (v) => _toggleAgent(a, v),
                              onEditModel: () => _editAgentModel(a),
                              onEditShard: () => _editAgentShard(a),
                              onRegenerate: () =>
                                  _regenerateAgentInstruction(a),
                              regenerating: _ctrl.regeneratingAgentIds.contains(
                                a.id,
                              ),
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
                              value: _ctrl.trackerValueFor(a.name),
                              onToggle: (v) => _toggleAgent(a, v),
                              onEditModel: () => _editAgentModel(a),
                              onEditShard: () => _editAgentShard(a),
                              onRegenerate: () =>
                                  _regenerateAgentInstruction(a),
                              regenerating: _ctrl.regeneratingAgentIds.contains(
                                a.id,
                              ),
                            ),
                          ),
                        ],
                      ],
                      const SizedBox(height: 12),
                      const _StudioTimeoutTile(),
                      const SizedBox(height: 4),
                      const _StudioMaxTokensTile(),
                      const SizedBox(height: 4),
                      const _StudioTemperatureTile(),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: _ctrl.building ? null : _buildStudio,
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
            if (_ctrl.loadingModels || _ctrl.building)
              Positioned.fill(
                child: ColoredBox(
                  color: cs.scrim.withValues(alpha: 0.4),
                  child: Center(
                    child: _ctrl.building
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
  final VoidCallback onEditShard;
  final VoidCallback onRegenerate;
  final bool regenerating;

  const _TrackerRow({
    required this.agent,
    required this.value,
    required this.onToggle,
    required this.onEditModel,
    required this.onEditShard,
    required this.onRegenerate,
    required this.regenerating,
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
      if (agent.activationKeywords.isNotEmpty)
        _StatusChip(
          label: 'kw:${agent.activationKeywords.length}',
          emphasize: true,
        ),
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
                      // Tappable prompt-shard chip — opens a multi-line
                      // editor for the tracker's promptShard (manual shard
                      // editing, Phase B).
                      _shardChip(context),
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
          // Regenerate this tracker's instruction from its source preset
          // blocks (Phase B). Spinner while the LLM build call is in flight.
          IconButton(
            onPressed: regenerating ? null : onRegenerate,
            icon: regenerating
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.refresh, size: 18, color: cs.onSurfaceVariant),
            tooltip: 'Regenerate instruction from preset',
            visualDensity: VisualDensity.compact,
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

  Widget _shardChip(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasShard = agent.promptShard.trim().isNotEmpty;
    return InkWell(
      onTap: onEditShard,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: cs.primary.withValues(alpha: 0.4),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.edit_note, size: 12, color: cs.onSurfaceVariant),
            const SizedBox(width: 3),
            Text(
              hasShard ? 'prompt' : 'add prompt',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
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

/// Idle timeout for Studio agents (pre-gen trackers + final generator).
/// Reads/writes `PipelineSettings.studioTimeoutMs`. The timer fires only
/// before the first chunk (text or reasoning) arrives — once any chunk
/// arrives it is cancelled entirely (see AgentStreamRunner).
class _StudioTimeoutTile extends ConsumerWidget {
  const _StudioTimeoutTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pipeline = ref.read(pipelineSettingsProvider);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final valueText = pipeline.studioTimeoutMs == 0
        ? 'post_building_default_seconds'.tr(namedArgs: {'arg0': '90'})
        : 'post_building_seconds_count'.tr(namedArgs: {
            'arg0': (pipeline.studioTimeoutMs / 1000).toStringAsFixed(0),
          });
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.timer_outlined, size: 20, color: cs.onSurfaceVariant),
      title: Text(
        'post_building_studio_timeout'.tr(),
        style: tt.bodyMedium,
      ),
      subtitle: Text(
        '$valueText — ${'post_building_studio_timeout_desc'.tr()}',
        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontSize: 11),
      ),
      trailing: const Icon(Icons.edit_outlined, size: 18),
      onTap: () async {
        final current = (pipeline.studioTimeoutMs / 1000).round();
        final controller = TextEditingController(text: '$current');
        final v = await showDialog<int>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text('post_building_studio_timeout'.tr()),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'post_building_seconds_min'.tr(namedArgs: {'arg0': '0'}),
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    suffixText: 'post_building_seconds_suffix'.tr(),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(c).pop(),
                child: Text('common_cancel'.tr()),
              ),
              FilledButton(
                onPressed: () {
                  final s = int.tryParse(controller.text.trim());
                  if (s == null || s < 0) {
                    Navigator.of(c).pop();
                    return;
                  }
                  Navigator.of(c).pop(s);
                },
                child: Text('common_save'.tr()),
              ),
            ],
          ),
        );
        if (v != null) {
          final updated = pipeline.copyWith(studioTimeoutMs: v * 1000);
          await ref.read(pipelineSettingsProvider.notifier).save(updated);
        }
      },
    );
  }
}

/// Max tokens override for the Studio final generator (Main Responder).
/// Reads/writes `PipelineSettings.studioFinalMaxTokens`. When 0, the
/// per-agent default (8000) is used. Useful for reasoning models that
/// spend most of the budget on thinking.
class _StudioMaxTokensTile extends ConsumerWidget {
  const _StudioMaxTokensTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pipeline = ref.read(pipelineSettingsProvider);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final value = pipeline.studioFinalMaxTokens;
    final valueText = value == 0
        ? 'post_building_default_tokens'.tr(namedArgs: {'arg0': '8000'})
        : 'post_building_tokens_count'.tr(namedArgs: {'arg0': '$value'});
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.text_snippet_outlined, size: 20, color: cs.onSurfaceVariant),
      title: Text(
        'post_building_studio_max_tokens'.tr(),
        style: tt.bodyMedium,
      ),
      subtitle: Text(
        '$valueText — ${'post_building_studio_max_tokens_desc'.tr()}',
        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontSize: 11),
      ),
      trailing: const Icon(Icons.edit_outlined, size: 18),
      onTap: () async {
        final controller = TextEditingController(text: '$value');
        final v = await showDialog<int>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text('post_building_studio_max_tokens'.tr()),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'post_building_tokens_min'.tr(namedArgs: {'arg0': '0'}),
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    suffixText: 'tokens',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(c).pop(),
                child: Text('common_cancel'.tr()),
              ),
              FilledButton(
                onPressed: () {
                  final s = int.tryParse(controller.text.trim());
                  if (s == null || s < 0) {
                    Navigator.of(c).pop();
                    return;
                  }
                  Navigator.of(c).pop(s);
                },
                child: Text('common_save'.tr()),
              ),
            ],
          ),
        );
        if (v != null) {
          final updated = pipeline.copyWith(studioFinalMaxTokens: v);
          await ref.read(pipelineSettingsProvider.notifier).save(updated);
        }
      },
    );
  }
}

/// Temperature override for the Studio final generator (Main Responder).
/// Reads/writes `PipelineSettings.studioFinalTemperature`. When negative,
/// the per-agent default (0.8) is used. Lets the user raise/lower the
/// final responder's creativity without rebuilding the Studio agents.
class _StudioTemperatureTile extends ConsumerWidget {
  const _StudioTemperatureTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pipeline = ref.read(pipelineSettingsProvider);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final value = pipeline.studioFinalTemperature;
    final valueText = value < 0
        ? 'post_building_default'.tr(namedArgs: {'arg0': '0.8'})
        : value.toStringAsFixed(2);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.thermostat_outlined, size: 20, color: cs.onSurfaceVariant),
      title: Text(
        'post_building_studio_temperature'.tr(),
        style: tt.bodyMedium,
      ),
      subtitle: Text(
        '$valueText — ${'post_building_studio_temperature_desc'.tr()}',
        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontSize: 11),
      ),
      trailing: const Icon(Icons.edit_outlined, size: 18),
      onTap: () async {
        final controller = TextEditingController(
          text: value < 0 ? '' : value.toStringAsFixed(2),
        );
        final v = await showDialog<double>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text('post_building_studio_temperature'.tr()),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'post_building_temperature_hint'.tr(),
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    suffixText: '0.0 – 2.0',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(c).pop(),
                child: Text('common_cancel'.tr()),
              ),
              FilledButton(
                onPressed: () {
                  final text = controller.text.trim();
                  if (text.isEmpty) {
                    Navigator.of(c).pop(-1.0);
                    return;
                  }
                  final s = double.tryParse(text);
                  if (s == null || s < 0 || s > 2) {
                    Navigator.of(c).pop();
                    return;
                  }
                  Navigator.of(c).pop(s);
                },
                child: Text('common_save'.tr()),
              ),
            ],
          ),
        );
        if (v != null) {
          final updated = pipeline.copyWith(studioFinalTemperature: v);
          await ref.read(pipelineSettingsProvider.notifier).save(updated);
        }
      },
    );
  }
}
