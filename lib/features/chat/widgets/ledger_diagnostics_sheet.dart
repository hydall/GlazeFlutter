import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/llm/aux_llm_client.dart' show AuxApiConfig;
import '../../../core/llm/studio_ledger_service.dart';
import '../../../core/llm/studio_slot_resolver.dart';
import '../../../core/models/api_config.dart';
import '../../settings/api_list_provider.dart';
import '../../../core/db/repositories/tracker_repo.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/tracker.dart';
import '../../../core/state/db_provider.dart';
import '../../../core/state/memory_agent_providers.dart';

/// Diagnostics sheet for Studio Ledger committed canon state.
///
/// Shows tracker rows written by [StudioLedgerService] grouped by namespace:
///   - npc:*   — entity state
///   - relationship:* — relationship state
///   - arc:*   — arc/story state
///   - world:* — world state
///   - scene.* — scene state
///   - canon_override:* — user manual overrides
///   - canon_lock:*     — user locks (prevent ledger writes)
///   - _ledger:*        — raw visible ledger diagnostic blobs
///   - _ledger_diag:*   — last run/skip reason per component
///
/// Each row supports:
///   - edit value (inline)
///   - lock (creates `canon_lock:<key>=true`)
///   - unlock (removes `canon_lock:<key>`)
///   - override (creates `canon_override:<key>`)
///   - reset (removes `canon_override:<key>` only)
///   - delete
///   - source-message navigation (when [onScrollToMessage] is provided)
///
/// Ledger diagnostics bottom sheet showing tracker/canon state.
class LedgerDiagnosticsSheet extends ConsumerStatefulWidget {
  final String sessionId;
  final Future<void> Function(String messageId)? onScrollToMessage;

  const LedgerDiagnosticsSheet({
    super.key,
    required this.sessionId,
    this.onScrollToMessage,
  });

  static Future<void> show(
    BuildContext context, {
    required String sessionId,
    Future<void> Function(String messageId)? onScrollToMessage,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => LedgerDiagnosticsSheet(
        sessionId: sessionId,
        onScrollToMessage: onScrollToMessage,
      ),
    );
  }

  @override
  ConsumerState<LedgerDiagnosticsSheet> createState() =>
      _LedgerDiagnosticsSheetState();
}

class _LedgerDiagnosticsSheetState
    extends ConsumerState<LedgerDiagnosticsSheet> {
  List<Tracker>? _rows;
  bool _loading = true;
  bool _rerunning = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(trackerRepoProvider);
    final all = await repo.getBySessionId(widget.sessionId);
    final ledger =
        all
            .where(
              (t) =>
                  t.scope == 'ledger' ||
                  t.scope == 'ledger_diagnostic' ||
                  t.name.startsWith('canon_override:') ||
                  t.name.startsWith('canon_lock:'),
            )
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    if (mounted) {
      setState(() {
        _rows = ledger;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.3,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.menu_book_outlined, color: cs.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Studio Ledger State',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: _rerunning
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(
                            Icons.replay_circle_filled_outlined,
                            size: 20,
                          ),
                    onPressed: _rerunning ? null : _rerunLastLedger,
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Regenerate Ledger for latest assistant turn',
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: () {
                      setState(() => _loading = true);
                      _load();
                    },
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Reload',
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _rows == null || _rows!.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.inbox_outlined,
                            size: 40,
                            color: cs.onSurfaceVariant,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No ledger state yet.\nEnable Studio Ledger and send a message.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    )
                  : _LedgerRowList(
                      rows: _rows!,
                      scrollController: scrollController,
                      onDeleted: _load,
                      sessionId: widget.sessionId,
                      onScrollToMessage: widget.onScrollToMessage,
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _rerunLastLedger() async {
    if (_rerunning) return;
    setState(() => _rerunning = true);

    ChatMessage? target;
    try {
      final session = await ref
          .read(chatRepoProvider)
          .getById(widget.sessionId);
      if (session == null) {
        throw StateError('Session not found');
      }
      final messages = session.messages;
      for (var i = messages.length - 1; i >= 0; i--) {
        final m = messages[i];
        if (m.role == 'assistant' &&
            !m.isError &&
            !m.isTyping &&
            m.content.trim().isNotEmpty) {
          target = m;
          break;
        }
      }
      if (target == null) {
        throw StateError('No assistant message found');
      }

      final pipeline = ref.read(pipelineSettingsProvider);
      final studioConfig = await ref
          .read(studioConfigRepoProvider)
          .getBySessionId(widget.sessionId);
      if (!mounted) return;
      await ref.read(apiListProvider.future);
      final apiConfigs =
          ref.read(apiListProvider).value ?? const <ApiConfig>[];
      final AuxApiConfig ledgerConfig;
      try {
        ledgerConfig = StudioSlotResolver.resolveFromList(
          apiConfigs: apiConfigs,
          apiConfigId: studioConfig?.cleanerApiConfigId ?? '',
          errorLabel: 'ledger-rerun',
          modelOverride: pipeline.cleaner.postCleanerModel,
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Studio Ledger rerun failed: $e')),
          );
        }
        return;
      }
      if (!mounted) return;
      final recentHistory = _recentHistoryText(
        messages,
        maxMessages: 10,
        upToMessageId: target.id,
      );
      final result = await ref
          .read(studioLedgerServiceProvider)
          .run(
            sessionId: widget.sessionId,
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

      await ref
          .read(trackerRepoProvider)
          .upsertValue(
            widget.sessionId,
            '_ledger_diag:studio_ledger',
            'turn=${target.id} • manual rerun, ${result.status} '
                '(ops=${result.opsApplied}, facts=${result.durableFactsWritten})'
                '${result.error == null ? '' : ': ${result.error}'}',
            scope: 'ledger_diagnostic',
            provenance:
                'message=${target.id}|swipe=${target.swipeId}|'
                'agentSwipe=${target.agentSwipeId}|manual=1',
          );
    } catch (e) {
      if (target != null) {
        await ref
            .read(trackerRepoProvider)
            .upsertValue(
              widget.sessionId,
              '_ledger_diag:studio_ledger',
              'turn=${target.id} • manual rerun, trigger error: $e',
              scope: 'ledger_diagnostic',
              provenance:
                  'message=${target.id}|swipe=${target.swipeId}|'
                  'agentSwipe=${target.agentSwipeId}|manual=1',
            );
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ledger rerun failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _rerunning = false);
        await _load();
      }
    }
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

class _LedgerRowList extends ConsumerWidget {
  final List<Tracker> rows;
  final ScrollController scrollController;
  final VoidCallback onDeleted;
  final String sessionId;
  final Future<void> Function(String messageId)? onScrollToMessage;

  const _LedgerRowList({
    required this.rows,
    required this.scrollController,
    required this.onDeleted,
    required this.sessionId,
    this.onScrollToMessage,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diag = rows.where((t) => t.name.startsWith('_ledger_diag:')).toList();
    final npc = rows.where((t) => t.name.startsWith('npc:')).toList();
    final rel = rows.where((t) => t.name.startsWith('relationship:')).toList();
    final arc = rows.where((t) => t.name.startsWith('arc:')).toList();
    final world = rows.where((t) => t.name.startsWith('world:')).toList();
    final scene = rows.where((t) => t.name.startsWith('scene.')).toList();
    final overrides = rows
        .where((t) => t.name.startsWith('canon_override:'))
        .toList();
    final locks = rows.where((t) => t.name.startsWith('canon_lock:')).toList();
    final diagBlob = rows.where((t) => t.name.startsWith('_ledger:')).toList();

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (diag.isNotEmpty) ...[
          _sectionHeader(
            context,
            Icons.history_outlined,
            'Run / Skip Diagnostics',
          ),
          ...diag.map(
            (t) => _DiagTile(t: t, onScrollToMessage: onScrollToMessage),
          ),
        ],
        if (npc.isNotEmpty) ...[
          _sectionHeader(context, Icons.person_outline, 'Entity State (NPC)'),
          ...npc.map(
            (t) => _TrackerTile(
              t: t,
              sessionId: sessionId,
              onDeleted: onDeleted,
              locks: locks,
              overrides: overrides,
              onScrollToMessage: onScrollToMessage,
            ),
          ),
        ],
        if (rel.isNotEmpty) ...[
          _sectionHeader(context, Icons.people_outline, 'Relationship State'),
          ...rel.map(
            (t) => _TrackerTile(
              t: t,
              sessionId: sessionId,
              onDeleted: onDeleted,
              locks: locks,
              overrides: overrides,
              onScrollToMessage: onScrollToMessage,
            ),
          ),
        ],
        if (arc.isNotEmpty) ...[
          _sectionHeader(context, Icons.timeline_outlined, 'Arc State'),
          ...arc.map(
            (t) => _TrackerTile(
              t: t,
              sessionId: sessionId,
              onDeleted: onDeleted,
              locks: locks,
              overrides: overrides,
              onScrollToMessage: onScrollToMessage,
            ),
          ),
        ],
        if (world.isNotEmpty) ...[
          _sectionHeader(context, Icons.public_outlined, 'World State'),
          ...world.map(
            (t) => _TrackerTile(
              t: t,
              sessionId: sessionId,
              onDeleted: onDeleted,
              locks: locks,
              overrides: overrides,
              onScrollToMessage: onScrollToMessage,
            ),
          ),
        ],
        if (scene.isNotEmpty) ...[
          _sectionHeader(context, Icons.theaters_outlined, 'Scene State'),
          ...scene.map(
            (t) => _TrackerTile(
              t: t,
              sessionId: sessionId,
              onDeleted: onDeleted,
              locks: locks,
              overrides: overrides,
              onScrollToMessage: onScrollToMessage,
            ),
          ),
        ],
        if (overrides.isNotEmpty) ...[
          _sectionHeader(context, Icons.edit_outlined, 'Manual Overrides'),
          ...overrides.map(
            (t) => _TrackerTile(
              t: t,
              sessionId: sessionId,
              onDeleted: onDeleted,
              locks: locks,
              overrides: overrides,
              accent: Colors.orange,
              onScrollToMessage: onScrollToMessage,
            ),
          ),
        ],
        if (locks.isNotEmpty) ...[
          _sectionHeader(context, Icons.lock_outline, 'Locked Keys'),
          ...locks.map(
            (t) => _TrackerTile(
              t: t,
              sessionId: sessionId,
              onDeleted: onDeleted,
              locks: locks,
              overrides: overrides,
              accent: Colors.red,
            ),
          ),
        ],
        if (diagBlob.isNotEmpty) ...[
          _sectionHeader(
            context,
            Icons.biotech_outlined,
            'Raw Visible Ledger (Diagnostic)',
          ),
          ...diagBlob.map(
            (t) => _TrackerTile(
              t: t,
              sessionId: sessionId,
              onDeleted: onDeleted,
              locks: locks,
              overrides: overrides,
              isLongValue: true,
              onScrollToMessage: onScrollToMessage,
            ),
          ),
        ],
      ],
    );
  }

  Widget _sectionHeader(BuildContext ctx, IconData icon, String label) {
    final cs = Theme.of(ctx).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: cs.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: cs.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackerTile extends ConsumerStatefulWidget {
  final Tracker t;
  final String sessionId;
  final VoidCallback onDeleted;
  final List<Tracker> locks;
  final List<Tracker> overrides;
  final Color? accent;
  final bool isLongValue;
  final Future<void> Function(String messageId)? onScrollToMessage;

  const _TrackerTile({
    required this.t,
    required this.sessionId,
    required this.onDeleted,
    required this.locks,
    required this.overrides,
    this.accent,
    this.isLongValue = false,
    this.onScrollToMessage,
  });

  @override
  ConsumerState<_TrackerTile> createState() => _TrackerTileState();
}

class _TrackerTileState extends ConsumerState<_TrackerTile> {
  bool get _isCanonLock => widget.t.name.startsWith('canon_lock:');
  bool get _isCanonOverride => widget.t.name.startsWith('canon_override:');

  bool get _isLocked =>
      widget.locks.any((l) => l.name == 'canon_lock:${widget.t.name}');

  String? get _messageIdFromProvenance {
    final match = RegExp(r'message=([^|]+)').firstMatch(widget.t.provenance);
    return match?.group(1);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectiveAccent = widget.accent ?? cs.onSurfaceVariant;
    final repo = ref.read(trackerRepoProvider);

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      title: Text(
        widget.t.name,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: effectiveAccent,
          fontFamily: 'monospace',
        ),
      ),
      subtitle: _TrackerValue(t: widget.t, isLongValue: widget.isLongValue),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Edit (only for canon rows, not for lock/override rows)
          if (!_isCanonLock && !_isCanonOverride)
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 16),
              visualDensity: VisualDensity.compact,
              tooltip: 'Edit value',
              onPressed: () => _editValue(context, repo),
            ),
          // Lock/unlock (only for canon rows)
          if (!_isCanonLock && !_isCanonOverride)
            IconButton(
              icon: Icon(
                _isLocked ? Icons.lock : Icons.lock_open_outlined,
                size: 16,
                color: _isLocked ? Colors.red : null,
              ),
              visualDensity: VisualDensity.compact,
              tooltip: _isLocked ? 'Unlock' : 'Lock (prevent ledger writes)',
              onPressed: () async {
                final lockKey = 'canon_lock:${widget.t.name}';
                if (_isLocked) {
                  await repo.delete(widget.sessionId, lockKey);
                } else {
                  await repo.upsertValue(
                    widget.sessionId,
                    lockKey,
                    'true',
                    scope: 'ledger',
                  );
                }
                widget.onDeleted();
              },
            ),
          // Override (only for canon rows, not for override rows)
          if (!_isCanonLock && !_isCanonOverride)
            IconButton(
              icon: const Icon(
                Icons.edit_outlined,
                size: 16,
                color: Colors.orange,
              ),
              visualDensity: VisualDensity.compact,
              tooltip: 'Create manual override',
              onPressed: () => _createOverride(context, repo),
            ),
          // Reset (only for override rows) — removes the override
          if (_isCanonOverride)
            IconButton(
              icon: const Icon(
                Icons.restart_alt,
                size: 16,
                color: Colors.orange,
              ),
              visualDensity: VisualDensity.compact,
              tooltip: 'Reset (remove override)',
              onPressed: () async {
                await repo.delete(widget.sessionId, widget.t.name);
                widget.onDeleted();
              },
            ),
          // Source-message navigation
          if (widget.onScrollToMessage != null &&
              _messageIdFromProvenance != null)
            IconButton(
              icon: const Icon(Icons.location_on_outlined, size: 16),
              visualDensity: VisualDensity.compact,
              tooltip: 'Go to source message',
              onPressed: () async {
                final msgId = _messageIdFromProvenance;
                if (msgId != null) {
                  await widget.onScrollToMessage!(msgId);
                }
              },
            ),
          // Copy
          IconButton(
            icon: const Icon(Icons.copy, size: 16),
            visualDensity: VisualDensity.compact,
            tooltip: 'Copy value',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: widget.t.value));
            },
          ),
          // Delete
          IconButton(
            icon: Icon(Icons.delete_outline, size: 16, color: cs.error),
            visualDensity: VisualDensity.compact,
            tooltip: 'Delete row',
            onPressed: () async {
              await repo.delete(widget.sessionId, widget.t.name);
              widget.onDeleted();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _editValue(BuildContext context, TrackerRepo repo) async {
    final controller = TextEditingController(text: widget.t.value);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.t.name, style: const TextStyle(fontSize: 13)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 8,
          minLines: 2,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Value',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null) {
      final trimmed = result.trim();
      if (trimmed.isEmpty) {
        await repo.delete(widget.sessionId, widget.t.name);
      } else {
        await repo.upsertValue(
          widget.sessionId,
          widget.t.name,
          trimmed,
          scope: 'ledger',
        );
      }
      widget.onDeleted();
    }
  }

  Future<void> _createOverride(BuildContext context, TrackerRepo repo) async {
    final controller = TextEditingController(text: widget.t.value);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Override: ${widget.t.name}',
          style: const TextStyle(fontSize: 13),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Manual override value outranks the model-written ledger value. '
              'The model cannot overwrite it. Reset removes the override.',
              style: TextStyle(fontSize: 11),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 8,
              minLines: 2,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Override value',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null) {
      final trimmed = result.trim();
      if (trimmed.isNotEmpty) {
        await repo.upsertValue(
          widget.sessionId,
          'canon_override:${widget.t.name}',
          trimmed,
          scope: 'ledger',
        );
        widget.onDeleted();
      }
    }
  }
}

class _TrackerValue extends StatelessWidget {
  final Tracker t;
  final bool isLongValue;

  const _TrackerValue({required this.t, this.isLongValue = false});

  @override
  Widget build(BuildContext context) {
    final value = isLongValue && t.value.length > 200
        ? '${t.value.substring(0, 200)}…  (tap to expand)'
        : t.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: TextStyle(fontSize: isLongValue ? 11 : 12)),
        if (t.provenance.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            t.provenance,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ],
    );
  }
}

class _DiagTile extends ConsumerWidget {
  final Tracker t;
  final Future<void> Function(String messageId)? onScrollToMessage;

  const _DiagTile({required this.t, this.onScrollToMessage});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final value = t.value;
    final isRan = value.startsWith('ran,');
    final isSkipped = value.startsWith('skipped,');
    final icon = isRan
        ? Icons.check_circle_outline
        : isSkipped
        ? Icons.skip_next_outlined
        : Icons.info_outline;
    final color = isRan
        ? cs.primary
        : isSkipped
        ? cs.onSurfaceVariant
        : cs.tertiary;

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Icon(icon, size: 18, color: color),
      title: Text(
        t.name,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          fontFamily: 'monospace',
        ),
      ),
      subtitle: Text(
        value,
        style: TextStyle(
          fontSize: 11,
          color: isRan ? cs.primary : cs.onSurfaceVariant,
        ),
      ),
      trailing:
          onScrollToMessage != null &&
              _messageIdFromProvenance(t.provenance) != null
          ? IconButton(
              icon: const Icon(Icons.location_on_outlined, size: 16),
              tooltip: 'Go to source message',
              visualDensity: VisualDensity.compact,
              onPressed: () async {
                final msgId = _messageIdFromProvenance(t.provenance);
                if (msgId != null) {
                  await onScrollToMessage!(msgId);
                }
              },
            )
          : null,
    );
  }

  String? _messageIdFromProvenance(String provenance) {
    final match = RegExp(r'message=([^|]+)').firstMatch(provenance);
    return match?.group(1);
  }
}
