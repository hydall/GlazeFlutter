import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/tracker.dart';
import '../../../core/state/db_provider.dart';

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
///
/// Opened from [StudioMenuDialog] via the "Ledger State" button.
class LedgerDiagnosticsSheet extends ConsumerStatefulWidget {
  final String sessionId;

  const LedgerDiagnosticsSheet({super.key, required this.sessionId});

  static Future<void> show(BuildContext context, {required String sessionId}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => LedgerDiagnosticsSheet(sessionId: sessionId),
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(trackerRepoProvider);
    final all = await repo.getBySessionId(widget.sessionId);
    // Only show ledger-scoped rows.
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
            // Handle bar
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
            // Header
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
            // Body
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
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _LedgerRowList extends ConsumerWidget {
  final List<Tracker> rows;
  final ScrollController scrollController;
  final VoidCallback onDeleted;
  final String sessionId;

  const _LedgerRowList({
    required this.rows,
    required this.scrollController,
    required this.onDeleted,
    required this.sessionId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Group by section.
    final npc = rows.where((t) => t.name.startsWith('npc:')).toList();
    final rel = rows.where((t) => t.name.startsWith('relationship:')).toList();
    final arc = rows.where((t) => t.name.startsWith('arc:')).toList();
    final world = rows.where((t) => t.name.startsWith('world:')).toList();
    final scene = rows.where((t) => t.name.startsWith('scene.')).toList();
    final overrides = rows
        .where((t) => t.name.startsWith('canon_override:'))
        .toList();
    final locks = rows.where((t) => t.name.startsWith('canon_lock:')).toList();
    final diag = rows.where((t) => t.name.startsWith('_ledger:')).toList();

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (npc.isNotEmpty) ...[
          _sectionHeader(context, Icons.person_outline, 'Entity State (NPC)'),
          ...npc.map(
            (t) =>
                _TrackerTile(t: t, sessionId: sessionId, onDeleted: onDeleted),
          ),
        ],
        if (rel.isNotEmpty) ...[
          _sectionHeader(context, Icons.people_outline, 'Relationship State'),
          ...rel.map(
            (t) =>
                _TrackerTile(t: t, sessionId: sessionId, onDeleted: onDeleted),
          ),
        ],
        if (arc.isNotEmpty) ...[
          _sectionHeader(context, Icons.timeline_outlined, 'Arc State'),
          ...arc.map(
            (t) =>
                _TrackerTile(t: t, sessionId: sessionId, onDeleted: onDeleted),
          ),
        ],
        if (world.isNotEmpty) ...[
          _sectionHeader(context, Icons.public_outlined, 'World State'),
          ...world.map(
            (t) =>
                _TrackerTile(t: t, sessionId: sessionId, onDeleted: onDeleted),
          ),
        ],
        if (scene.isNotEmpty) ...[
          _sectionHeader(context, Icons.theaters_outlined, 'Scene State'),
          ...scene.map(
            (t) =>
                _TrackerTile(t: t, sessionId: sessionId, onDeleted: onDeleted),
          ),
        ],
        if (overrides.isNotEmpty) ...[
          _sectionHeader(context, Icons.edit_outlined, 'Manual Overrides'),
          ...overrides.map(
            (t) => _TrackerTile(
              t: t,
              sessionId: sessionId,
              onDeleted: onDeleted,
              accent: Colors.orange,
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
              accent: Colors.red,
            ),
          ),
        ],
        if (diag.isNotEmpty) ...[
          _sectionHeader(
            context,
            Icons.biotech_outlined,
            'Raw Visible Ledger (Diagnostic)',
          ),
          ...diag.map(
            (t) => _TrackerTile(
              t: t,
              sessionId: sessionId,
              onDeleted: onDeleted,
              isLongValue: true,
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

class _TrackerTile extends ConsumerWidget {
  final Tracker t;
  final String sessionId;
  final VoidCallback onDeleted;
  final Color? accent;
  final bool isLongValue;

  const _TrackerTile({
    required this.t,
    required this.sessionId,
    required this.onDeleted,
    this.accent,
    this.isLongValue = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final effectiveAccent = accent ?? cs.onSurfaceVariant;

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      title: Text(
        t.name,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: effectiveAccent,
          fontFamily: 'monospace',
        ),
      ),
      subtitle: isLongValue
          ? GestureDetector(
              onTap: () => _showFullValue(context, t),
              child: _TrackerValue(t: t, isLongValue: true),
            )
          : _TrackerValue(t: t),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.copy, size: 16),
            visualDensity: VisualDensity.compact,
            tooltip: 'Copy value',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: t.value));
            },
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, size: 16, color: cs.error),
            visualDensity: VisualDensity.compact,
            tooltip: 'Delete row',
            onPressed: () async {
              final repo = ref.read(trackerRepoProvider);
              await repo.delete(sessionId, t.name);
              onDeleted();
            },
          ),
        ],
      ),
    );
  }

  void _showFullValue(BuildContext ctx, Tracker t) {
    showDialog<void>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: Text(t.name, style: const TextStyle(fontSize: 13)),
        content: SingleChildScrollView(
          child: SelectableText(t.value, style: const TextStyle(fontSize: 12)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
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
