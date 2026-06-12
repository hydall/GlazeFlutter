import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/app_db.dart';
import '../db/repositories/embedding_repo.dart';
import '../db/repositories/memory_book_repo.dart';
import '../db/repositories/memory_catalog_repo.dart';
import '../models/chat_message.dart';
import '../models/memory_book.dart';
import '../state/db_provider.dart';
import '../state/memory_settings_provider.dart';
import 'embedding_service.dart';
import 'embedding_types.dart';
import 'memory_catalog_builder.dart';
import 'memory_budget.dart';
import 'memory_diagnostics.dart';
import 'memory_embedding_service.dart';
import 'memory_excerpt_selector.dart';
import 'memory_selector.dart';
import 'retrieval_query_builder.dart';
import 'vector_math.dart';

class MemoryInjectionResult {
  final List<MemoryEntry> entries;
  final String content;
  final String injectionTarget;
  final String macroContent;
  final int totalTokens;
  final int? maxInjectionTokens;
  final bool budgetTrimmed;
  final List<MemoryCandidateScore> diagnostics;
  final MemoryDiagnostics? memoryDiagnostics;
  final int excludedBySourceWindow;
  final int candidatesTotal;

  const MemoryInjectionResult({
    this.entries = const [],
    this.content = '',
    this.injectionTarget = 'hard_block',
    this.macroContent = '',
    this.totalTokens = 0,
    this.maxInjectionTokens,
    this.budgetTrimmed = false,
    this.diagnostics = const [],
    this.memoryDiagnostics,
    this.excludedBySourceWindow = 0,
    this.candidatesTotal = 0,
  });
}

class MemoryCandidateBuildResult {
  final MemorySelection selection;
  final MemoryDiagnostics? diagnostics;

  const MemoryCandidateBuildResult({
    required this.selection,
    required this.diagnostics,
  });
}

class MemoryInjectionService {
  final MemoryBookRepo _repo;
  final EmbeddingRepo _embeddingRepo;
  final MemoryCatalogRepo _catalogRepo;
  final EmbeddingService _embeddingService;
  final Ref _ref;

  MemoryInjectionService(
    this._repo,
    this._embeddingRepo,
    this._catalogRepo,
    this._embeddingService,
    this._ref,
  );

  /// Build injection candidates + diagnostics. Returns the raw selection
  /// (with source-window exclusion applied) plus all scored candidates
  /// for visibility. The caller is responsible for token-budget
  /// re-finalization if the prompt-window cutoff is known after this
  /// call (see [finalizeWithVisibleWindow]).
  Future<MemorySelection> buildCandidates({
    required String sessionId,
    required List<ChatMessage> history,
    required String currentText,
    EmbeddingConfig? embeddingConfig,
    bool Function()? shouldAbort,
    CancelToken? cancelToken,
    int? contextBudgetTokens,
    Set<String> visibleMessageIds = const {},
  }) async {
    final result = await buildCandidatesWithDiagnostics(
      sessionId: sessionId,
      history: history,
      currentText: currentText,
      embeddingConfig: embeddingConfig,
      shouldAbort: shouldAbort,
      cancelToken: cancelToken,
      contextBudgetTokens: contextBudgetTokens,
      visibleMessageIds: visibleMessageIds,
    );
    return result.selection;
  }

  Future<MemoryCandidateBuildResult> buildCandidatesWithDiagnostics({
    required String sessionId,
    required List<ChatMessage> history,
    required String currentText,
    EmbeddingConfig? embeddingConfig,
    bool Function()? shouldAbort,
    CancelToken? cancelToken,
    int? contextBudgetTokens,
    Set<String> visibleMessageIds = const {},
  }) async {
    final sw = Stopwatch()..start();
    MemoryCandidateBuildResult finish(
      MemorySelection selection, {
      MemoryBudgetBreakdown budget = const MemoryBudgetBreakdown(
        source: 'none',
      ),
      MemoryBookSettings? settings,
    }) {
      sw.stop();
      final resolvedSettings = settings ?? const MemoryBookSettings();
      return MemoryCandidateBuildResult(
        selection: selection,
        diagnostics: settings == null
            ? null
            : MemoryDiagnostics.fromSelection(
                selection,
                budget: budget,
                latencyMs: sw.elapsedMilliseconds,
                currentText: currentText,
                memoryMode: resolvedSettings.memoryMode,
                factualContinuityGuardEnabled:
                    resolvedSettings.factualContinuityGuardEnabled,
              ),
      );
    }

    if (shouldAbort?.call() == true) {
      return finish(const MemorySelection());
    }
    debugPrint('[mem] buildCandidates: reading memory book...');
    final book = await _repo.getBySessionId(sessionId);
    if (shouldAbort?.call() == true) {
      return finish(const MemorySelection());
    }
    if (book == null) {
      debugPrint('[mem] no memory book found');
      return finish(const MemorySelection());
    }
    debugPrint('[mem] memory book loaded, entries=${book.entries.length}');

    final gs = _ref.read(memoryGlobalSettingsProvider);
    if (!gs.enabled || !book.settings.enabled) {
      debugPrint('[mem] memory disabled');
      return finish(const MemorySelection());
    }

    final activeEntries = book.entries
        .where((e) => e.status == 'active' && e.content.trim().isNotEmpty)
        .toList();
    debugPrint('[mem] active entries: ${activeEntries.length}');
    if (activeEntries.isEmpty) return finish(const MemorySelection());

    var vectorMatches = const _MemoryVectorMatchResult();
    final keywordMatchedTerms = _keywordMatches(
      activeEntries,
      _selectorScanText(book.settings, history, currentText),
      book.settings.keyMatchMode,
    );
    final catalogMatches = book.settings.memoryMode == 'balanced'
        ? await _catalogMatches(book, activeEntries, history, currentText)
        : const _CatalogMatchResult();
    if (shouldAbort?.call() == true) {
      return finish(const MemorySelection(), settings: book.settings);
    }
    if (gs.vectorSearchEnabled &&
        embeddingConfig != null &&
        embeddingConfig.endpoint.isNotEmpty &&
        history.isNotEmpty) {
      debugPrint('[mem] starting vector search...');
      vectorMatches = await _vectorSearchMemory(
        activeEntries,
        history,
        currentText,
        embeddingConfig,
        gs,
        shouldAbort: shouldAbort,
        cancelToken: cancelToken,
      );
      debugPrint(
        '[mem] vector search done, scores=${vectorMatches.scores.length}',
      );
    } else {
      debugPrint(
        '[mem] vector search skipped (enabled=${gs.vectorSearchEnabled}, endpoint=${embeddingConfig?.endpoint.isNotEmpty ?? false}, history=${history.isNotEmpty})',
      );
    }

    final budget = MemoryInjectionBudget.describeBudget(
      contextBudgetTokens: contextBudgetTokens,
      percent: book.settings.maxInjectionBudgetPercent,
      absoluteCap: book.settings.memoryMode == 'legacy'
          ? null
          : book.settings.maxInjectedTokens,
    );

    final selection = MemorySelector.select(
      MemorySelectionInput(
        selectionMode: book.settings.memoryMode == 'legacy' ? 'legacy' : 'v2',
        entries: activeEntries,
        vectorScores: vectorMatches.scores,
        vectorMatchedChunks: vectorMatches.chunksByEntryId,
        keywordMatchedTerms: keywordMatchedTerms,
        catalogScores: catalogMatches.scores,
        catalogMatchedTerms: catalogMatches.termsByEntryId,
        visibleMessageIds: visibleMessageIds,
        maxInjectionTokens: budget.effectiveTokens,
        maxInjectedEntries: book.settings.maxInjectedEntries,
        diversityAware: book.settings.diversityAware,
        diversityPenalty: book.settings.diversityPenalty,
        recencyBoost: book.settings.recencyBoost,
        recencyHalfLifeDays: book.settings.recencyHalfLifeDays,
        importanceBoost: book.settings.importanceBoost,
        importanceWeight: book.settings.importanceWeight,
        sourceWindowExclusion: book.settings.sourceWindowExclusion,
        currentMessageIndex: history.length,
      ),
    );
    return finish(selection, budget: budget, settings: book.settings);
  }

  /// Backwards-compatible facade for callers that still expect an
  /// assembled injection payload in one shot (tokenizer sheet, etc.).
  Future<MemoryInjectionResult> buildInjection({
    required String sessionId,
    required String historyText,
    required int messageCount,
    String? summaryExcerpt,
    List<ChatMessageForSearch>? history,
    String? currentText,
    EmbeddingConfig? embeddingConfig,
    bool Function()? shouldAbort,
    CancelToken? cancelToken,
    int? contextBudgetTokens,
    Set<String> visibleMessageIds = const {},
  }) async {
    final chatHistory = (history ?? const [])
        .map((m) => ChatMessage(id: '', role: m.role, content: m.content))
        .toList();
    final gs = _ref.read(memoryGlobalSettingsProvider);

    final candidateResult = await buildCandidatesWithDiagnostics(
      sessionId: sessionId,
      history: chatHistory,
      currentText: currentText ?? '',
      embeddingConfig: embeddingConfig,
      shouldAbort: shouldAbort,
      cancelToken: cancelToken,
      contextBudgetTokens: contextBudgetTokens,
      visibleMessageIds: visibleMessageIds,
    );
    final selection = candidateResult.selection;

    if (selection.entries.isEmpty) {
      return MemoryInjectionResult(
        diagnostics: selection.allScores,
        memoryDiagnostics: candidateResult.diagnostics,
        excludedBySourceWindow: selection.excludedBySourceWindow,
        candidatesTotal: selection.allScores.length,
        maxInjectionTokens: selection.budgetTokens,
      );
    }

    final excerptSelection = gs.memoryExcerptingEnabled
        ? MemoryExcerptSelector.select(
            selection,
            packingMode: gs.memoryPackingMode,
          )
        : MemoryExcerptSelector.fullEntries(selection);
    final maxInjectionTokens = selection.budgetTokens;
    final totalTokens = excerptSelection.totalTokens;
    final macroContent = _formatMemoryItems(
      excerptSelection.items,
      includeContextHeader: false,
    );

    final contentParts = <String>[];
    if (summaryExcerpt != null && summaryExcerpt.isNotEmpty) {
      contentParts.add('Summary excerpt:\n$summaryExcerpt');
    }
    contentParts.add(
      _formatMemoryItems(excerptSelection.items, includeContextHeader: true),
    );

    final injectionTarget = gs.injectionTarget == 'macro'
        ? 'macro'
        : 'hard_block';

    return MemoryInjectionResult(
      entries: excerptSelection.entries,
      content: contentParts.join('\n\n'),
      injectionTarget: injectionTarget,
      macroContent: macroContent,
      totalTokens: totalTokens,
      maxInjectionTokens: maxInjectionTokens,
      budgetTrimmed: excerptSelection.budgetTrimmed,
      diagnostics: selection.allScores,
      memoryDiagnostics: candidateResult.diagnostics,
      excludedBySourceWindow: selection.excludedBySourceWindow,
      candidatesTotal: selection.allScores.length,
    );
  }

  Future<_MemoryVectorMatchResult> _vectorSearchMemory(
    List<MemoryEntry> entries,
    List<ChatMessage> history,
    String currentText,
    EmbeddingConfig config,
    MemoryGlobalSettings settings, {
    bool Function()? shouldAbort,
    CancelToken? cancelToken,
  }) async {
    try {
      if (shouldAbort?.call() == true) return const _MemoryVectorMatchResult();
      debugPrint('[mem-vec] reading embeddings from DB...');
      final embeddingRows = await _embeddingRepo.getBySourceType(
        'memory_entry',
      );
      if (shouldAbort?.call() == true) return const _MemoryVectorMatchResult();
      final embeddingMap = <String, EmbeddingRow>{};
      for (final row in embeddingRows) {
        embeddingMap[row.entryId] = row;
      }
      debugPrint('[mem-vec] loaded ${embeddingRows.length} embedding rows');

      final candidates = <VectorCandidate>[];
      for (int i = 0; i < entries.length; i++) {
        final entry = entries[i];
        debugPrint(
          '[mem-vec] processing entry ${i + 1}/${entries.length}: id=${entry.id}',
        );
        final row = embeddingMap[entry.id];
        if (shouldAbort?.call() == true) {
          return const _MemoryVectorMatchResult();
        }
        if (row == null || !_embeddingRepo.hasUsableVectors(row)) {
          debugPrint('[mem-vec]   skipped: no row or no vectorsBlob');
          continue;
        }

        final text = entry.content;
        final hints = MemoryEmbeddingService.extractMemoryRetrievalHints(entry);
        final fingerprint = jsonEncode({'text': text, 'retrievalHints': hints});
        final currentHash = sha256.convert(utf8.encode(fingerprint)).toString();
        if (row.textHash != currentHash) {
          debugPrint('[mem-vec]   skipped: hash mismatch');
          continue;
        }

        final vectors = _embeddingRepo.decodeVectors(row);
        if (vectors == null || vectors.isEmpty) {
          debugPrint('[mem-vec]   skipped: vectors null or empty');
          continue;
        }
        final chunkTexts = _decodeMemoryChunkTexts(row, vectors.length);

        candidates.add(
          VectorCandidate(
            id: entry.id,
            vectors: vectors
                .asMap()
                .entries
                .map(
                  (v) => VectorChunk(
                    text: v.key < chunkTexts.length ? chunkTexts[v.key] : '',
                    vector: v.value,
                  ),
                )
                .toList(),
            metadata: {
              'hints': _embeddingRepo.decodeHints(row) ?? [],
              'chunkTexts': chunkTexts,
            },
          ),
        );
        debugPrint(
          '[mem-vec]   added candidate with ${vectors.length} vectors',
        );
      }
      debugPrint('[mem-vec] valid candidates: ${candidates.length}');

      if (candidates.isEmpty) return const _MemoryVectorMatchResult();

      final queryText = settings.memoryMode == 'legacy'
          ? _legacyVectorQuery(history, currentText)
          : RetrievalQueryBuilder.build(
              currentText: currentText,
              history: history,
              includeAssistant: settings.queryIncludeAssistant,
              recentTurns: settings.queryRecentTurns,
              maxChars: settings.queryMaxChars,
            );
      if (queryText.isEmpty) return const _MemoryVectorMatchResult();
      if (shouldAbort?.call() == true) return const _MemoryVectorMatchResult();

      debugPrint(
        '[mem-vec] calling embedding API (endpoint=${config.endpoint})...',
      );
      final queryChunks = await _embeddingService
          .getEmbeddingsWithChunks(
            [queryText],
            config,
            cancelToken: cancelToken,
          )
          .timeout(const Duration(seconds: 15), onTimeout: () => []);
      if (cancelToken?.isCancelled == true) {
        return const _MemoryVectorMatchResult();
      }
      debugPrint(
        '[mem-vec] embedding API returned ${queryChunks.length} chunks',
      );
      if (queryChunks.isEmpty) return const _MemoryVectorMatchResult();

      final queryVecChunks = queryChunks
          .map((c) => VectorChunk(text: c.text, vector: c.vector))
          .toList();
      final results = findTopKMulti(
        queryVecChunks,
        candidates,
        candidates.length,
        0,
      );

      final threshold = settings.vectorThreshold;
      final topK = settings.maxInjectedEntries.clamp(1, 50);
      final scores = <String, double>{};
      final chunksByEntryId = <String, List<String>>{};
      for (final result
          in results.where((r) => r.score >= threshold).take(topK)) {
        scores[result.id] = result.score;
        final chunkTexts = result.metadata['chunkTexts'];
        if (chunkTexts is List && result.bestCandidateChunk != null) {
          final bestIndex = result.bestCandidateChunk!;
          final matched = <String>[];
          if (bestIndex >= 0 && bestIndex < chunkTexts.length) {
            final text = chunkTexts[bestIndex];
            if (text is String && text.trim().isNotEmpty) matched.add(text);
          }
          final neighboringIndexes = [bestIndex - 1, bestIndex + 1];
          for (final index in neighboringIndexes) {
            if (index < 0 || index >= chunkTexts.length) continue;
            final text = chunkTexts[index];
            if (text is String && text.trim().isNotEmpty) matched.add(text);
          }
          if (matched.isNotEmpty) chunksByEntryId[result.id] = matched;
        }
      }
      return _MemoryVectorMatchResult(
        scores: scores,
        chunksByEntryId: chunksByEntryId,
      );
    } catch (_) {
      return const _MemoryVectorMatchResult();
    }
  }

  List<String> _decodeMemoryChunkTexts(EmbeddingRow row, int vectorCount) {
    final metadata = _embeddingRepo.decodeMetadata(row);
    final chunks = metadata?['chunks'];
    if (chunks is! List) return const [];
    final texts = List<String>.filled(vectorCount, '');
    for (final chunk in chunks) {
      if (chunk is! Map) continue;
      final indexRaw = chunk['index'];
      final textRaw = chunk['text'];
      if (indexRaw is! num || textRaw is! String) continue;
      final index = indexRaw.toInt();
      if (index < 0 || index >= texts.length) continue;
      texts[index] = textRaw;
    }
    return texts;
  }

  Future<_CatalogMatchResult> _catalogMatches(
    MemoryBook book,
    List<MemoryEntry> activeEntries,
    List<ChatMessage> history,
    String currentText,
  ) async {
    try {
      var rows = await _catalogRepo.getBySessionId(book.sessionId);
      final activeIds = activeEntries.map((entry) => entry.id).toSet();
      final usableRows = rows
          .where(
            (row) =>
                activeIds.contains(row.memoryEntryId) &&
                row.status == 'active' &&
                !row.stale,
          )
          .toList(growable: false);
      if (usableRows.length != activeEntries.length) {
        rows = await _catalogRepo.rebuildForMemoryBook(book);
      }

      final scanText = RetrievalQueryBuilder.build(
        currentText: currentText,
        history: history,
        includeAssistant: book.settings.queryIncludeAssistant,
        recentTurns: book.settings.queryRecentTurns,
        maxChars: book.settings.queryMaxChars,
      ).toLowerCase();
      if (scanText.isEmpty) return const _CatalogMatchResult();

      final activeMap = {for (final entry in activeEntries) entry.id: entry};
      final scores = <String, double>{};
      final termsByEntryId = <String, List<String>>{};
      for (final row in rows) {
        final entry = activeMap[row.memoryEntryId];
        if (entry == null || row.status != 'active' || row.stale) continue;
        final matched = _matchedCatalogTerms(row, scanText);
        if (matched.isEmpty) continue;
        termsByEntryId[row.memoryEntryId] = matched;
        scores[row.memoryEntryId] = _catalogScore(matched, row);
      }
      return _CatalogMatchResult(
        scores: scores,
        termsByEntryId: termsByEntryId,
      );
    } catch (_) {
      return const _CatalogMatchResult();
    }
  }

  static String _legacyVectorQuery(
    List<ChatMessage> history,
    String currentText,
  ) {
    final parts = <String>[];
    if (currentText.trim().isNotEmpty) parts.add(currentText.trim());
    var chars = parts.fold<int>(0, (sum, part) => sum + part.length);
    for (int i = history.length - 1; i >= 0; i--) {
      final msg = history[i];
      if (msg.isHidden || msg.isTyping || msg.role != 'user') continue;
      final text = msg.content.trim();
      if (text.isEmpty || text == currentText.trim()) continue;
      if (chars + text.length > 1500) break;
      parts.add(text);
      chars += text.length;
    }
    return parts.join('\n').trim();
  }

  static String _selectorScanText(
    MemoryBookSettings settings,
    List<ChatMessage> history,
    String currentText,
  ) {
    if (settings.memoryMode == 'legacy') {
      return _legacyVectorQuery(history, currentText).toLowerCase();
    }
    return RetrievalQueryBuilder.build(
      currentText: currentText,
      history: history,
      includeAssistant: settings.queryIncludeAssistant,
      recentTurns: settings.queryRecentTurns,
      maxChars: settings.queryMaxChars,
    ).toLowerCase();
  }

  static Map<String, List<String>> _keywordMatches(
    List<MemoryEntry> entries,
    String scanText,
    String keyMatchMode,
  ) {
    if (scanText.isEmpty) return const {};
    final matchedByEntry = <String, List<String>>{};
    for (final entry in entries) {
      final matched = <String>[];
      for (final key in entry.keys) {
        if (key.trim().isEmpty) continue;
        final lowerKey = key.toLowerCase();
        final hit = switch (keyMatchMode) {
          'glaze' => memoryKeyMatchesGlaze(lowerKey, scanText),
          'both' =>
            scanText.contains(lowerKey) ||
                memoryKeyMatchesGlaze(lowerKey, scanText),
          _ => scanText.contains(lowerKey),
        };
        if (hit) matched.add(key);
      }
      if (matched.isNotEmpty) matchedByEntry[entry.id] = matched;
    }
    return matchedByEntry;
  }

  static List<String> _matchedCatalogTerms(
    MemoryCatalogRow row,
    String scanText,
  ) {
    final terms = <String>{
      ...row.keys,
      ...row.entities,
      ...row.locations,
      ...row.topics,
      row.title,
    };
    final matched = <String>[];
    for (final raw in terms) {
      final term = raw.trim().toLowerCase();
      if (term.length < 3) continue;
      if (scanText.contains(term)) matched.add(raw.trim());
    }
    matched.sort();
    return matched;
  }

  static double _catalogScore(List<String> matched, MemoryCatalogRow row) {
    final tokenFactor = row.tokenCount <= 0
        ? 1.0
        : 1.0 / (1.0 + row.tokenCount / 8000);
    final importance = row.importance.clamp(0, 1) * 0.5;
    return (matched.length.clamp(1, 6) * 0.75 + importance) * tokenFactor;
  }
}

class _MemoryVectorMatchResult {
  final Map<String, double> scores;
  final Map<String, List<String>> chunksByEntryId;

  const _MemoryVectorMatchResult({
    this.scores = const {},
    this.chunksByEntryId = const {},
  });
}

class _CatalogMatchResult {
  final Map<String, double> scores;
  final Map<String, List<String>> termsByEntryId;

  const _CatalogMatchResult({
    this.scores = const {},
    this.termsByEntryId = const {},
  });
}

final memoryInjectionServiceProvider = Provider<MemoryInjectionService>((ref) {
  return MemoryInjectionService(
    ref.watch(memoryBookRepoProvider),
    ref.watch(embeddingRepoProvider),
    ref.watch(memoryCatalogRepoProvider),
    EmbeddingService(),
    ref,
  );
});

final memoryEmbeddingServiceProvider = Provider<MemoryEmbeddingService>((ref) {
  return MemoryEmbeddingService(
    ref.watch(embeddingRepoProvider),
    EmbeddingService(),
  );
});

String _formatMemoryItems(
  List<MemoryInjectionItem> items, {
  required bool includeContextHeader,
}) {
  final parts = <String>[];
  if (includeContextHeader) parts.add('Memory context:');
  for (final item in items) {
    final title = item.entry.title.isNotEmpty
        ? item.entry.title
        : _formatMemoryRange(item.entry) ?? 'Memory';
    final range = _formatMemoryRange(item.entry);
    final heading = range == null
        ? 'Memory: $title'
        : 'Memory: $title ($range)';
    if (item.excerpt) {
      parts.add(
        '$heading\n${item.text.trim()}\n[Excerpted from a larger Memory Book entry]',
      );
    } else {
      parts.add('$heading\n${item.text.trim()}');
    }
  }
  return parts.where((part) => part.trim().isNotEmpty).join('\n\n');
}

String? _formatMemoryRange(MemoryEntry entry) {
  final range = entry.messageRange;
  if (range == null) return null;
  return '${range.start}-${range.end}';
}
