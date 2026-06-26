import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/agent_operation_record.dart';
import '../../../shared/theme/app_colors.dart';
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
  _LogFilter _filter = _LogFilter.all;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentOperationsLogProvider);
    final allRecords = state.forSession(widget.sessionId);
    final filtered = switch (_filter) {
      _LogFilter.all => allRecords,
      _LogFilter.failed => allRecords.where((r) => r.status.isFailure).toList(),
      _LogFilter.success =>
        allRecords.where((r) => r.status.isOk).toList(),
    };
    filtered.sort((a, b) => b.finishedAtMs.compareTo(a.finishedAtMs));

    return Dialog(
      child: SizedBox(
        width: 720,
        height: 560,
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
                      icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                      tooltip: 'Clear log',
                      visualDensity: VisualDensity.compact,
                    ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 20),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  SegmentedButton<_LogFilter>(
                    segments: const [
                      ButtonSegment(
                        value: _LogFilter.all,
                        label: Text('All'),
                      ),
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
                    onSelectionChanged: (s) =>
                        setState(() => _filter = s.first),
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (widget.sessionId != null)
                    Expanded(
                      child: Text(
                        'Filtered to current chat',
                        style: TextStyle(
                          fontSize: 11,
                          color: context.cs.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No agentic operations recorded yet.\n\n'
                          'Operations appear here when the POST-cleaner, '
                          'memory sidecar reranker, or agentic memory '
                          'search/write tools are invoked during generation.',
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
                      separatorBuilder: (_, _) => const Divider(
                        height: 1,
                        indent: 12,
                        endIndent: 12,
                      ),
                      itemBuilder: (context, i) =>
                          _OperationTile(record: filtered[i]),
                    ),
            ),
          ],
        ),
      ),
    );
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
              style: TextStyle(
                fontSize: 11,
                color: context.cs.onSurface,
              ),
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
