import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/studio_config.dart';
import '../../../core/models/tracker.dart';
import '../../../core/state/db_provider.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(studioConfigRepoProvider);
    final trackerRepo = ref.read(trackerRepoProvider);
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
        child: Padding(
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
                      'No trackers configured. Add agents in the Post-Building '
                      'menu under the write-loop / generation sections.',
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
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _openAdvanced,
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text('Advanced / POST-building config'),
                    ),
                  ),
                ],
              ],
            ),
          ),
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

  const _TrackerRow({
    required this.agent,
    required this.value,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final chips = <_StatusChip>[
      _StatusChip(label: 'ctx:${agent.contextSize}'),
      if (agent.runInterval != 1)
        _StatusChip(label: 'every ${agent.runInterval}'),
      if (agent.modelOverride.isNotEmpty)
        _StatusChip(label: agent.modelOverride, emphasize: true),
      if (agent.runIndividually) _StatusChip(label: 'solo', emphasize: true),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Switch(
            value: agent.enabled,
            onChanged: onToggle,
          ),
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
                if (chips.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 0,
                      children: chips
                          .map(
                            (c) => _chip(context, c.label, c.emphasize),
                          )
                          .toList(),
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
