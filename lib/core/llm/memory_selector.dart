import '../models/memory_book.dart';
import 'tokenizer.dart';
import 'glaze_matcher.dart';

/// Result of one candidate after the deterministic selector.
class MemoryCandidateScore {
  final MemoryEntry entry;
  final double score;
  final double keywordScore;
  final double vectorScore;
  final double recencyScore;
  final double importanceScore;
  final double catalogScore;
  final double diversityPenalty;
  final List<String> matchedKeys;
  final List<String> catalogMatchedTerms;
  final bool excludedBySourceWindow;
  final String? exclusionReason;

  const MemoryCandidateScore({
    required this.entry,
    required this.score,
    this.keywordScore = 0,
    this.vectorScore = 0,
    this.recencyScore = 0,
    this.importanceScore = 0,
    this.catalogScore = 0,
    this.diversityPenalty = 0,
    this.matchedKeys = const [],
    this.catalogMatchedTerms = const [],
    this.excludedBySourceWindow = false,
    this.exclusionReason,
  });
}

/// Aggregated result of [MemorySelector.select].
class MemorySelection {
  final String selectionMode;
  final List<MemoryEntry> entries;
  final List<MemoryCandidateScore> allScores;
  final int totalTokens;
  final int? budgetTokens;
  final int entryCap;
  final bool budgetTrimmed;
  final int excludedBySourceWindow;

  const MemorySelection({
    this.selectionMode = 'v2',
    this.entries = const [],
    this.allScores = const [],
    this.totalTokens = 0,
    this.budgetTokens,
    this.entryCap = 0,
    this.budgetTrimmed = false,
    this.excludedBySourceWindow = 0,
  });
}

/// Inputs to [MemorySelector.select]. Both keyword and vector layers are
/// optional so the same selector works in the isolate (no vector API) and
/// in the async injection service (with vector search).
class MemorySelectionInput {
  final String selectionMode;
  final List<MemoryEntry> entries;
  final Map<String, double> vectorScores;
  final Map<String, double> catalogScores;
  final Map<String, List<String>> catalogMatchedTerms;
  final Map<String, List<String>> keywordMatchedTerms;
  final Set<String> visibleMessageIds;
  final int? maxInjectionTokens;
  final int maxInjectedEntries;
  final bool diversityAware;
  final double diversityPenalty;
  final bool recencyBoost;
  final double recencyHalfLifeDays;
  final bool importanceBoost;
  final double importanceWeight;
  final bool sourceWindowExclusion;
  final int? nowMillis;
  final double keywordWeight;
  final double vectorWeight;
  final int now;

  const MemorySelectionInput({
    this.selectionMode = 'v2',
    required this.entries,
    this.vectorScores = const {},
    this.catalogScores = const {},
    this.catalogMatchedTerms = const {},
    this.keywordMatchedTerms = const {},
    this.visibleMessageIds = const {},
    this.maxInjectionTokens,
    this.maxInjectedEntries = 7,
    this.diversityAware = true,
    this.diversityPenalty = 0.15,
    this.recencyBoost = true,
    this.recencyHalfLifeDays = 0.5,
    this.importanceBoost = true,
    this.importanceWeight = 0.5,
    this.sourceWindowExclusion = true,
    this.nowMillis,
    this.keywordWeight = 6.0,
    this.vectorWeight = 5.0,
    int? nowSeconds,
  }) : now = nowSeconds ?? 0;

  /// Backwards-compat: callers used `nowSeconds` historically.
  // ignore: prefer_initializing_formals
  factory MemorySelectionInput.legacy({
    required List<MemoryEntry> entries,
    Map<String, double> vectorScores = const {},
    Set<String> visibleMessageIds = const {},
    int? maxInjectionTokens,
    int maxInjectedEntries = 7,
  }) => MemorySelectionInput(
    selectionMode: 'legacy',
    entries: entries,
    vectorScores: vectorScores,
    visibleMessageIds: visibleMessageIds,
    maxInjectionTokens: maxInjectionTokens,
    maxInjectedEntries: maxInjectedEntries,
  );
}

/// Pure selector. No I/O, no DB, no embeddings. Deterministic, testable.
/// Keeps the legacy "first entry always admitted" behavior of
/// [MemoryInjectionBudget] so we don't regress on empty-result corner cases.
class MemorySelector {
  const MemorySelector._();

  /// Per-entry tokens used for budget calculation. Centralized so tests
  /// can stub the estimator without touching the selector.
  static int tokenCost(MemoryEntry entry) => estimateTokens(entry.content);

  static MemorySelection select(
    MemorySelectionInput input, {
    String Function(String key, String text)? keyMatcher,
    int Function(MemoryEntry entry)? tokenCounter,
  }) {
    final entries = input.entries
        .where((e) => e.status == 'active' && e.content.trim().isNotEmpty)
        .toList();

    if (entries.isEmpty) return const MemorySelection();

    final nowMillis = input.nowMillis ?? DateTime.now().millisecondsSinceEpoch;
    final costFn = tokenCounter ?? tokenCost;

    final visibleSet = input.visibleMessageIds;
    final legacyMode = input.selectionMode == 'legacy';

    final scored = <MemoryCandidateScore>[];
    for (final entry in entries) {
      if (!legacyMode &&
          input.sourceWindowExclusion &&
          entry.messageIds.isNotEmpty &&
          entry.messageIds.any(visibleSet.contains)) {
        scored.add(
          MemoryCandidateScore(
            entry: entry,
            score: 0,
            excludedBySourceWindow: true,
            exclusionReason: 'source_visible_in_prompt',
          ),
        );
        continue;
      }
      final matched = _matchedKeys(entry, input.keywordMatchedTerms);
      if (legacyMode) {
        final vector = (input.vectorScores[entry.id] ?? 0) * 5.0;
        final keyword = matched.isEmpty ? 0.0 : input.keywordWeight;
        final messageSource = entry.messageIds.isNotEmpty ? 2.0 : 0.0;
        final contentLength = entry.content.trim().length > 20 ? 1.0 : 0.0;
        scored.add(
          MemoryCandidateScore(
            entry: entry,
            score: keyword + vector + messageSource + contentLength,
            keywordScore: keyword,
            vectorScore: vector,
            matchedKeys: matched,
          ),
        );
        continue;
      }
      final vector = (input.vectorScores[entry.id] ?? 0) * input.vectorWeight;
      final keyword = matched.isEmpty
          ? 0.0
          : input.keywordWeight * _keywordBoost(matched, entry.keys.length);
      final catalog = input.catalogScores[entry.id] ?? 0;
      final recency = input.recencyBoost
          ? _recencyBoost(
              entry.createdAt,
              nowMillis,
              input.recencyHalfLifeDays,
              entry.temporallyBlind,
            )
          : 0.0;
      final importance = input.importanceBoost
          ? (entry.importance.clamp(0, 1)) * input.importanceWeight
          : 0.0;
      final baseline = entry.content.trim().length > 20 ? 0.5 : 0.0;
      final score =
          keyword + vector + catalog + recency + importance + baseline;
      scored.add(
        MemoryCandidateScore(
          entry: entry,
          score: score,
          keywordScore: keyword,
          vectorScore: vector,
          catalogScore: catalog,
          recencyScore: recency,
          importanceScore: importance,
          matchedKeys: matched,
          catalogMatchedTerms: input.catalogMatchedTerms[entry.id] ?? const [],
        ),
      );
    }

    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      // Deterministic tiebreaker: newer entries win, then by id.
      final at = a.entry.createdAt ?? 0;
      final bt = b.entry.createdAt ?? 0;
      if (at != bt) return bt.compareTo(at);
      return a.entry.id.compareTo(b.entry.id);
    });

    final picked = <MemoryCandidateScore>[];
    final seenTokens = <String>{};
    var usedTokens = 0;
    var trimmedByBudget = false;
    final cap = input.maxInjectedEntries.clamp(0, 64);
    final budget = input.maxInjectionTokens;

    for (final c in scored) {
      if (c.excludedBySourceWindow) continue;
      if (picked.length >= cap) break;
      final cost = costFn(c.entry);
      final wouldOverflow =
          budget != null && usedTokens + cost > budget && picked.isNotEmpty;
      if (wouldOverflow) {
        trimmedByBudget = true;
        break;
      }
      picked.add(c);
      usedTokens += cost;
      if (!legacyMode && input.diversityAware) {
        _accumulateDiversityTokens(c.entry, seenTokens);
        final penalty = _diversityPenaltyFor(
          c.entry,
          picked.sublist(0, picked.length - 1),
          seenTokens,
          input.diversityPenalty,
        );
        // Apply penalty in-place so diagnostics reflect the reranked score.
        final reranked = MemoryCandidateScore(
          entry: c.entry,
          score: c.score - penalty,
          keywordScore: c.keywordScore,
          vectorScore: c.vectorScore,
          catalogScore: c.catalogScore,
          recencyScore: c.recencyScore,
          importanceScore: c.importanceScore,
          diversityPenalty: penalty,
          matchedKeys: c.matchedKeys,
          catalogMatchedTerms: c.catalogMatchedTerms,
        );
        picked[picked.length - 1] = reranked;
        // Also stamp the reranked score into allScores so the diagnostic
        // surface reflects what was actually injected, not the pre-penalty
        // ranking score. Excluded entries keep their original 0.
        final idx = scored.indexWhere((s) => identical(s.entry, c.entry));
        if (idx >= 0) {
          scored[idx] = reranked;
        }
      }
    }

    return MemorySelection(
      selectionMode: legacyMode ? 'legacy' : 'v2',
      entries: picked.map((p) => p.entry).toList(growable: false),
      allScores: scored,
      totalTokens: usedTokens,
      budgetTokens: budget,
      entryCap: cap,
      budgetTrimmed: trimmedByBudget,
      excludedBySourceWindow: scored
          .where((s) => s.excludedBySourceWindow)
          .length,
    );
  }

  /// Default keyword matcher: case-insensitive substring across the
  /// entries' own keys. Used by the isolate path where the scan text
  /// is not precomputed.
  static List<String> defaultKeywordMatch(MemoryEntry entry, String scanText) {
    final text = scanText.toLowerCase();
    final matched = <String>[];
    for (final key in entry.keys) {
      if (key.isEmpty) continue;
      if (text.contains(key.toLowerCase())) matched.add(key);
    }
    return matched;
  }

  /// Recency boost: half-life decay; 0 if [temporallyBlind] or no timestamp.
  /// Returns a value in [0, 1] that callers can scale with recencyWeight.
  static double _recencyBoost(
    int? createdAtMs,
    int nowMs,
    double halfLifeDays,
    bool temporallyBlind,
  ) {
    if (temporallyBlind || createdAtMs == null || createdAtMs <= 0) return 0;
    if (halfLifeDays <= 0) return 0;
    final ageDays = (nowMs - createdAtMs) / 86400000.0;
    if (ageDays < 0) return 0;
    final halvings = ageDays / halfLifeDays;
    return 1.0 / (1.0 + halvings);
  }

  static double _keywordBoost(List<String> matched, int totalKeys) {
    if (matched.isEmpty) return 0;
    final t = totalKeys <= 0 ? matched.length : totalKeys;
    return (matched.length / t).clamp(0.0, 1.0);
  }

  static List<String> _matchedKeys(
    MemoryEntry entry,
    Map<String, List<String>> keywordMatchedTerms,
  ) {
    return keywordMatchedTerms[entry.id] ?? const [];
  }

  static void _accumulateDiversityTokens(MemoryEntry entry, Set<String> sink) {
    for (final token in _entryTokens(entry)) {
      sink.add(token);
    }
  }

  static double _diversityPenaltyFor(
    MemoryEntry candidate,
    List<MemoryCandidateScore> alreadyPicked,
    Set<String> seenTokens,
    double penalty,
  ) {
    if (alreadyPicked.isEmpty || penalty <= 0) return 0;
    final candTokens = _entryTokens(candidate);
    if (candTokens.isEmpty) return 0;
    var overlap = 0;
    for (final t in candTokens) {
      if (seenTokens.contains(t)) overlap++;
    }
    final ratio = overlap / candTokens.length;
    return penalty * ratio;
  }

  static Set<String> _entryTokens(MemoryEntry e) {
    final tokens = <String>{};
    final titleWords = e.title.toLowerCase().split(RegExp(r'[\s,.;:()]+'));
    final keyWords = e.keys.expand(
      (k) => k.toLowerCase().split(RegExp(r'[\s,.;:()]+')),
    );
    final arcWords = e.arc.toLowerCase().split(RegExp(r'[\s,.;:()]+'));
    for (final w in [...titleWords, ...keyWords, ...arcWords]) {
      if (w.length >= 3) tokens.add(w);
    }
    return tokens;
  }
}

/// Re-exports the glaze whole-word matcher for callers that want the
/// same key matching behavior the legacy code used in the async path.
bool memoryKeyMatchesGlaze(String key, String scanText) {
  return glazeCheckMatch(
    key,
    scanText.toLowerCase(),
    false,
    WholeWordMode.glaze,
  );
}
