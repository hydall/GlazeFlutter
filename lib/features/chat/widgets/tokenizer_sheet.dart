import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/llm/context_calculator.dart';
import '../../../core/llm/prompt_isolate.dart';
import '../../../core/llm/prompt_payload_builder.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/sheet_view.dart';
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
      final chatState = ref.read(chatProvider(widget.charId)).value;
      final session = chatState?.session;
      if (session == null) {
        setState(() => _loading = false);
        return;
      }

      _visibleCount = session.messages.where((m) => !m.isHidden).length;
      _hiddenCount = session.messages.where((m) => m.isHidden).length;

      final builder = ref.read(promptPayloadBuilderProvider);
      final payload = await builder.buildFromSession(
        charId: widget.charId,
        session: session,
      );
      _contextSize = payload.apiConfig.contextSize;

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
    ref.listen(chatProvider(widget.charId), (prev, next) {
      final prevSession = prev?.value?.session;
      final nextSession = next.value?.session;
      if (prevSession != nextSession && !_loading) {
        _calculate();
      }
    });

    final contextSize = _contextSize ?? 4096;
    final bd = _breakdown;
    final used = bd?.totalTokens ?? 0;
    final remaining = bd?.remaining ?? (contextSize - used);
    final usedPercent = contextSize > 0 ? (used / contextSize * 100) : 0.0;
    final historyFill = bd?.historyFillPercent ?? 0.0;
    final nearLimit = historyFill >= _historyFillThreshold;

    return SheetView(
      title: _showSettings ? 'Tokenizer Settings' : 'Context Usage',
      showBack: true,
      onBack: () => _showSettings
          ? setState(() => _showSettings = false)
          : Navigator.of(context).maybePop(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : bd == null
          ? Center(
              child: Text(
                'No data',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          : _showSettings
          ? _buildSettings()
          : _buildMainView(
              bd,
              contextSize,
              used,
              remaining,
              usedPercent,
              historyFill,
              nearLimit,
            ),
    );
  }

  Widget _buildMainView(
    TokenBreakdown bd,
    int contextSize,
    int used,
    int remaining,
    double usedPercent,
    double historyFill,
    bool nearLimit,
  ) {
    return Builder(
      builder: (context) => ListView(
        padding: const EdgeInsets.all(
          16,
        ).add(EdgeInsets.only(top: MediaQuery.paddingOf(context).top)),
        children: [
          HeroCard(
            used: used,
            contextSize: contextSize,
            remaining: remaining,
            usedPercent: usedPercent,
            historyFill: historyFill,
          ),
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
      ),
    );
  }

  Widget _buildSettings() {
    return Builder(
      builder: (context) => ListView(
        padding: const EdgeInsets.all(
          16,
        ).add(EdgeInsets.only(top: MediaQuery.paddingOf(context).top)),
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
      ),
    );
  }
}

void showTokenizerSheet(BuildContext context, String charId) {
  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => TokenizerSheet(charId: charId),
  );
}
