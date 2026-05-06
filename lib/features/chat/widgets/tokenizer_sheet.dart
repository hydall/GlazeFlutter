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
import 'tokenizer_widgets.dart';

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
  int _visibleCount = 0;
  int _hiddenCount = 0;
  double _hidePercent = 30;
  double _historyFillThreshold = 85;
  bool _showSettings = false;

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

      _visibleCount = session.messages.where((m) => !m.isHidden).length;
      _hiddenCount = session.messages.where((m) => m.isHidden).length;

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
    final nearLimit = historyFill >= _historyFillThreshold;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: GlazeAppBar(
                title: _showSettings ? 'Tokenizer Settings' : 'Context Usage',
                leading: BackButton(
                  onPressed: () => _showSettings
                      ? setState(() => _showSettings = false)
                      : Navigator.pop(context),
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : bd == null
                    ? Center(child: Text('No data', style: TextStyle(color: AppColors.textSecondary)))
                    : _showSettings
                        ? _buildSettings()
                        : _buildMainView(bd, contextSize, used, remaining, usedPercent, historyFill, nearLimit),
          ),
        ],
      ),
    );
  }

  Widget _buildMainView(TokenBreakdown bd, int contextSize, int used, int remaining, double usedPercent, double historyFill, bool nearLimit) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        HeroCard(used: used, contextSize: contextSize, remaining: remaining, usedPercent: usedPercent, historyFill: historyFill),
        const SizedBox(height: 20),
        ContextVerticalBar(breakdown: bd, contextSize: contextSize),
        const SizedBox(height: 20),
        BreakdownRows(breakdown: bd),
        if (bd.cutoffIndex > 0) ...[
          const SizedBox(height: 12),
          CutoffWarning(cutoffCount: bd.cutoffIndex),
        ],
        if (nearLimit) ...[
          const SizedBox(height: 12),
          NearLimitWarning(historyFill: historyFill),
        ],
        const SizedBox(height: 16),
        TokenizerActionButtons(
          charId: widget.charId,
          visibleCount: _visibleCount,
          hiddenCount: _hiddenCount,
          hidePercent: _hidePercent,
          onRefresh: _calculate,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _calculate,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Recalculate'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _showSettings = true),
                icon: const Icon(Icons.settings, size: 16),
                label: const Text('Settings'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSettings() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SettingsSlider(
          label: 'History fill threshold',
          value: _historyFillThreshold,
          min: 1,
          max: 100,
          unit: '%',
          description: 'Warn when history fills this % of its budget',
          onChanged: (v) => setState(() => _historyFillThreshold = v),
        ),
        const SizedBox(height: 16),
        SettingsSlider(
          label: 'Hide top messages',
          value: _hidePercent,
          min: 1,
          max: 95,
          unit: '%',
          description: 'What % of visible messages the Hide button will hide',
          onChanged: (v) => setState(() => _hidePercent = v),
        ),
      ],
    );
  }
}

void showTokenizerSheet(BuildContext context, String charId) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => TokenizerSheet(charId: charId)),
  );
}
