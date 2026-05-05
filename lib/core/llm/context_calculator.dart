import 'tokenizer.dart';
import 'prompt_block_resolver.dart';
import 'history_assembler.dart';

class ContextCalculator {
  final int contextSize;
  final int maxTokens;

  ContextCalculator({
    required this.contextSize,
    required this.maxTokens,
  });

  int get safeContext => (contextSize - maxTokens).clamp(1000, contextSize);

  TokenBreakdown calculate({
    required List<ResolvedBlock> staticBlocks,
    required List<PromptMessage> historyMessages,
  }) {
    final sourceTokens = <String, int>{};
    var staticTotal = 0;

    for (final block in staticBlocks) {
      final tokens = estimateTokens(block.content);
      final source = _sourceForBlock(block.id);
      sourceTokens[source] = (sourceTokens[source] ?? 0) + tokens;
      staticTotal += tokens;
    }

    final historyBudget = safeContext - staticTotal;

    final (trimmedHistory, cutoffIndex) = _trimHistory(
      historyMessages,
      historyBudget > 0 ? historyBudget : 0,
    );

    final historyTokens = trimmedHistory.fold<int>(
      0,
      (sum, m) => sum + estimateTokens(m.content),
    );
    sourceTokens['history'] = historyTokens;

    return TokenBreakdown(
      sourceTokens: sourceTokens,
      staticTotal: staticTotal,
      historyBudget: historyBudget,
      historyTokens: historyTokens,
      totalTokens: staticTotal + historyTokens,
      cutoffIndex: cutoffIndex,
      trimmedHistory: trimmedHistory,
    );
  }

  String _sourceForBlock(String blockId) {
    return switch (blockId) {
      'char_card' || 'char_personality' || 'scenario' || 'example_dialogue' => 'character',
      'user_persona' => 'persona',
      'summary' => 'summary',
      'chat_history' => 'history',
      _ => 'preset',
    };
  }

  (List<PromptMessage>, int) _trimHistory(
    List<PromptMessage> messages,
    int budget,
  ) {
    if (budget <= 0) return (<PromptMessage>[], messages.length);

    final kept = <PromptMessage>[];
    var used = 0;

    for (int i = messages.length - 1; i >= 0; i--) {
      final tokens = estimateTokens(messages[i].content);
      if (used + tokens > budget) break;
      used += tokens;
      kept.insert(0, messages[i]);
    }

    final cutoff = messages.length - kept.length;
    return (kept, cutoff);
  }
}

class TokenBreakdown {
  final Map<String, int> sourceTokens;
  final int staticTotal;
  final int historyBudget;
  final int historyTokens;
  final int totalTokens;
  final int cutoffIndex;
  final List<PromptMessage> trimmedHistory;

  const TokenBreakdown({
    required this.sourceTokens,
    required this.staticTotal,
    required this.historyBudget,
    required this.historyTokens,
    required this.totalTokens,
    required this.cutoffIndex,
    required this.trimmedHistory,
  });
}
