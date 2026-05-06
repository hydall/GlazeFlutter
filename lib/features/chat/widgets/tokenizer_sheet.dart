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

  static const _sourceColors = <String, Color>{
    'character': Color(0xFFFF6B6B),
    'persona': Color(0xFF4ECDC4),
    'summary': Color(0xFF95E1D3),
    'preset': Color(0xFFFFD93D),
    'lorebook': Color(0xFFF4A261),
    'history': Color(0xFF6C5CE7),
  };

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
    final used = _breakdown?.totalTokens ?? 0;
    final remaining = contextSize - used;
    final usedPercent = contextSize > 0 ? (used / contextSize * 100) : 0.0;

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
                : _breakdown == null
                    ? Center(child: Text('No data', style: TextStyle(color: AppColors.textSecondary)))
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          _HeroSection(used: used, contextSize: contextSize, remaining: remaining, usedPercent: usedPercent),
                          const SizedBox(height: 20),
                          _ContextBar(breakdown: _breakdown!, contextSize: contextSize),
                          const SizedBox(height: 20),
                          _BreakdownList(breakdown: _breakdown!),
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

class _HeroSection extends StatelessWidget {
  final int used;
  final int contextSize;
  final int remaining;
  final double usedPercent;
  const _HeroSection({required this.used, required this.contextSize, required this.remaining, required this.usedPercent});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(used.toString(), style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        Text('used / $contextSize', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _MiniStat(value: remaining.toString(), label: 'remaining'),
            const SizedBox(width: 24),
            _MiniStat(value: '${usedPercent.toStringAsFixed(1)}%', label: 'fill'),
          ],
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String value;
  final String label;
  const _MiniStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.accent)),
        Text(label, style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }
}

class _ContextBar extends StatelessWidget {
  final TokenBreakdown breakdown;
  final int contextSize;
  const _ContextBar({required this.breakdown, required this.contextSize});

  @override
  Widget build(BuildContext context) {
    final segments = <_BarSegment>[];
    final sortedSources = breakdown.sourceTokens.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    for (final entry in sortedSources) {
      final pct = contextSize > 0 ? entry.value / contextSize * 100 : 0.0;
      segments.add(_BarSegment(
        key: entry.key,
        tokens: entry.value,
        percent: pct,
        color: _TokenizerSheetState._sourceColors[entry.key] ?? Colors.grey,
      ));
    }

    final usedPct = breakdown.totalTokens / (contextSize > 0 ? contextSize : 1) * 100;
    final remainingPct = 100 - usedPct;
    if (remainingPct > 0) {
      segments.add(_BarSegment(key: 'remaining', tokens: contextSize - breakdown.totalTokens, percent: remainingPct, color: Colors.white.withValues(alpha: 0.05)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 24,
            child: Row(
              children: segments.map((s) => Expanded(
                flex: (s.percent * 100).round().clamp(1, 10000),
                child: Container(color: s.color, height: 24),
              )).toList(),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: sortedSources.map((e) => _LegendItem(
            label: e.key,
            color: _TokenizerSheetState._sourceColors[e.key] ?? Colors.grey,
          )).toList(),
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  final String label;
  final Color color;
  const _LegendItem({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }
}

class _BreakdownList extends StatelessWidget {
  final TokenBreakdown breakdown;
  const _BreakdownList({required this.breakdown});

  @override
  Widget build(BuildContext context) {
    final sorted = breakdown.sourceTokens.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      color: Colors.white.withValues(alpha: 0.03),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          for (int i = 0; i < sorted.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 12, endIndent: 12),
            ListTile(
              dense: true,
              leading: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _TokenizerSheetState._sourceColors[sorted[i].key] ?? Colors.grey,
                  shape: BoxShape.circle,
                ),
              ),
              title: Text(sorted[i].key, style: const TextStyle(fontSize: 14, color: AppColors.textPrimary)),
              trailing: Text(
                '~${sorted[i].value} tok',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
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
          if (breakdown.cutoffIndex > 0) ...[
            const Divider(height: 1, indent: 12, endIndent: 12),
            ListTile(
              dense: true,
              title: Text('${breakdown.cutoffIndex} messages cut from history', style: TextStyle(fontSize: 12, color: Colors.orange.withValues(alpha: 0.8))),
              trailing: const Icon(Icons.warning_amber, size: 16, color: Colors.orange),
            ),
          ],
        ],
      ),
    );
  }
}

class _BarSegment {
  final String key;
  final int tokens;
  final double percent;
  final Color color;
  const _BarSegment({required this.key, required this.tokens, required this.percent, required this.color});
}

void showTokenizerSheet(BuildContext context, String charId) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => TokenizerSheet(charId: charId)),
  );
}
