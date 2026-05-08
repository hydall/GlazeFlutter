import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/llm/context_calculator.dart';
import '../../../shared/theme/app_colors.dart';
import '../chat_provider.dart';

const kSourceMeta = <String, SourceMeta>{
  'character':       SourceMeta(label: 'Character',        color: Color(0xFFFF6B6B)),
  'preset':          SourceMeta(label: 'Preset',           color: Color(0xFF4ECDC4)),
  'persona':         SourceMeta(label: 'Persona',          color: Color(0xFF81ECEC)),
  'authorsNote':     SourceMeta(label: "Author's Note",    color: Color(0xFFFFD93D)),
  'summary':         SourceMeta(label: 'Summary',          color: Color(0xFF95E1D3)),
  'memory':          SourceMeta(label: 'Memory',           color: Color(0xFFA8E6CF)),
  'lorebook':        SourceMeta(label: 'Keyword Lorebook', color: Color(0xFFF4A261)),
  'vectorLore':      SourceMeta(label: 'Vector Lorebook',  color: Color(0xFFE76F51)),
  'lorebookReserve': SourceMeta(label: 'Lorebook Reserve', color: Color(0xFFA8DADC)),
  'history':         SourceMeta(label: 'History',          color: Color(0xFF6C5CE7)),
};

class SourceMeta {
  final String label;
  final Color color;
  const SourceMeta({required this.label, required this.color});
}

class BarRow {
  final String key;
  final String label;
  final int tokens;
  final Color color;
  const BarRow({required this.key, required this.label, required this.tokens, required this.color});
}

int tokensForKey(TokenBreakdown bd, String key) {
  return switch (key) {
    'lorebookReserve' => _unusedLorebookReserve(bd),
    'memory'          => bd.memoryTokens,
    'vectorLore'      => bd.vectorLoreTokens,
    _                 => bd.sourceTokens[key] ?? 0,
  };
}

int _unusedLorebookReserve(TokenBreakdown bd) {
  final actual = bd.sourceTokens['lorebook'] ?? 0;
  return bd.lorebookReserveTokens > actual ? bd.lorebookReserveTokens - actual : 0;
}

List<BarRow> buildOrderedRows(TokenBreakdown bd, List<String> keys) {
  final rows = <BarRow>[];
  for (final key in keys) {
    final tokens = tokensForKey(bd, key);
    if (tokens <= 0) continue;
    final meta = kSourceMeta[key] ?? SourceMeta(label: key, color: Colors.grey);
    rows.add(BarRow(key: key, label: meta.label, tokens: tokens, color: meta.color));
  }
  return rows;
}

class HeroCard extends StatelessWidget {
  final int used;
  final int contextSize;
  final int remaining;
  final double usedPercent;
  final double historyFill;

  const HeroCard({
    super.key,
    required this.used,
    required this.contextSize,
    required this.remaining,
    required this.usedPercent,
    required this.historyFill,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF1a5276), Color(0xFF2980b9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      child: Column(
        children: [
          Text(
            fmtNum(used),
            style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: Colors.white),
          ),
          Text(
            'used / ${fmtNum(contextSize)}',
            style: const TextStyle(fontSize: 14, color: Colors.white70),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                KpiItem(value: fmtNum(remaining), label: 'Remaining'),
                Container(width: 1, height: 28, color: Colors.white24),
                KpiItem(value: '${usedPercent.toStringAsFixed(1)}%', label: 'Total Fill'),
                Container(width: 1, height: 28, color: Colors.white24),
                KpiItem(value: '${historyFill.toStringAsFixed(1)}%', label: 'History Fill'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String fmtNum(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

class KpiItem extends StatelessWidget {
  final String value;
  final String label;
  const KpiItem({super.key, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.white60)),
      ],
    );
  }
}

class ContextVerticalBar extends StatelessWidget {
  final TokenBreakdown breakdown;
  final int contextSize;
  const ContextVerticalBar({super.key, required this.breakdown, required this.contextSize});

  static const _mainKeys = ['character', 'preset', 'persona', 'authorsNote', 'summary', 'memory', 'history'];
  static const _reserveKeys = ['lorebook', 'vectorLore', 'lorebookReserve'];

  @override
  Widget build(BuildContext context) {
    final mainItems = buildOrderedRows(breakdown, _mainKeys);
    final reserveItems = buildOrderedRows(breakdown, _reserveKeys);

    final totalMain = mainItems.fold<int>(0, (s, r) => s + r.tokens);
    final totalReserve = reserveItems.fold<int>(0, (s, r) => s + r.tokens);
    final emptyTokens = contextSize - totalMain - totalReserve;
    final ctxPct = contextSize > 0 ? 1.0 / contextSize : 0.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 48,
          child: Column(
            children: [
              for (final item in mainItems)
                _barSegment(item.tokens.toDouble() * ctxPct, item.color),
              if (emptyTokens > 0)
                _barSegment(emptyTokens.toDouble() * ctxPct, Colors.white.withValues(alpha: 0.04)),
              for (final item in reserveItems)
                _barSegment(item.tokens.toDouble() * ctxPct, item.color),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...mainItems.map(_barRowLabel),
              if (reserveItems.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Reserve', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                const SizedBox(height: 4),
                ...reserveItems.map(_barRowLabel),
              ],
              if (breakdown.lorebookTotal > 0 && (breakdown.sourceTokens['lorebook'] ?? 0) > 0 && breakdown.vectorLoreTokens > 0) ...[
                const SizedBox(height: 4),
                _barRowLabel(BarRow(key: 'lorebookTotal', label: 'Lorebook Total', tokens: breakdown.lorebookTotal, color: const Color(0xFFF4A261))),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _barSegment(double fraction, Color color) {
    final height = (fraction * 240).clamp(2.0, 240.0);
    return Container(
      width: 48,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: fraction < 0.02 ? null : BorderRadius.zero,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 2, offset: const Offset(1, 0))],
      ),
    );
  }

  Widget _barRowLabel(BarRow row) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: row.color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 6),
          Expanded(child: Text(row.label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
          Text('~${row.tokens} tok', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}

class BreakdownRows extends StatelessWidget {
  final TokenBreakdown breakdown;
  const BreakdownRows({super.key, required this.breakdown});

  static const _orderedKeys = [
    'character', 'preset', 'persona', 'authorsNote', 'summary', 'memory',
    'lorebook', 'vectorLore', 'lorebookReserve', 'history',
  ];

  @override
  Widget build(BuildContext context) {
    final rows = buildOrderedRows(breakdown, _orderedKeys);

    if (breakdown.lorebookTotal > 0 && (breakdown.sourceTokens['lorebook'] ?? 0) > 0 && breakdown.vectorLoreTokens > 0) {
      rows.add(BarRow(key: 'lorebookTotal', label: 'Lorebook Total', tokens: breakdown.lorebookTotal, color: const Color(0xFFF4A261)));
    }

    return Card(
      color: Colors.white.withValues(alpha: 0.03),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 12, endIndent: 12),
            ListTile(
              dense: true,
              leading: Container(width: 8, height: 8, decoration: BoxDecoration(color: rows[i].color, shape: BoxShape.circle)),
              title: Text(rows[i].label, style: const TextStyle(fontSize: 14, color: AppColors.textPrimary)),
              trailing: Text(
                _rowTokenText(breakdown, rows[i]),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: rows[i].key == 'lorebookTotal' ? FontWeight.w700 : FontWeight.w500,
                  color: rows[i].key == 'lorebookTotal' ? AppColors.accent : AppColors.textPrimary,
                ),
              ),
            ),
          ],
          const Divider(height: 1, indent: 12, endIndent: 12),
          ListTile(
            dense: true,
            title: const Text('Total', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            trailing: Text('~${breakdown.totalTokens} tok', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.accent)),
          ),
        ],
      ),
    );
  }
}

String _rowTokenText(TokenBreakdown bd, BarRow row) {
  if (row.key == 'lorebook' && bd.lorebookReserveTokens > 0) {
    return '~${row.tokens} / ${bd.lorebookReserveTokens} tok';
  }
  return '~${row.tokens} tok';
}

class TokenizerActionButtons extends ConsumerWidget {
  final String charId;
  final int visibleCount;
  final int hiddenCount;
  final double hidePercent;
  final VoidCallback onRefresh;

  const TokenizerActionButtons({
    super.key,
    required this.charId,
    required this.visibleCount,
    required this.hiddenCount,
    required this.hidePercent,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hideCount = (visibleCount * hidePercent / 100).ceil().clamp(1, visibleCount > 1 ? visibleCount - 1 : 0);

    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: hideCount > 0 ? () => _confirmHide(context, ref, hideCount) : null,
            icon: const Icon(Icons.visibility_off, size: 16),
            label: Text('Hide top $hideCount'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2980b9),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ),
        if (hiddenCount > 0) ...[
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () async {
                await ref.read(chatProvider(charId).notifier).unhideAllMessages();
                if (context.mounted) onRefresh();
              },
              icon: const Icon(Icons.visibility, size: 16),
              label: Text('Unhide all ($hiddenCount)'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accent,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _confirmHide(BuildContext context, WidgetRef ref, int count) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hide Messages'),
        content: Text('Hide the top $count visible message${count > 1 ? 's' : ''} from prompt? They will still be visible in chat (dimmed) but excluded from generation.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(chatProvider(charId).notifier).hideTopMessages(count);
              onRefresh();
            },
            child: Text('Hide $count'),
          ),
        ],
      ),
    );
  }
}

class CutoffWarning extends StatelessWidget {
  final int cutoffCount;
  const CutoffWarning({super.key, required this.cutoffCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber, size: 18, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(child: Text('$cutoffCount message${cutoffCount > 1 ? 's' : ''} cut from history', style: const TextStyle(fontSize: 13, color: Colors.orange))),
        ],
      ),
    );
  }
}

class NearLimitWarning extends StatelessWidget {
  final double historyFill;
  const NearLimitWarning({super.key, required this.historyFill});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFB84D).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFB84D).withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.speed, size: 18, color: Color(0xFFFFB84D)),
              const SizedBox(width: 8),
              Text('History is near its limit', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFFFFB84D))),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'History fill: ${historyFill.toStringAsFixed(1)}%. Consider hiding older messages or increasing context size.',
            style: TextStyle(fontSize: 12, color: const Color(0xFFFFB84D).withValues(alpha: 0.8)),
          ),
        ],
      ),
    );
  }
}

class SettingsSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final String unit;
  final String description;
  final ValueChanged<double> onChanged;

  const SettingsSlider({
    super.key,
    required this.label,
    required this.value,
    this.min = 1,
    this.max = 100,
    this.unit = '%',
    required this.description,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white.withValues(alpha: 0.03),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                Text('${value.round()}$unit', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.accent)),
              ],
            ),
            const SizedBox(height: 4),
            Text(description, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            Slider(value: value, min: min, max: max, divisions: (max - min).round(), activeColor: AppColors.accent, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}
