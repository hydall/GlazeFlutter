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
  final MemoryDiagnostics diagnostics;

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
    var memoryMode = 'fast';
    var memorySettings = const MemoryBookSettings();
    MemoryCandidateBuildResult finish(
      MemorySelection selection,
      MemoryBudgetBreakdown budget,
    ) {
      sw.stop();
      return MemoryCandidateBuildResult(
        selection: selection,
        diagnostics: MemoryDiagnostics.fromSelection(
          selection,
          budget: budget,
          latencyMs: sw.elapsedMilliseconds,
          currentText: currentText,
          memoryMode: memoryMode,
          factualContinuityGuardEnabled:
              memorySettings.factualContinuityGuardEnabled,
        ),
      );
    }

    const noBudget = MemoryBudgetBreakdown(source: 'none');
    if (shouldAbort?.call() == true) {
      return finish(const MemorySelection(), noBudget);
    }
    debugPrint('[mem] buildCandidates: reading memory book...');
    final book = await _repo.getBySessionId(sessionId);
    if (shouldAbort?.call() == true) {
      return finish(const MemorySelection(), noBudget);
    }
    if (book == null) {
      debugPrint('[mem] no memory book found');
      return finish(const MemorySelection(), noBudget);
    }
    memoryMode = book.settings.memoryMode;
    memorySettings = book.settings;
    debugPrint('[mem] memory book loaded, entries=${book.entries.length}');

    final gs = _ref.read(memoryGlobalSettingsProvider);
    if (!gs.enabled) {
      debugPrint('[mem] memory disabled globally');
      return finish(const MemorySelection(), noBudget);
    }

    final activeEntries = book.entries
        .where((e) => e.status == 'active' && e.content.trim().isNotEmpty)
        .toList();
    debugPrint('[mem] active entries: ${activeEntries.length}');
    if (activeEntries.isEmpty) return finish(const MemorySelection(), noBudget);

    final vectorScores = <String, double>{};
    final catalogMatches = book.settings.memoryMode == 'balanced'
        ? await _catalogMatches(book, activeEntries, history, currentText)
        : const _CatalogMatchResult();
    if (shouldAbort?.call() == true) {
      return finish(const MemorySelection(), noBudget);
    }
    if (gs.vectorSearchEnabled &&
        embeddingConfig != null &&
        embeddingConfig.endpoint.isNotEmpty &&
        history.isNotEmpty) {
      debugPrint('[mem] starting vector search...');
      vectorScores.addAll(
        await _vectorSearchMemory(
          activeEntries,
          history,
          currentText,
          embeddingConfig,
          gs,
          shouldAbort: shouldAbort,
          cancelToken: cancelToken,
        ),
      );
      debugPrint('[mem] vector search done, scores=${vectorScores.length}');
    } else {
      debugPrint(
        '[mem] vector search skipped (enabled=${gs.vectorSearchEnabled}, endpoint=${embeddingConfig?.endpoint.isNotEmpty ?? false}, history=${history.isNotEmpty})',
      );
    }

    final budget = MemoryInjectionBudget.describeBudget(
      contextBudgetTokens: contextBudgetTokens,
      percent: book.settings.maxInjectionBudgetPercent,
      absoluteCap: book.settings.maxInjectedTokens,
    );

    final selection = MemorySelector.select(
      MemorySelectionInput(
        entries: activeEntries,
        vectorScores: vectorScores,
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
      ),
    );
    return finish(selection, budget);
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

    final maxInjectionTokens = selection.budgetTokens;
    final totalTokens = selection.totalTokens;
    final macroContent = selection.entries
        .map((e) => e.content.trim())
        .join('\n\n');

    final contentParts = <String>[];
    if (summaryExcerpt != null && summaryExcerpt.isNotEmpty) {
      contentParts.add('Summary excerpt:\n$summaryExcerpt');
    }
    contentParts.add('Memory context:');
    for (final entry in selection.entries) {
      final title = entry.title.isNotEmpty ? entry.title : 'Memory';
      contentParts.add('- $title: ${entry.content.trim()}');
    }

    final injectionTarget = gs.injectionTarget == 'macro'
        ? 'macro'
        : 'hard_block';

    return MemoryInjectionResult(
      entries: selection.entries,
      content: contentParts.join('\n\n'),
      injectionTarget: injectionTarget,
      macroContent: macroContent,
      totalTokens: totalTokens,
      maxInjectionTokens: maxInjectionTokens,
      budgetTrimmed: selection.budgetTrimmed,
      diagnostics: selection.allScores,
      memoryDiagnostics: candidateResult.diagnostics,
      excludedBySourceWindow: selection.excludedBySourceWindow,
      candidatesTotal: selection.allScores.length,
    );
  }

  Future<Map<String, double>> _vectorSearchMemory(
    List<MemoryEntry> entries,
    List<ChatMessage> history,
    String currentText,
    EmbeddingConfig config,
    MemoryGlobalSettings settings, {
    bool Function()? shouldAbort,
    CancelToken? cancelToken,
  }) async {
    try {
      if (shouldAbort?.call() == true) return {};
      debugPrint('[mem-vec] reading embeddings from DB...');
      final embeddingRows = await _embeddingRepo.getBySourceType(
        'memory_entry',
      );
      if (shouldAbort?.call() == true) return {};
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
        if (shouldAbort?.call() == true) return {};
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

        candidates.add(
          VectorCandidate(
            id: entry.id,
            vectors: vectors
                .map((v) => VectorChunk(text: '', vector: v))
                .toList(),
            metadata: {'hints': _embeddingRepo.decodeHints(row) ?? []},
          ),
        );
        debugPrint(
          '[mem-vec]   added candidate with ${vectors.length} vectors',
        );
      }
      debugPrint('[mem-vec] valid candidates: ${candidates.length}');

      if (candidates.isEmpty) return {};

      final queryText = RetrievalQueryBuilder.build(
        currentText: currentText,
        history: history,
        includeAssistant: settings.queryIncludeAssistant,
        recentTurns: settings.queryRecentTurns,
        maxChars: settings.queryMaxChars,
      );
      if (queryText.isEmpty) return {};
      if (shouldAbort?.call() == true) return {};

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
      if (cancelToken?.isCancelled == true) return {};
      debugPrint(
        '[mem-vec] embedding API returned ${queryChunks.length} chunks',
      );
      if (queryChunks.isEmpty) return {};

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
      return Map.fromEntries(
        results
            .where((r) => r.score >= threshold)
            .take(topK)
            .map((r) => MapEntry(r.id, r.score)),
      );
    } catch (_) {
      return {};
    }
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
