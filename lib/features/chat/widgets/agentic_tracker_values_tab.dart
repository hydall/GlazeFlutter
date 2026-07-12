import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/tracker.dart';
import '../../../core/state/db_provider.dart';
import '../../../shared/theme/app_colors.dart';
import 'agentic_operations_log_dialog.dart' show AgenticSessionScope;

class AgenticTrackerValuesTab extends ConsumerStatefulWidget {
  const AgenticTrackerValuesTab({super.key});

  @override
  ConsumerState<AgenticTrackerValuesTab> createState() =>
      _AgenticTrackerValuesTabState();
}

class _AgenticTrackerValuesTabState
    extends ConsumerState<AgenticTrackerValuesTab> {
  List<Tracker>? _trackers;
  bool _loaded = false;
  bool _didLoad = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoad) return;
    _didLoad = true;
    _load();
  }

  Future<void> _load() async {
    final sessionId = _sessionIdOf(context);
    if (sessionId == null) {
      if (mounted) setState(() => _loaded = true);
      return;
    }
    final snapshotRepo = ref.read(trackerSnapshotRepoProvider);
    final trackerRepo = ref.read(trackerRepoProvider);
    final snapshot = await snapshotRepo.getLatest(sessionId);
    final trackers =
        snapshot?.trackers ?? await trackerRepo.getBySessionId(sessionId);
    if (!mounted) return;
    setState(() {
      _trackers = trackers;
      _loaded = true;
    });
  }

  String? _sessionIdOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AgenticSessionScope>();
    return scope?.sessionId;
  }

  Future<void> _purgeTrackers() async {
    final sessionId = _sessionIdOf(context);
    if (sessionId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Purge tracker values?'),
        content: const Text(
          'This permanently deletes all tracker rows and snapshots for this '
          'session. Use this to clear orphaned trackers left by deleted '
          'messages or a Clear chat. The action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Purge'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(trackerRepoProvider).clearForSession(sessionId);
    await ref.read(trackerSnapshotRepoProvider).deleteBySessionId(sessionId);
    if (!mounted) return;
    setState(() {
      _trackers = const <Tracker>[];
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final trackers = _trackers ?? const <Tracker>[];
    return Column(
      children: [
        if (trackers.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Text(
                  '${trackers.length} tracker${trackers.length == 1 ? '' : 's'}',
                  style: TextStyle(
                    color: context.cs.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _purgeTrackers,
                  icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                  label: const Text('Purge'),
                  style: TextButton.styleFrom(
                    foregroundColor: context.cs.error,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: trackers.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No tracker values recorded yet for this session.\n\n'
                      'Studio Ledger records accepted session state such as '
                      'scene, world, relationships, and character context. '
                      'Manual canon overrides and locks can also appear here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: context.cs.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  itemCount: trackers.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, indent: 12, endIndent: 12),
                  itemBuilder: (context, i) =>
                      _TrackerTile(tracker: trackers[i]),
                ),
        ),
      ],
    );
  }
}

class _TrackerTile extends StatelessWidget {
  final Tracker tracker;
  const _TrackerTile({required this.tracker});

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final tt = Theme.of(context).textTheme;
    final value = tracker.value.trim();
    final hasValue = value.isNotEmpty;
    return ExpansionTile(
      dense: true,
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      leading: Icon(Icons.track_changes_outlined, color: cs.primary, size: 20),
      title: Text(
        tracker.name,
        style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${tracker.scope} · ${tracker.provenance.isEmpty ? "no provenance" : tracker.provenance}',
        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontSize: 11),
      ),
      trailing: hasValue
          ? const Icon(Icons.expand_more, size: 18)
          : const Text('—', style: TextStyle(color: Colors.grey)),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasValue)
                SelectableText(
                  value,
                  style: tt.bodySmall?.copyWith(color: cs.onSurface),
                )
              else
                Text(
                  '(empty — the tracker exists but has no value yet)',
                  style: tt.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                'updatedAt: ${DateTime.fromMillisecondsSinceEpoch(tracker.updatedAt * 1000).toIso8601String()}',
                style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
