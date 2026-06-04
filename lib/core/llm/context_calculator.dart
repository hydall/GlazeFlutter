import 'tokenizer.dart';
import 'history_assembler.dart';

class StaticBlock {
  final String id;
  final String content;
  const StaticBlock({required this.id, required this.content});

  Map<String, dynamic> toJson() => {'id': id, 'content': content};

  factory StaticBlock.fromJson(Map<String, dynamic> json) => StaticBlock(
    id: json['id'] as String,
    content: json['content'] as String,
  );
}

class ContextCalculator {
  final int contextSize;
  final int maxTokens;

  ContextCalculator({
    required this.contextSize,
    required this.maxTokens,
  });

  int get safeContext => contextSize;

  TokenBreakdown calculate({
    required List<StaticBlock> staticBlocks,
    required List<PromptMessage> historyMessages,
    int lorebookReserveTokens = 0,
    int memoryTokens = 0,
    int vectorLoreTokens = 0,
    Map<String, int> macroTokens = const {},
  }) {
    final sourceTokens = <String, int>{};
    var staticTotal = 0;

    for (final block in staticBlocks) {
      final tokens = estimateTokens(block.content);
      final source = _sourceForBlock(block.id);
      sourceTokens[source] = (sourceTokens[source] ?? 0) + tokens;
      staticTotal += tokens;
    }

    final actualLorebook = (sourceTokens['lorebook'] ?? 0) + (macroTokens['lorebooks'] ?? 0);
    final effectiveReserve = lorebookReserveTokens > actualLorebook
        ? lorebookReserveTokens - actualLorebook
        : 0;

    final historyBudget = safeContext - staticTotal - effectiveReserve - memoryTokens;

    final (trimmedHistory, cutoffIndex) = _trimHistory(
      historyMessages,
      historyBudget > 0 ? historyBudget : 0,
    );

    final historyTokens = trimmedHistory.fold<int>(
      0,
      (sum, m) => sum + estimateTokens(m.content),
    );
    sourceTokens['history'] = historyTokens;

    if (vectorLoreTokens > 0) {
      sourceTokens['vectorLore'] = vectorLoreTokens;
    }

    final fixedTotal = staticTotal + effectiveReserve + memoryTokens + vectorLoreTokens;
    final remaining = safeContext - fixedTotal - historyTokens;

    // sentTokens = tokens actually sent in the request (no unspent reserve).
    // fixedTotal includes effectiveReserve which shrinks the history budget but
    // is never literally in the payload; exclude it so HeroCard matches
    // the provider's prompt_tokens as closely as possible.
    final sentTokens = staticTotal + memoryTokens + vectorLoreTokens + historyTokens;

    return TokenBreakdown(
      sourceTokens: sourceTokens,
      macroTokens: macroTokens,
      staticTotal: staticTotal,
      historyBudget: historyBudget,
      historyTokens: historyTokens,
      totalTokens: sentTokens,
      cutoffIndex: cutoffIndex,
      trimmedHistory: trimmedHistory,
      lorebookReserveTokens: lorebookReserveTokens,
      memoryTokens: memoryTokens,
      vectorLoreTokens: vectorLoreTokens,
      fixedTotal: fixedTotal,
      remaining: remaining,
    );
  }

  String _sourceForBlock(String blockId) {
    return switch (blockId) {
      'char_card' => 'description',
      'char_personality' => 'personality',
      'scenario' => 'scenario',
      'example_dialogue' => 'mesExamples',
      'char_depth_prompt' => 'depthPrompt',
      'user_persona' => 'persona',
      'summary' => 'summary',
      'authors_note' => 'authorsNote',
      'chat_history' => 'history',
      'worldInfoBefore' || 'worldInfoAfter' => 'lorebook',
      'memory' => 'memory',
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
  final Map<String, int> macroTokens;
  final int staticTotal;
  final int historyBudget;
  final int historyTokens;
  final int totalTokens;
  final int cutoffIndex;
  final List<PromptMessage> trimmedHistory;
  final int lorebookReserveTokens;
  final int memoryTokens;
  final int vectorLoreTokens;
  final int fixedTotal;
  final int remaining;
  final int summaryContentTokens;

  const TokenBreakdown({
    required this.sourceTokens,
    this.macroTokens = const {},
    required this.staticTotal,
    required this.historyBudget,
    required this.historyTokens,
    required this.totalTokens,
    required this.cutoffIndex,
    required this.trimmedHistory,
    this.lorebookReserveTokens = 0,
    this.memoryTokens = 0,
    this.vectorLoreTokens = 0,
    this.fixedTotal = 0,
    this.remaining = 0,
    this.summaryContentTokens = 0,
  });

  Map<String, dynamic> toJson() => {
    'sourceTokens': sourceTokens,
    'macroTokens': macroTokens,
    'staticTotal': staticTotal,
    'historyBudget': historyBudget,
    'historyTokens': historyTokens,
    'totalTokens': totalTokens,
    'cutoffIndex': cutoffIndex,
    'trimmedHistory': trimmedHistory.map((m) => m.toJson()).toList(),
    'lorebookReserveTokens': lorebookReserveTokens,
    'memoryTokens': memoryTokens,
    'vectorLoreTokens': vectorLoreTokens,
    'fixedTotal': fixedTotal,
    'remaining': remaining,
    'summaryContentTokens': summaryContentTokens,
  };

  factory TokenBreakdown.fromJson(Map<String, dynamic> json) => TokenBreakdown(
    sourceTokens: Map<String, int>.from(json['sourceTokens'] as Map),
    macroTokens: Map<String, int>.from(json['macroTokens'] as Map? ?? {}),
    staticTotal: json['staticTotal'] as int,
    historyBudget: json['historyBudget'] as int,
    historyTokens: json['historyTokens'] as int,
    totalTokens: json['totalTokens'] as int,
    cutoffIndex: json['cutoffIndex'] as int,
    trimmedHistory: (json['trimmedHistory'] as List).map((m) => PromptMessage.fromJson(m as Map<String, dynamic>)).toList(),
    lorebookReserveTokens: json['lorebookReserveTokens'] as int? ?? 0,
    memoryTokens: json['memoryTokens'] as int? ?? 0,
    vectorLoreTokens: json['vectorLoreTokens'] as int? ?? 0,
    fixedTotal: json['fixedTotal'] as int? ?? 0,
    remaining: json['remaining'] as int? ?? 0,
    summaryContentTokens: json['summaryContentTokens'] as int? ?? 0,
  );

  int get lorebookTotal => (sourceTokens['lorebook'] ?? 0) + (macroTokens['lorebooks'] ?? 0) + vectorLoreTokens;

  double get historyFillPercent => historyBudget > 0
      ? (historyTokens / historyBudget * 100).clamp(0, 100)
      : 0;

  int get presetNetTokens {
    final presetGross = sourceTokens['preset'] ?? 0;
    var subtract = 0;
    for (final entry in macroTokens.entries) {
      if (entry.key == 'memory') continue;
      if ((sourceTokens[entry.key] ?? 0) == 0) {
        subtract += entry.value;
      }
    }
    return (presetGross - subtract).clamp(0, presetGross);
  }
}
