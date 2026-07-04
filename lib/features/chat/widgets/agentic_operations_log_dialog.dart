import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/llm/aux_llm_client.dart' show AuxApiConfig;
import '../../../core/llm/studio_ledger_service.dart';
import '../../../core/llm/studio_slot_resolver.dart';
import '../../../core/models/api_config.dart';
import '../../settings/api_list_provider.dart';
import '../../../core/models/agent_operation_record.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/tracker.dart';
import '../../../core/state/db_provider.dart';
import '../../../core/state/memory_agent_providers.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/glaze_toast.dart';
import '../state/agent_operations_log_provider.dart';
import 'post_cleaner_diff_dialog.dart';

enum _LogFilter { all, failed, success }

class AgenticOperationsLogDialog extends ConsumerStatefulWidget {
  final String? sessionId;

  const AgenticOperationsLogDialog({super.key, this.sessionId});

  /// Opens the dialog as an overlay. Caller passes the current [sessionId]
  /// so the dialog can scope the list, or null to show operations across all
  /// sessions.
  static Future<void> show(BuildContext context, {String? sessionId}) {
    return showDialog(
      context: context,
      builder: (_) => AgenticOperationsLogDialog(sessionId: sessionId),
    );
  }

  @override
  ConsumerState<AgenticOperationsLogDialog> createState() =>
      _AgenticOperationsLogDialogState();
}

class _AgenticOperationsLogDialogState
    extends ConsumerState<AgenticOperationsLogDialog> {
  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 720,
        height: 560,
        child: DefaultTabController(
          length: 3,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.smart_toy_outlined, color: context.cs.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Agentic Operations Log',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, size: 20),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
              const TabBar(
                tabs: [
                  Tab(
                    icon: Icon(Icons.history_outlined, size: 16),
                    text: 'Operations',
                  ),
                  Tab(
                    icon: Icon(Icons.track_changes_outlined, size: 16),
                    text: 'Tracker values',
                  ),
                  Tab(
                    icon: Icon(Icons.warning_amber_outlined, size: 16),
                    text: 'Last turn',
                  ),
                ],
                tabAlignment: TabAlignment.fill,
              ),
              Expanded(
                child: _SessionScope(
                  sessionId: widget.sessionId,
                  child: const TabBarView(
                    children: [
                      _OperationsTab(),
                      _TrackerValuesTab(),
                      _LastTurnTab(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OperationsTab extends ConsumerStatefulWidget {
  const _OperationsTab();

  @override
  ConsumerState<_OperationsTab> createState() => _OperationsTabState();
}

class _OperationsTabState extends ConsumerState<_OperationsTab> {
  _LogFilter _filter = _LogFilter.all;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentOperationsLogProvider);
    // The parent dialog passes the sessionId via a route arg we don't have
    // here — pull it from the closest AgenticOperationsLogDialog ancestor.
    // For the simple two-tab layout we instead rely on the parent's
    // `widget.sessionId` via a shared `InheritedWidget` is overkill; the
    // simplest correct fix is to read the global state and filter by the
    // dialog's sessionId through a `_SessionScope` passed via constructor.
    // We do that here:
    final sessionId = _sessionIdOf(context);
    final allRecords = state.forSession(sessionId);
    final filtered = switch (_filter) {
      _LogFilter.all => allRecords,
      _LogFilter.failed => allRecords.where((r) => r.status.isFailure).toList(),
      _LogFilter.success => allRecords.where((r) => r.status.isOk).toList(),
    };
    filtered.sort((a, b) => b.finishedAtMs.compareTo(a.finishedAtMs));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              SegmentedButton<_LogFilter>(
                segments: const [
                  ButtonSegment(value: _LogFilter.all, label: Text('All')),
                  ButtonSegment(
                    value: _LogFilter.failed,
                    label: Text('Failed'),
                    icon: Icon(Icons.error_outline, size: 16),
                  ),
                  ButtonSegment(
                    value: _LogFilter.success,
                    label: Text('Success'),
                    icon: Icon(Icons.check_circle_outline, size: 16),
                  ),
                ],
                selected: {_filter},
                onSelectionChanged: (s) => setState(() => _filter = s.first),
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
              ),
              const SizedBox(width: 8),
              Text(
                '${filtered.length} ops',
                style: TextStyle(
                  fontSize: 11,
                  color: context.cs.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              if (state.records.isNotEmpty)
                IconButton(
                  onPressed: () => _confirmClear(context),
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  tooltip: 'Clear log',
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No agentic operations recorded yet.\n\n'
                      'Operations appear here when the POST-cleaner, Studio '
                      'Ledger, tracker agents, or agentic memory search/write '
                      'tools are invoked during generation.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: context.cs.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, indent: 12, endIndent: 12),
                  itemBuilder: (context, i) =>
                      _OperationTile(record: filtered[i]),
                ),
        ),
      ],
    );
  }

  /// Read the dialog's `sessionId` from the nearest ancestor. We use a
  /// small `_SessionScope` inherited widget set by the dialog's state — see
  /// the build method's wrapper in [_AgenticOperationsLogDialogState].
  String? _sessionIdOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_SessionScope>();
    return scope?.sessionId;
  }

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear operations log?'),
        content: const Text(
          'This removes all recorded agentic operations from memory. '
          'The chat itself is not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(agentOperationsLogProvider.notifier).state =
          const AgentOperationsLogState();
    }
  }
}

class _LastTurnTab extends ConsumerStatefulWidget {
  const _LastTurnTab();

  @override
  ConsumerState<_LastTurnTab> createState() => _LastTurnTabState();
}

class _LastTurnTabState extends ConsumerState<_LastTurnTab> {
  bool _runningLedger = false;

  @override
  Widget build(BuildContext context) {
    final sessionId = _sessionIdOf(context);
    if (sessionId == null) {
      return Center(
        child: Text(
          'Open Agentic Ops from a chat to inspect the last turn.',
          style: TextStyle(color: context.cs.onSurfaceVariant, fontSize: 12),
        ),
      );
    }
    final state = ref.watch(agentOperationsLogProvider);
    return FutureBuilder<ChatMessage?>(
      future: _latestAssistant(sessionId),
      builder: (context, snapshot) {
        final last = snapshot.data;
        final records = last == null
            ? <AgentOperationRecord>[]
            : state
                  .forSession(sessionId)
                  .where((r) => r.messageId == last.id)
                  .toList();
        records.sort((a, b) => a.startedAtMs.compareTo(b.startedAtMs));
        final failed = records.where((r) => r.status.isFailure).toList();

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      last == null
                          ? 'No assistant turn found.'
                          : 'Latest assistant turn: ${last.id}',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.cs.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: last == null || _runningLedger
                        ? null
                        : () => _rerunLedger(sessionId, last),
                    icon: _runningLedger
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.replay_outlined, size: 16),
                    label: const Text('Rerun Studio Ledger'),
                  ),
                ],
              ),
            ),
            if (failed.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${failed.length} failed operation(s) on this turn',
                    style: TextStyle(fontSize: 11, color: context.cs.error),
                  ),
                ),
              ),
            Expanded(
              child: records.isEmpty
                  ? Center(
                      child: Text(
                        'No operations recorded for the latest turn yet.',
                        style: TextStyle(
                          color: context.cs.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: records.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, indent: 12, endIndent: 12),
                      itemBuilder: (context, i) =>
                          _OperationTile(record: records[i]),
                    ),
            ),
          ],
        );
      },
    );
  }

  String? _sessionIdOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_SessionScope>();
    return scope?.sessionId;
  }

  Future<ChatMessage?> _latestAssistant(String sessionId) async {
    final session = await ref.read(chatRepoProvider).getById(sessionId);
    final messages = session?.messages ?? const <ChatMessage>[];
    for (var i = messages.length - 1; i >= 0; i--) {
      final m = messages[i];
      if (m.role == 'assistant' &&
          !m.isError &&
          !m.isTyping &&
          m.content.trim().isNotEmpty) {
        return m;
      }
    }
    return null;
  }

  Future<void> _rerunLedger(String sessionId, ChatMessage target) async {
    if (_runningLedger) return;
    setState(() => _runningLedger = true);
    try {
      final session = await ref.read(chatRepoProvider).getById(sessionId);
      if (!mounted) return;
      if (session == null) throw StateError('Session not found');
      final studioConfig = await ref
          .read(studioConfigRepoProvider)
          .getBySessionId(sessionId);
      if (!mounted) return;
      final recentHistory = _recentHistoryText(
        session.messages,
        maxMessages: 10,
        upToMessageId: target.id,
      );
      final startedAt = DateTime.now().millisecondsSinceEpoch;
      final pipeline = ref.read(pipelineSettingsProvider);
      await ref.read(apiListProvider.future);
      final apiConfigs =
          ref.read(apiListProvider).value ?? const <ApiConfig>[];
      final AuxApiConfig ledgerConfig;
      try {
        ledgerConfig = StudioSlotResolver.resolve(
          apiConfigs: apiConfigs,
          apiConfigId: studioConfig?.cleanerApiConfigId ?? '',
          errorLabel: 'ledger-rerun',
          modelOverride: pipeline.cleaner.postCleanerModel,
        );
      } catch (e) {
        if (mounted) {
          GlazeToast.showWithoutContext(
            'Studio Ledger rerun failed: $e',
            duration: 4000,
            isError: true,
          );
        }
        return;
      }
      if (!mounted) return;
      final result = await ref
          .read(studioLedgerServiceProvider)
          .run(
            sessionId: sessionId,
            settings: pipeline,
            config: ledgerConfig,
            finalAssistantText: target.content,
            recentHistoryText: recentHistory,
            messageId: target.id,
            swipeId: target.swipeId,
            agentSwipeId: target.agentSwipeId,
            forceEnabled: true,
            isStillCurrent: () => mounted,
          );
      if (!mounted) return;
      await ref
          .read(trackerRepoProvider)
          .upsertValue(
            sessionId,
            '_ledger_diag:studio_ledger',
            'turn=${target.id} • manual rerun, ${result.status} '
                '(ops=${result.opsApplied}, facts=${result.durableFactsWritten})'
                '${result.error == null ? '' : ': ${result.error}'}',
            scope: 'ledger_diagnostic',
            provenance:
                'message=${target.id}|swipe=${target.swipeId}|'
                'agentSwipe=${target.agentSwipeId}|manual=1',
          );
      if (!mounted) return;
      _appendLedgerRecord(sessionId, target, result, startedAt);
      if (mounted) {
        GlazeToast.show(
          context,
          result.status == 'ok'
              ? 'Studio Ledger rerun ok: ops=${result.opsApplied}, facts=${result.durableFactsWritten}'
              : 'Studio Ledger rerun failed: ${result.error ?? result.status}',
          isError: result.status != 'ok',
          duration: 4000,
          position: ToastPosition.top,
        );
      }
    } catch (e) {
      if (!mounted) return;
      final result = LedgerRunResult(status: 'error', error: '$e');
      _appendLedgerRecord(
        sessionId,
        target,
        result,
        DateTime.now().millisecondsSinceEpoch,
      );
      if (mounted) {
        GlazeToast.show(
          context,
          'Studio Ledger rerun failed: $e',
          isError: true,
          duration: 4000,
          position: ToastPosition.top,
        );
      }
    } finally {
      if (mounted) setState(() => _runningLedger = false);
    }
  }

  void _appendLedgerRecord(
    String sessionId,
    ChatMessage target,
    LedgerRunResult result,
    int fallbackStartedAt,
  ) {
    if (!mounted) return;
    final status = _ledgerStatusToOp(result.status);
    final now = DateTime.now().millisecondsSinceEpoch;
    ref.read(agentOperationsLogProvider.notifier).state = ref
        .read(agentOperationsLogProvider)
        .append(
          AgentOperationRecord(
            id: 'studio-ledger-manual-${target.id}-${DateTime.now().microsecondsSinceEpoch}',
            kind: AgentOperationKind.studioLedger,
            status: status,
            sessionId: sessionId,
            messageId: target.id,
            attempts: result.attempts,
            totalElapsedMs: result.elapsedMs,
            model: result.model,
            summary: status.isOk
                ? 'manual rerun: ops=${result.opsApplied}, facts=${result.durableFactsWritten}'
                : result.error ?? result.status,
            startedAtMs: result.attempts.isNotEmpty
                ? result.attempts.first.startedAtMs
                : fallbackStartedAt,
            finishedAtMs: result.attempts.isNotEmpty
                ? result.attempts.last.startedAtMs +
                      result.attempts.last.elapsedMs
                : now,
            canRegenerate: status.isFailure,
          ),
        );
  }
}

String _recentHistoryText(
  List<ChatMessage> messages, {
  int maxMessages = 10,
  String? upToMessageId,
}) {
  var source = messages;
  if (upToMessageId != null) {
    final idx = messages.indexWhere((m) => m.id == upToMessageId);
    if (idx >= 0) source = messages.sublist(0, idx + 1);
  }
  final start = source.length > maxMessages ? source.length - maxMessages : 0;
  final lines = <String>[];
  for (final msg in source.sublist(start)) {
    if (msg.isError || msg.isTyping) continue;
    final content = msg.content.trim();
    if (content.isEmpty) continue;
    final role = msg.role == 'assistant' ? 'Assistant' : 'User';
    lines.add('$role: $content');
  }
  return lines.join('\n\n');
}

AgentOperationStatus _ledgerStatusToOp(String status) {
  return switch (status) {
    'ok' => AgentOperationStatus.ok,
    'skipped' => AgentOperationStatus.disabled,
    'disabled' => AgentOperationStatus.disabled,
    'aborted' => AgentOperationStatus.aborted,
    'timeout' => AgentOperationStatus.timeout,
    'error' => AgentOperationStatus.error,
    _ => AgentOperationStatus.error,
  };
}

/// Phase 7.5 — "Tracker values" tab. Lists the live [Tracker] store for the
/// dialog's session, showing name / scope / value / provenance / updatedAt.
/// Lets the user see what the trackers (memory tracker + post-turn
/// write-loop) have written to the persistent tracker table — separate from
/// the operations log (which shows *what ran*) and from the MemoryBook
/// (which shows *what was remembered long-term*).
class _TrackerValuesTab extends ConsumerStatefulWidget {
  const _TrackerValuesTab();

  @override
  ConsumerState<_TrackerValuesTab> createState() => _TrackerValuesTabState();
}

class _TrackerValuesTabState extends ConsumerState<_TrackerValuesTab> {
  List<Tracker>? _trackers;
  bool _loaded = false;
  bool _didLoad = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Read the inherited `_SessionScope` here (NOT in initState — inherited
    // widgets are not safe to depend on before the first didChangeDependencies).
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
    final scope = context.dependOnInheritedWidgetOfExactType<_SessionScope>();
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
                      'Trackers are written by the post-turn write-loop and the '
                      'memory tracker. They hold lightweight state (scene, '
                      'weather, relationship, ...) injected into later prompts '
                      'via macros.',
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

/// Small inherited widget that exposes the dialog's `sessionId` to the
/// two tabs without having to plumb it through constructors (the tabs are
/// built inside a `TabBarView` whose `DefaultTabController` is stateless).
class _SessionScope extends InheritedWidget {
  final String? sessionId;
  const _SessionScope({this.sessionId, required super.child});

  @override
  bool updateShouldNotify(_SessionScope oldWidget) =>
      oldWidget.sessionId != sessionId;
}

class _OperationTile extends StatelessWidget {
  final AgentOperationRecord record;

  const _OperationTile({required this.record});

  bool get _canShowDiff =>
      record.kind == AgentOperationKind.postCleaner &&
      record.status.isOk &&
      record.sessionId != null &&
      record.messageId != null;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(context, record.status);
    return ExpansionTile(
      dense: true,
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      leading: Icon(_kindIcon(record.kind), color: color, size: 20),
      title: Text(
        record.tileLabel,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: context.cs.onSurface,
        ),
      ),
      subtitle: record.summary == null
          ? null
          : Text(
              record.summary!,
              style: TextStyle(
                fontSize: 11,
                color: context.cs.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_canShowDiff)
            IconButton(
              onPressed: () => PostCleanerDiffDialog.show(
                context,
                sessionId: record.sessionId!,
                messageId: record.messageId!,
              ),
              icon: const Icon(Icons.compare_arrows, size: 18),
              tooltip: 'View diff',
              visualDensity: VisualDensity.compact,
            ),
          if (record.canRegenerate)
            IconButton(
              onPressed: () => _showRegenHint(context),
              icon: const Icon(Icons.refresh, size: 18),
              tooltip: 'Regenerate (next turn)',
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow(context, 'Kind', record.kind.label),
              _detailRow(context, 'Status', record.status.label),
              _detailRow(
                context,
                'Attempts',
                '${record.attemptCount}${record.wasRetried ? " (retried)" : ""}',
              ),
              _detailRow(context, 'Total time', '${record.totalElapsedMs}ms'),
              if (record.model != null)
                _detailRow(context, 'Model', record.model!),
              if (record.messageId != null)
                _detailRow(context, 'Message', record.messageId!),
              if (record.attempts.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Attempts:',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: context.cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                ...record.attempts.map(
                  (a) => Padding(
                    padding: const EdgeInsets.only(left: 8, bottom: 2),
                    child: Row(
                      children: [
                        Icon(
                          a.isSuccess ? Icons.check : Icons.error_outline,
                          size: 14,
                          color: a.isSuccess
                              ? context.cs.primary
                              : _attemptColor(context, a.status),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '#${a.attempt} · ${a.status}'
                          '${a.statusCode != 0 ? " · HTTP ${a.statusCode}" : ""}'
                          ' · ${a.elapsedMs}ms',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.cs.onSurface,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _detailRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: context.cs.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 11, color: context.cs.onSurface),
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(BuildContext context, AgentOperationStatus status) {
    if (status.isOk) return context.cs.primary;
    if (status.isFailure) return context.cs.error;
    return context.cs.onSurfaceVariant;
  }

  Color _attemptColor(BuildContext context, String status) {
    if (status == 'http_5xx' || status == 'timeout') return context.cs.error;
    if (status == 'http_4xx') return Colors.orange;
    return context.cs.onSurfaceVariant;
  }

  IconData _kindIcon(AgentOperationKind kind) {
    return switch (kind) {
      AgentOperationKind.memorySidecar => Icons.memory,
      AgentOperationKind.postCleaner => Icons.cleaning_services_outlined,
      AgentOperationKind.agenticSearch => Icons.search,
      AgentOperationKind.agenticWrite => Icons.edit_note,
      AgentOperationKind.classifier => Icons.category_outlined,
      AgentOperationKind.consolidation => Icons.merge_type_outlined,
      AgentOperationKind.studioTracker => Icons.auto_awesome_outlined,
      AgentOperationKind.studioFinal => Icons.edit_note,
      AgentOperationKind.factChecker => Icons.fact_check_outlined,
      AgentOperationKind.studioLedger => Icons.menu_book_outlined,
    };
  }

  void _showRegenHint(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'This operation will be retried automatically on the next '
          'generation that triggers it.',
        ),
        duration: Duration(seconds: 3),
      ),
    );
  }
}
