import '../models/memory_book.dart';
import 'memory_selector.dart';
import 'tokenizer.dart';

const defaultMemoryExcerptTokensPerEntry = 500;
const defaultMemoryExcerptChunksPerEntry = 2;

class MemoryInjectionItem {
  final MemoryEntry entry;
  final bool excerpt;
  final String text;
  final int tokenCost;
  final int originalTokenCost;
  final List<int> chunkIndexes;
  final List<String> matchedTerms;
  final String reason;

  const MemoryInjectionItem({
    required this.entry,
    required this.excerpt,
    required this.text,
    required this.tokenCost,
    required this.originalTokenCost,
    this.chunkIndexes = const [],
    this.matchedTerms = const [],
    this.reason = 'full_entry',
  });
}

class MemoryExcerptSelection {
  final List<MemoryInjectionItem> items;
  final int totalTokens;
  final bool budgetTrimmed;

  const MemoryExcerptSelection({
    this.items = const [],
    this.totalTokens = 0,
    this.budgetTrimmed = false,
  });

  List<MemoryEntry> get entries => items.map((item) => item.entry).toList();
}

class MemoryExcerptSelector {
  const MemoryExcerptSelector._();

  static MemoryExcerptSelection fullEntries(MemorySelection selection) {
    final items = selection.entries
        .map(
          (entry) => MemoryInjectionItem(
            entry: entry,
            excerpt: false,
            text: entry.content.trim(),
            tokenCost: estimateTokens(entry.content),
            originalTokenCost: estimateTokens(entry.content),
          ),
        )
        .toList(growable: false);
    return MemoryExcerptSelection(
      items: items,
      totalTokens: items.fold<int>(0, (sum, item) => sum + item.tokenCost),
      budgetTrimmed: selection.budgetTrimmed,
    );
  }

  static MemoryExcerptSelection select(
    MemorySelection selection, {
    int maxExcerptTokensPerEntry = defaultMemoryExcerptTokensPerEntry,
    int maxExcerptChunksPerEntry = defaultMemoryExcerptChunksPerEntry,
    int Function(String text)? tokenCounter,
  }) {
    final tokenFn = tokenCounter ?? estimateTokens;
    final budget = selection.budgetTokens;
    final selectedIds = selection.entries.map((entry) => entry.id).toSet();
    final selectedFullTokens = selection.entries.fold<int>(
      0,
      (sum, entry) => sum + tokenFn(entry.content),
    );

    if (budget == null || selectedFullTokens <= budget) {
      return MemoryExcerptSelection(
        items: selection.entries
            .map(
              (entry) => MemoryInjectionItem(
                entry: entry,
                excerpt: false,
                text: entry.content.trim(),
                tokenCost: tokenFn(entry.content),
                originalTokenCost: tokenFn(entry.content),
              ),
            )
            .toList(growable: false),
        totalTokens: selectedFullTokens,
        budgetTrimmed: selection.budgetTrimmed,
      );
    }

    final cap = selection.entryCap > 0
        ? selection.entryCap
        : selection.entries.length;
    final items = <MemoryInjectionItem>[];
    var usedTokens = 0;
    var trimmed = selection.budgetTrimmed;

    for (final score in selection.allScores) {
      if (score.excludedBySourceWindow) continue;
      if (items.length >= cap) break;
      final entry = score.entry;
      final fullText = entry.content.trim();
      if (fullText.isEmpty) continue;
      final fullTokens = tokenFn(fullText);

      if (usedTokens + fullTokens <= budget) {
        items.add(
          MemoryInjectionItem(
            entry: entry,
            excerpt: false,
            text: fullText,
            tokenCost: fullTokens,
            originalTokenCost: fullTokens,
          ),
        );
        usedTokens += fullTokens;
        continue;
      }

      final remaining = budget - usedTokens;
      if (remaining <= 0 && items.isNotEmpty) {
        trimmed = true;
        continue;
      }

      final perEntryBudget = budget <= 0
          ? 0
          : items.isEmpty
          ? maxExcerptTokensPerEntry.clamp(1, budget)
          : maxExcerptTokensPerEntry.clamp(1, remaining);
      final excerpt = _buildExcerpt(
        score,
        maxTokens: perEntryBudget,
        maxChunks: maxExcerptChunksPerEntry,
        tokenCounter: tokenFn,
      );

      if (excerpt == null) {
        if (items.isEmpty && selectedIds.contains(entry.id)) {
          items.add(
            MemoryInjectionItem(
              entry: entry,
              excerpt: false,
              text: fullText,
              tokenCost: fullTokens,
              originalTokenCost: fullTokens,
              reason: 'first_entry_fallback',
            ),
          );
          usedTokens += fullTokens;
        } else {
          trimmed = true;
        }
        continue;
      }

      if (usedTokens + excerpt.tokenCost <= budget || items.isEmpty) {
        items.add(excerpt);
        usedTokens += excerpt.tokenCost;
      } else {
        trimmed = true;
      }
    }

    return MemoryExcerptSelection(
      items: items,
      totalTokens: usedTokens,
      budgetTrimmed: trimmed,
    );
  }

  static MemoryInjectionItem? _buildExcerpt(
    MemoryCandidateScore score, {
    required int maxTokens,
    required int maxChunks,
    required int Function(String text) tokenCounter,
  }) {
    if (maxTokens <= 0 || maxChunks <= 0) return null;
    final chunks = _chunk(score.entry.content, maxTokens, tokenCounter);
    if (chunks.isEmpty) return null;
    final terms = _termsFor(score);
    final ranked =
        chunks
            .map(
              (chunk) => _ScoredChunk(
                chunk,
                _scoreChunk(chunk.text, terms) +
                    _vectorChunkBoost(chunk.text, score.vectorMatchedChunks),
              ),
            )
            .toList(growable: false)
          ..sort((a, b) {
            final byScore = b.score.compareTo(a.score);
            if (byScore != 0) return byScore;
            return a.chunk.index.compareTo(b.chunk.index);
          });

    final picked = <_ExcerptChunk>[];
    var used = 0;
    for (final rankedChunk in ranked) {
      if (picked.length >= maxChunks) break;
      final chunk = rankedChunk.chunk;
      if (used + chunk.tokenCost > maxTokens && picked.isNotEmpty) continue;
      picked.add(chunk);
      used += chunk.tokenCost;
    }
    if (picked.isEmpty) return null;
    picked.sort((a, b) => a.index.compareTo(b.index));
    final text = picked.map((chunk) => chunk.text).join('\n\n').trim();
    if (text.isEmpty) return null;
    final matched = terms
        .where((term) => text.toLowerCase().contains(term))
        .toList(growable: false);
    return MemoryInjectionItem(
      entry: score.entry,
      excerpt: true,
      text: text,
      tokenCost: tokenCounter(text),
      originalTokenCost: tokenCounter(score.entry.content),
      chunkIndexes: picked.map((chunk) => chunk.index).toList(growable: false),
      matchedTerms: matched,
      reason: 'over_budget_excerpt',
    );
  }

  static List<_ExcerptChunk> _chunk(
    String content,
    int maxTokens,
    int Function(String text) tokenCounter,
  ) {
    final blocks = content
        .split(RegExp(r'\n\s*\n+'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    final chunks = <_ExcerptChunk>[];
    var index = 0;
    for (final block in blocks) {
      final tokenCost = tokenCounter(block);
      if (tokenCost <= maxTokens) {
        chunks.add(_ExcerptChunk(index++, block, tokenCost));
        continue;
      }
      final sentences = _sentences(block);
      var window = <String>[];
      for (final sentence in sentences) {
        final candidate = [...window, sentence].join(' ').trim();
        if (candidate.isEmpty) continue;
        if (tokenCounter(candidate) > maxTokens && window.isNotEmpty) {
          final text = window.join(' ').trim();
          chunks.add(_ExcerptChunk(index++, text, tokenCounter(text)));
          window = [sentence];
        } else if (tokenCounter(candidate) > maxTokens) {
          final words = sentence.split(RegExp(r'\s+'));
          final shortText = words.take(maxTokens * 3).join(' ').trim();
          if (shortText.isNotEmpty) {
            chunks.add(
              _ExcerptChunk(index++, shortText, tokenCounter(shortText)),
            );
          }
          window = [];
        } else {
          window.add(sentence);
        }
      }
      if (window.isNotEmpty) {
        final text = window.join(' ').trim();
        chunks.add(_ExcerptChunk(index++, text, tokenCounter(text)));
      }
    }
    return chunks;
  }

  static List<String> _sentences(String text) {
    final matches = RegExp(r'[^.!?\n]+(?:[.!?]+|$)').allMatches(text);
    final sentences = matches
        .map((match) => match.group(0)?.trim() ?? '')
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    return sentences.isEmpty ? [text.trim()] : sentences;
  }

  static Set<String> _termsFor(MemoryCandidateScore score) {
    final raw = <String>[
      ...score.matchedKeys,
      ...score.catalogMatchedTerms,
      ...score.entry.keys,
      score.entry.title,
      score.entry.arc,
    ];
    final terms = <String>{};
    for (final value in raw) {
      for (final token in value.toLowerCase().split(
        RegExp(r'[^\p{L}\p{N}_]+', unicode: true),
      )) {
        if (token.length >= 3) terms.add(token);
      }
    }
    return terms;
  }

  static double _vectorChunkBoost(String text, List<String> vectorChunks) {
    if (vectorChunks.isEmpty) return 0;
    final lower = text.toLowerCase();
    for (final vectorChunk in vectorChunks) {
      final chunk = vectorChunk.trim().toLowerCase();
      if (chunk.isEmpty) continue;
      if (lower.contains(chunk) || chunk.contains(lower)) return 100.0;
      final chunkTerms = chunk
          .split(RegExp(r'[^\p{L}\p{N}_]+', unicode: true))
          .where((term) => term.length >= 4)
          .toSet();
      if (chunkTerms.isEmpty) continue;
      final overlap = chunkTerms.where(lower.contains).length;
      if (overlap > 0) return overlap.clamp(0, 12) * 2.0;
    }
    return 0;
  }

  static double _scoreChunk(String text, Set<String> terms) {
    final lower = text.toLowerCase();
    var score = 0.0;
    for (final term in terms) {
      if (lower.contains(term)) score += 2.0;
    }
    for (final durable in _durableTerms) {
      if (lower.contains(durable)) score += 0.5;
    }
    if (RegExp(r'\b[A-Z][a-z]{2,}\b').hasMatch(text)) score += 0.35;
    if (RegExp(r'\d').hasMatch(text)) score += 0.2;
    if (text.length < 40) score -= 0.2;
    return score;
  }

  static const _durableTerms = <String>{
    'promise',
    'promised',
    'secret',
    'injury',
    'wound',
    'debt',
    'map',
    'ritual',
    'location',
    'relationship',
    'trust',
  };
}

class _ExcerptChunk {
  final int index;
  final String text;
  final int tokenCost;

  const _ExcerptChunk(this.index, this.text, this.tokenCost);
}

class _ScoredChunk {
  final _ExcerptChunk chunk;
  final double score;

  const _ScoredChunk(this.chunk, this.score);
}
