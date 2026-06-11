import '../models/memory_book.dart';
import 'memory_budget.dart';
import 'memory_selector.dart';

class MemoryCandidateDiagnostics {
  final String entryId;
  final String title;
  final int tokenCost;
  final bool selected;
  final double score;
  final double keywordScore;
  final double vectorScore;
  final double recencyScore;
  final double importanceScore;
  final double diversityPenalty;
  final List<String> matchedKeys;
  final String reason;
  final List<String> messageIds;
  final String messageRange;
  final String arc;
  final String kind;

  const MemoryCandidateDiagnostics({
    required this.entryId,
    required this.title,
    required this.tokenCost,
    required this.selected,
    required this.score,
    required this.keywordScore,
    required this.vectorScore,
    required this.recencyScore,
    required this.importanceScore,
    required this.diversityPenalty,
    required this.matchedKeys,
    required this.reason,
    required this.messageIds,
    required this.messageRange,
    required this.arc,
    required this.kind,
  });

  Map<String, dynamic> toJson() => {
    'entryId': entryId,
    'title': title,
    'tokenCost': tokenCost,
    'selected': selected,
    'score': score,
    'keywordScore': keywordScore,
    'vectorScore': vectorScore,
    'recencyScore': recencyScore,
    'importanceScore': importanceScore,
    'diversityPenalty': diversityPenalty,
    'matchedKeys': matchedKeys,
    'reason': reason,
    'messageIds': messageIds,
    'messageRange': messageRange,
    'arc': arc,
    'kind': kind,
  };
}

class MemoryDiagnostics {
  final List<String> selectedEntryIds;
  final List<MemoryCandidateDiagnostics> candidates;
  final int selectedCount;
  final int skippedCount;
  final int totalCandidates;
  final int selectedTokens;
  final MemoryBudgetBreakdown budget;
  final bool budgetTrimmed;
  final int excludedBySourceWindow;
  final int latencyMs;

  const MemoryDiagnostics({
    required this.selectedEntryIds,
    required this.candidates,
    required this.selectedCount,
    required this.skippedCount,
    required this.totalCandidates,
    required this.selectedTokens,
    required this.budget,
    required this.budgetTrimmed,
    required this.excludedBySourceWindow,
    this.latencyMs = 0,
  });

  factory MemoryDiagnostics.fromSelection(
    MemorySelection selection, {
    required MemoryBudgetBreakdown budget,
    int Function(MemoryCandidateScore score)? tokenCounter,
    int latencyMs = 0,
  }) {
    final selectedIds = selection.entries.map((e) => e.id).toSet();
    final costs = <String, int>{};
    var selectedTokens = 0;

    int costOf(MemoryCandidateScore score) {
      return costs.putIfAbsent(
        score.entry.id,
        () =>
            tokenCounter?.call(score) ?? MemorySelector.tokenCost(score.entry),
      );
    }

    final candidates = selection.allScores
        .map((score) {
          final selected = selectedIds.contains(score.entry.id);
          final tokenCost = costOf(score);
          if (selected) selectedTokens += tokenCost;
          return MemoryCandidateDiagnostics(
            entryId: score.entry.id,
            title: score.entry.title,
            tokenCost: tokenCost,
            selected: selected,
            score: score.score,
            keywordScore: score.keywordScore,
            vectorScore: score.vectorScore,
            recencyScore: score.recencyScore,
            importanceScore: score.importanceScore,
            diversityPenalty: score.diversityPenalty,
            matchedKeys: score.matchedKeys,
            reason: _reasonFor(score, selected, selection),
            messageIds: score.entry.messageIds,
            messageRange: _formatMessageRange(score.entry.messageRange),
            arc: score.entry.arc,
            kind: score.entry.kind,
          );
        })
        .toList(growable: false);

    return MemoryDiagnostics(
      selectedEntryIds: selection.entries
          .map((e) => e.id)
          .toList(growable: false),
      candidates: candidates,
      selectedCount: selectedIds.length,
      skippedCount: candidates.length - selectedIds.length,
      totalCandidates: candidates.length,
      selectedTokens: tokenCounter == null && selection.totalTokens > 0
          ? selection.totalTokens
          : selectedTokens,
      budget: budget,
      budgetTrimmed: selection.budgetTrimmed,
      excludedBySourceWindow: selection.excludedBySourceWindow,
      latencyMs: latencyMs,
    );
  }

  Map<String, dynamic> toJson() => {
    'selectedEntryIds': selectedEntryIds,
    'selectedCount': selectedCount,
    'skippedCount': skippedCount,
    'totalCandidates': totalCandidates,
    'selectedTokens': selectedTokens,
    'budget': budget.toJson(),
    'budgetTrimmed': budgetTrimmed,
    'excludedBySourceWindow': excludedBySourceWindow,
    'latencyMs': latencyMs,
    'candidates': candidates.map((c) => c.toJson()).toList(),
  };

  String get summary => selectedCount == 0
      ? 'Memory: no entries selected'
      : 'Memory: $selectedCount entries, $selectedTokens tokens';

  static String _reasonFor(
    MemoryCandidateScore score,
    bool selected,
    MemorySelection selection,
  ) {
    if (selected) return 'selected';
    if (score.excludedBySourceWindow) {
      return score.exclusionReason ?? 'source_visible_in_prompt';
    }
    if (selection.budgetTrimmed && selection.budgetTokens != null) {
      return 'budget_trimmed';
    }
    if (selection.entryCap > 0 &&
        selection.entries.length >= selection.entryCap) {
      return 'entry_cap';
    }
    return 'not_selected';
  }

  static String _formatMessageRange(MessageRange? range) {
    if (range == null) return '';
    return '${range.start}-${range.end}';
  }
}
