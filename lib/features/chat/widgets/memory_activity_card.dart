import 'package:flutter/material.dart';

import '../../../shared/theme/app_colors.dart';
import '../state/memory_activity_provider.dart';

class MemoryActivityCard extends StatelessWidget {
  final MemoryActivityState activity;
  final bool expanded;
  final VoidCallback onToggle;

  const MemoryActivityCard({
    super.key,
    required this.activity,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final diagnostics = activity.diagnostics;
    final selectedCount = diagnostics['selectedCount'] as int? ?? 0;
    final selectedTokens = diagnostics['selectedTokens'] as int? ?? 0;
    final totalCandidates = diagnostics['totalCandidates'] as int? ?? 0;
    final skippedCount = diagnostics['skippedCount'] as int? ?? 0;
    final latencyMs = diagnostics['latencyMs'] as int? ?? 0;
    final title = selectedCount == 0
        ? 'Memory: no entries selected'
        : 'Memory: $selectedCount entries, $selectedTokens tokens';

    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.cs.surface.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.cs.primary.withValues(alpha: 0.22)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.24),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.psychology_alt_outlined,
                        size: 18,
                        color: context.cs.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            color: context.cs.onSurface,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        '$totalCandidates candidates',
                        style: TextStyle(
                          color: context.cs.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        expanded
                            ? Icons.expand_more_rounded
                            : Icons.chevron_left_rounded,
                        color: context.cs.onSurfaceVariant,
                        size: 20,
                      ),
                    ],
                  ),
                  if (expanded) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _MemoryActivityChip(label: 'skipped $skippedCount'),
                        _MemoryActivityChip(label: 'latency ${latencyMs}ms'),
                        _MemoryActivityChip(
                          label: _budgetLabel(diagnostics['budget']),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ..._candidateRows(diagnostics),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _budgetLabel(Object? raw) {
    if (raw is! Map) return 'budget none';
    final source = raw['source'] ?? 'none';
    final tokens = raw['effectiveTokens'];
    return tokens is int ? 'budget $tokens ($source)' : 'budget $source';
  }

  static List<Widget> _candidateRows(Map<String, dynamic> diagnostics) {
    final raw = diagnostics['candidates'];
    if (raw is! List) return const [];
    return raw
        .take(6)
        .whereType<Map<String, dynamic>>()
        .map((candidate) {
          final title = (candidate['title'] as String?)?.trim();
          final entryId = candidate['entryId'] as String? ?? '';
          final label = title == null || title.isEmpty ? entryId : title;
          final selected = candidate['selected'] == true;
          final reason = candidate['reason'] as String? ?? 'not_selected';
          final tokens = candidate['tokenCost'] as int? ?? 0;
          final injectionType = candidate['injectionType'] as String? ?? 'none';
          final score = candidate['score'];
          final scoreText = score is num ? score.toStringAsFixed(2) : '0.00';
          final typeLabel = injectionType == 'excerpt'
              ? 'excerpt'
              : injectionType == 'full_entry'
              ? 'full'
              : reason;
          return Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Icon(
                  selected ? Icons.check_circle_outline : Icons.cancel_outlined,
                  color: selected ? Colors.greenAccent : Colors.orangeAccent,
                  size: 16,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    '$label · $typeLabel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                Text(
                  '$tokens tok · $scoreText',
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          );
        })
        .toList(growable: false);
  }
}

class _MemoryActivityChip extends StatelessWidget {
  final String label;

  const _MemoryActivityChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: context.cs.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: context.cs.onSurfaceVariant, fontSize: 11),
      ),
    );
  }
}
