import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/llm/context_calculator.dart';
import '../../../core/llm/prompt_builder.dart';
import '../../../core/llm/prompt_isolate.dart';
import '../../../core/state/active_selection_provider.dart';
import '../../../core/state/db_provider.dart';
import '../../../core/state/lorebook_provider.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/glaze_scaffold.dart';
import '../chat_provider.dart';

const _kSourceMeta = <String, _SourceMeta>{
  'character':       _SourceMeta(label: 'Character',       color: Color(0xFFFF6B6B)),
  'preset':          _SourceMeta(label: 'Preset',          color: Color(0xFF4ECDC4)),
  'persona':         _SourceMeta(label: 'Persona',         color: Color(0xFF81ECEC)),
  'authorsNote':     _SourceMeta(label: "Author's Note",   color: Color(0xFFFFD93D)),
  'summary':         _SourceMeta(label: 'Summary',         color: Color(0xFF95E1D3)),
  'memory':          _SourceMeta(label: 'Memory',          color: Color(0xFFA8E6CF)),
  'lorebook':        _SourceMeta(label: 'Keyword Lorebook', color: Color(0xFFF4A261)),
  'vectorLore':      _SourceMeta(label: 'Vector Lorebook', color: Color(0xFFE76F51)),
  'lorebookReserve': _SourceMeta(label: 'Lorebook Reserve', color: Color(0xFFA8DADC)),
  'history':         _SourceMeta(label: 'History',         color: Color(0xFF6C5CE7)),
};

class _SourceMeta {
  final String label;
  final Color color;
  const _SourceMeta({required this.label, required this.color});
}

class TokenizerSheet extends ConsumerStatefulWidget {
  final String charId;
  const TokenizerSheet({super.key, required this.charId});

  @override
  ConsumerState<TokenizerSheet> createState() => _TokenizerSheetState();
}

class _TokenizerSheetState extends ConsumerState<TokenizerSheet> {
  TokenBreakdown? _breakdown;
  int? _contextSize;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _calculate();
  }

  Future<void> _calculate() async {
    setState(() => _loading = true);

    try {
      final charRepo = ref.read(characterRepoProvider);
      final presetRepo = ref.read(presetRepoProvider);
      final personaRepo = ref.read(personaRepoProvider);
      final apiConfigRepo = ref.read(apiConfigRepoProvider);

      final character = await charRepo.getById(widget.charId);
      if (character == null) { setState(() => _loading = false); return; }

      final apiConfigs = await apiConfigRepo.getAll();
      if (apiConfigs.isEmpty) { setState(() => _loading = false); return; }
      final apiConfig = apiConfigs.first;
      _contextSize = apiConfig.contextSize;

      final activePresetId = ref.read(activePresetIdProvider);
      final activePersonaId = ref.read(activePersonaIdProvider);
      final presets = await presetRepo.getAll();
      final preset = activePresetId != null
          ? presets.where((p) => p.id == activePresetId).firstOrNull
          : (presets.isNotEmpty ? presets.first : null);
      final personas = await personaRepo.getAll();
      final persona = activePersonaId != null
          ? personas.where((p) => p.id == activePersonaId).firstOrNull
          : (personas.isNotEmpty ? personas.first : null);

      final chatState = ref.read(chatProvider(widget.charId)).value;
      final session = chatState?.session;
      if (session == null) { setState(() => _loading = false); return; }

      final payload = PromptPayload(
        character: character,
        persona: persona,
        preset: preset,
        history: session.messages,
        apiConfig: apiConfig,
        sessionVars: session.sessionVars,
        globalVars: ref.read(globalVarsProvider),
        lorebooks: await ref.read(lorebookRepoProvider).getAll(),
        lorebookSettings: ref.read(lorebookSettingsProvider),
        lorebookActivations: ref.read(lorebookActivationsProvider),
      );

      final result = await buildPromptInIsolate(payload);
      if (mounted) setState(() => _breakdown = result.breakdown);
    } catch (e) {
      debugPrint('Tokenizer error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final contextSize = _contextSize ?? 4096;
    final bd = _breakdown;
    final used = bd?.totalTokens ?? 0;
    final remaining = bd?.remaining ?? (contextSize - used);
    final usedPercent = contextSize > 0 ? (used / contextSize * 100) : 0.0;
    final historyFill = bd?.historyFillPercent ?? 0.0;
    final nearLimit = historyFill >= 85;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: GlazeAppBar(
                title: 'Context Usage',
                leading: BackButton(onPressed: () => Navigator.pop(context)),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : bd == null
                    ? Center(child: Text('No data', style: TextStyle(color: AppColors.textSecondary)))
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          _HeroCard(used: used, contextSize: contextSize, remaining: remaining, usedPercent: usedPercent, historyFill: historyFill),
                          const SizedBox(height: 20),
                          _VerticalBar(breakdown: bd, contextSize: contextSize),
                          const SizedBox(height: 20),
                          _BreakdownRows(breakdown: bd),
                          if (bd.cutoffIndex > 0) ...[
                            const SizedBox(height: 12),
                            _CutoffWarning(cutoffCount: bd.cutoffIndex),
                          ],
                          if (nearLimit) ...[
                            const SizedBox(height: 12),
                            _NearLimitWarning(historyFill: historyFill),
                          ],
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: _calculate,
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('Recalculate'),
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  final int used;
  final int contextSize;
  final int remaining;
  final double usedPercent;
  final double historyFill;

  const _HeroCard({
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
            _fmtNum(used),
            style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: Colors.white),
          ),
          Text(
            'used / ${_fmtNum(contextSize)}',
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
                _KpiItem(value: _fmtNum(remaining), label: 'Remaining'),
                Container(width: 1, height: 28, color: Colors.white24),
                _KpiItem(value: '${usedPercent.toStringAsFixed(1)}%', label: 'Total Fill'),
                Container(width: 1, height: 28, color: Colors.white24),
                _KpiItem(value: '${historyFill.toStringAsFixed(1)}%', label: 'History Fill'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmtNum(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

class _KpiItem extends StatelessWidget {
  final String value;
  final String label;
  const _KpiItem({required this.value, required this.label});

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

class _VerticalBar extends StatelessWidget {
  final TokenBreakdown breakdown;
  final int contextSize;
  const _VerticalBar({required this.breakdown, required this.contextSize});

  @override
  Widget build(BuildContext context) {
    final mainItems = <_BarRow>[];
    final reserveItems = <_BarRow>[];

    final orderedKeys = [
      'character', 'preset', 'persona', 'authorsNote', 'summary', 'memory', 'history',
      'lorebook', 'vectorLore', 'lorebookReserve',
    ];

    for (final key in orderedKeys) {
      int tokens;
      switch (key) {
        case 'lorebookReserve':
          tokens = breakdown.lorebookReserveTokens;
        case 'memory':
          tokens = breakdown.memoryTokens;
        case 'vectorLore':
          tokens = breakdown.vectorLoreTokens;
        default:
          tokens = breakdown.sourceTokens[key] ?? 0;
      }
      if (tokens <= 0) continue;

      final meta = _kSourceMeta[key] ?? _SourceMeta(label: key, color: Colors.grey);
      final row = _BarRow(key: key, label: meta.label, tokens: tokens, color: meta.color);

      if (key == 'lorebook' || key == 'vectorLore' || key == 'lorebookReserve') {
        reserveItems.add(row);
      } else {
        mainItems.add(row);
      }
    }

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
              ...mainItems.map((r) => _barRow(r)),
              if (reserveItems.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Reserve', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                const SizedBox(height: 4),
                ...reserveItems.map((r) => _barRow(r)),
              ],
              if (breakdown.lorebookTotal > 0 && (breakdown.sourceTokens['lorebook'] ?? 0) > 0 && breakdown.vectorLoreTokens > 0) ...[
                const SizedBox(height: 4),
                _barRow(_BarRow(
                  key: 'lorebookTotal',
                  label: 'Lorebook Total',
                  tokens: breakdown.lorebookTotal,
                  color: const Color(0xFFF4A261),
                )),
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
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 2, offset: const Offset(1, 0)),
        ],
      ),
    );
  }

  Widget _barRow(_BarRow row) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: row.color, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 6),
          Expanded(child: Text(row.label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
          Text('~${row.tokens} tok', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}

class _BreakdownRows extends StatelessWidget {
  final TokenBreakdown breakdown;
  const _BreakdownRows({required this.breakdown});

  @override
  Widget build(BuildContext context) {
    final rows = <_BarRow>[];
    final orderedKeys = [
      'character', 'preset', 'persona', 'authorsNote', 'summary', 'memory',
      'lorebook', 'vectorLore', 'lorebookReserve', 'history',
    ];

    for (final key in orderedKeys) {
      int tokens;
      switch (key) {
        case 'lorebookReserve':
          tokens = breakdown.lorebookReserveTokens;
        case 'memory':
          tokens = breakdown.memoryTokens;
        case 'vectorLore':
          tokens = breakdown.vectorLoreTokens;
        default:
          tokens = breakdown.sourceTokens[key] ?? 0;
      }
      if (tokens <= 0) continue;
      final meta = _kSourceMeta[key] ?? _SourceMeta(label: key, color: Colors.grey);
      rows.add(_BarRow(key: key, label: meta.label, tokens: tokens, color: meta.color));
    }

    if (breakdown.lorebookTotal > 0 && (breakdown.sourceTokens['lorebook'] ?? 0) > 0 && breakdown.vectorLoreTokens > 0) {
      rows.add(_BarRow(key: 'lorebookTotal', label: 'Lorebook Total', tokens: breakdown.lorebookTotal, color: const Color(0xFFF4A261)));
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
              leading: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: rows[i].color, shape: BoxShape.circle),
              ),
              title: Text(rows[i].label, style: const TextStyle(fontSize: 14, color: AppColors.textPrimary)),
              trailing: Text(
                '~${rows[i].tokens} tok',
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
            trailing: Text(
              '~${breakdown.totalTokens} tok',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.accent),
            ),
          ),
        ],
      ),
    );
  }
}

class _CutoffWarning extends StatelessWidget {
  final int cutoffCount;
  const _CutoffWarning({required this.cutoffCount});

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
          Expanded(
            child: Text(
              '$cutoffCount message${cutoffCount > 1 ? 's' : ''} cut from history',
              style: const TextStyle(fontSize: 13, color: Colors.orange),
            ),
          ),
        ],
      ),
    );
  }
}

class _NearLimitWarning extends StatelessWidget {
  final double historyFill;
  const _NearLimitWarning({required this.historyFill});

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
              Text(
                'History is near its limit',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFFFFB84D)),
              ),
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

class _BarRow {
  final String key;
  final String label;
  final int tokens;
  final Color color;
  const _BarRow({required this.key, required this.label, required this.tokens, required this.color});
}

void showTokenizerSheet(BuildContext context, String charId) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => TokenizerSheet(charId: charId)),
  );
}
