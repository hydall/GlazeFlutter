import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/llm/context_calculator.dart';
import '../../../shared/theme/app_colors.dart';
import '../chat_provider.dart';

const kSourceMeta = <String, SourceMeta>{
  'preset':          SourceMeta(label: 'Preset',           color: Color(0xFF4ECDC4)),
  'description':     SourceMeta(label: 'Description',      color: Color(0xFFFF6B6B)),
  'personality':     SourceMeta(label: 'Personality',      color: Color(0xFFD4A5E5)),
  'scenario':        SourceMeta(label: 'Scenario',         color: Color(0xFFB8D4E3)),
  'mesExamples':     SourceMeta(label: 'Mes Examples',     color: Color(0xFFC9B1FF)),
  'depthPrompt':     SourceMeta(label: 'Depth Prompt',     color: Color(0xFFE8A0BF)),
  'persona':         SourceMeta(label: 'Persona',          color: Color(0xFF81ECEC)),
  'authorsNote':     SourceMeta(label: "Author's Note",    color: Color(0xFFFFD93D)),
  'summary':         SourceMeta(label: 'Summary',          color: Color(0xFF95E1D3)),
  'memory':          SourceMeta(label: 'Memory',           color: Color(0xFFA8E6CF)),
  'lorebook':        SourceMeta(label: 'Keyword Lorebook', color: Color(0xFFF4A261)),
  'lorebooks':       SourceMeta(label: 'Lorebooks (macro)',color: Color(0xFFE8985E)),
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
    'vectorLore'      => bd.vectorLoreTokens,
    'preset'          => bd.presetNetTokens,
    'summary'         => _summaryTokens(bd),
    _                 => (bd.sourceTokens[key] ?? 0) > 0 ? bd.sourceTokens[key]! : (bd.macroTokens[key] ?? 0),
  };
}

int _summaryTokens(TokenBreakdown bd) {
  final raw = (bd.sourceTokens['summary'] ?? 0) > 0 ? bd.sourceTokens['summary']! : (bd.macroTokens['summary'] ?? 0);
  final memoryOverlap = (bd.sourceTokens['summary'] ?? 0) > 0 ? (bd.macroTokens['memory'] ?? 0) : 0;
  return (raw - memoryOverlap).clamp(0, raw);
}

int _unusedLorebookReserve(TokenBreakdown bd) {
  final actual = (bd.sourceTokens['lorebook'] ?? 0) + (bd.macroTokens['lorebooks'] ?? 0);
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
  final double historyFill;

  const HeroCard({
    super.key,
    required this.used,
    required this.contextSize,
    required this.remaining,
    required this.historyFill,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [context.cs.primary, Color.lerp(context.cs.primary, Colors.black, 0.2)!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Column(
        children: [
          Text(
            fmtNum(used),
            style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w700, color: Colors.white, height: 1.1, letterSpacing: -0.5),
          ),
          const SizedBox(height: 4),
          Text(
            'used / ${fmtNum(contextSize)}'.toUpperCase(),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white70, letterSpacing: 0.5),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Expanded(child: KpiItem(value: fmtNum(remaining), label: 'remaining')),
                Container(width: 1, height: 28, color: Colors.white.withValues(alpha: 0.2)),
                Expanded(child: KpiItem(value: '${historyFill.round()}%', label: 'history fill')),
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
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
        const SizedBox(height: 2),
        Text(label.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.white.withValues(alpha: 0.65), letterSpacing: 0.3)),
      ],
    );
  }
}

class TokenizerLayout extends StatelessWidget {
  final TokenBreakdown breakdown;
  final int contextSize;
  const TokenizerLayout({super.key, required this.breakdown, required this.contextSize});

  static const _mainKeys = ['description', 'personality', 'scenario', 'mesExamples', 'depthPrompt', 'preset', 'persona', 'authorsNote', 'summary', 'memory', 'history'];
  static const _reserveKeys = ['lorebook', 'lorebooks', 'vectorLore', 'lorebookTotal', 'lorebookReserve'];

  @override
  Widget build(BuildContext context) {
    final mainItems = buildOrderedRows(breakdown, _mainKeys);
    final reserveItems = buildOrderedRows(breakdown, _reserveKeys);
    
    final List<BarRow> combinedBreakdownItems = [...mainItems, ...reserveItems];
    final hasKeywordLore = (breakdown.sourceTokens['lorebook'] ?? 0) > 0 || (breakdown.macroTokens['lorebooks'] ?? 0) > 0;
    if (breakdown.lorebookTotal > 0 && hasKeywordLore && breakdown.vectorLoreTokens > 0) {
      combinedBreakdownItems.add(BarRow(key: 'lorebookTotal', label: 'Lorebook Total', tokens: breakdown.lorebookTotal, color: Colors.transparent));
    }

    final totalMain = mainItems.fold<int>(0, (s, r) => s + r.tokens);
    final totalReserve = reserveItems.fold<int>(0, (s, r) => s + r.tokens);
    final emptyTokens = contextSize - totalMain - totalReserve;
    final ctxPct = contextSize > 0 ? 1.0 / contextSize : 0.0;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 48,
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Container(
              decoration: BoxDecoration(
                color: context.cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(color: Colors.white.withValues(alpha: 0.05), offset: const Offset(1, 1), blurRadius: 2, spreadRadius: 0, blurStyle: BlurStyle.inner),
                  BoxShadow(color: Colors.black.withValues(alpha: 0.2), offset: const Offset(-1, -1), blurRadius: 2, spreadRadius: 0, blurStyle: BlurStyle.inner),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.white.withValues(alpha: 0.05), Colors.white.withValues(alpha: 0.12), Colors.white.withValues(alpha: 0.02), Colors.transparent],
                          stops: const [0, 0.2, 0.5, 1],
                        ),
                      ),
                    ),
                  ),
                  Column(
                    children: [
                      for (final item in mainItems)
                        _barSegment(item.tokens.toDouble() * ctxPct, item.color),
                      if (emptyTokens > 0)
                        _barSegment(emptyTokens.toDouble() * ctxPct, Colors.transparent),
                      for (final item in reserveItems)
                        _barSegment(item.tokens.toDouble() * ctxPct, item.color),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
              child: Column(
              mainAxisSize: MainAxisSize.min,
              children: combinedBreakdownItems.map((row) => _breakdownRow(context, row, breakdown)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _barSegment(double fraction, Color color) {
    if (fraction <= 0) return const SizedBox();
    final flex = (fraction * 100000).toInt();
    if (flex <= 0) return const SizedBox();
    
    Decoration? decoration;
    if (color != Colors.transparent) {
      final darken = Color.lerp(color, Colors.black, 0.15)!;
      decoration = BoxDecoration(
        gradient: LinearGradient(colors: [color, darken]),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          bottom: BorderSide(color: Colors.black.withValues(alpha: 0.1)),
        ),
      );
    }
    
    return Expanded(
      flex: flex,
      child: Container(
        width: double.infinity,
        decoration: decoration,
      ),
    );
  }

  Widget _breakdownRow(BuildContext context, BarRow row, TokenBreakdown bd) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          if (row.key == 'lorebookTotal')
            const SizedBox(width: 8)
          else
            Container(width: 8, height: 8, decoration: BoxDecoration(color: row.color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(child: Text(row.label, style: TextStyle(fontSize: 14, color: context.cs.onSurfaceVariant))),
          Text(
            _rowTokenText(bd, row),
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: context.cs.onSurface),
          ),
        ],
      ),
    );
  }

  String _rowTokenText(TokenBreakdown bd, BarRow row) {
    return '${row.tokens}';
  }
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
                foregroundColor: context.cs.primary,
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
  final int hideCount;
  final int hideTokens;
  const NearLimitWarning({super.key, required this.hideCount, required this.hideTokens});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFB84D).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFB84D).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('History is near its limit', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFFFFB84D))),
          const SizedBox(height: 4),
          Text(
            'Hide about $hideCount top message${hideCount == 1 ? '' : 's'} to free about $hideTokens tokens.',
            style: TextStyle(fontSize: 14, color: context.cs.onSurfaceVariant),
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
                Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: context.cs.onSurface)),
                Text('${value.round()}$unit', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: context.cs.primary)),
              ],
            ),
            const SizedBox(height: 4),
            Text(description, style: TextStyle(fontSize: 12, color: context.cs.onSurfaceVariant)),
            Slider(value: value, min: min, max: max, divisions: (max - min).round(), activeColor: context.cs.primary, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}
