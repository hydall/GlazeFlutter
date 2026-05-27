import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/app_db.dart';
import '../db/repositories/embedding_repo.dart';
import '../db/repositories/memory_book_repo.dart';
import '../models/memory_book.dart';
import '../state/db_provider.dart';
import '../state/memory_settings_provider.dart';
import 'embedding_service.dart';
import 'glaze_matcher.dart';
import 'embedding_types.dart';
import 'memory_embedding_service.dart';
import 'vector_math.dart';

class MemoryInjectionResult {
  final List<MemoryEntry> entries;
  final String content;
  final String injectionTarget;
  final String macroContent;

  const MemoryInjectionResult({
    this.entries = const [],
    this.content = '',
    this.injectionTarget = 'summary_block',
    this.macroContent = '',
  });
}

class MemoryInjectionService {
  final MemoryBookRepo _repo;
  final EmbeddingRepo _embeddingRepo;
  final EmbeddingService _embeddingService;
  final Ref _ref;

  MemoryInjectionService(this._repo, this._embeddingRepo, this._embeddingService, this._ref);

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
  }) async {
    if (shouldAbort?.call() == true) return const MemoryInjectionResult();
    debugPrint('[mem] buildInjection: reading memory book...');
    final book = await _repo.getBySessionId(sessionId);
    if (shouldAbort?.call() == true) return const MemoryInjectionResult();
    if (book == null) { debugPrint('[mem] no memory book found'); return const MemoryInjectionResult(); }
    debugPrint('[mem] memory book loaded, entries=${book.entries.length}');

    final gs = _ref.read(memoryGlobalSettingsProvider);
    if (!gs.enabled) { debugPrint('[mem] memory disabled globally'); return const MemoryInjectionResult(); }

    final activeEntries = book.entries
        .where((e) => (e.status == 'active') && e.content.trim().isNotEmpty)
        .toList();
    debugPrint('[mem] active entries: ${activeEntries.length}');

    if (activeEntries.isEmpty) return const MemoryInjectionResult();

    final scanText = historyText.toLowerCase();
    final keywordMatched = <String>{};

    for (final entry in activeEntries) {
      for (final key in entry.keys) {
        if (key.isEmpty) continue;
        if (gs.keyMatchMode == 'glaze') {
          if (_glazeMatch(key, scanText)) keywordMatched.add(entry.id);
        } else if (gs.keyMatchMode == 'both') {
          if (scanText.contains(key.toLowerCase()) || _glazeMatch(key, scanText)) {
            keywordMatched.add(entry.id);
          }
        } else {
          if (scanText.contains(key.toLowerCase())) keywordMatched.add(entry.id);
        }
      }
    }
    debugPrint('[mem] keyword matched: ${keywordMatched.length}');

    final vectorScores = <String, double>{};
    if (gs.vectorSearchEnabled && embeddingConfig != null && embeddingConfig.endpoint.isNotEmpty && history != null) {
      debugPrint('[mem] starting vector search...');
      vectorScores.addAll(await _vectorSearchMemory(
        activeEntries,
        history,
        currentText ?? '',
        embeddingConfig,
        gs,
        shouldAbort: shouldAbort,
        cancelToken: cancelToken,
      ));
      debugPrint('[mem] vector search done, scores=${vectorScores.length}');
    } else {
      debugPrint('[mem] vector search skipped (enabled=${gs.vectorSearchEnabled}, endpoint=${embeddingConfig?.endpoint.isNotEmpty ?? false}, history=${history != null})');
    }

    final scoredEntries = activeEntries.map((entry) {
      var score = 0.0;
      if (keywordMatched.contains(entry.id)) score += 6;
      if (vectorScores.containsKey(entry.id)) score += (vectorScores[entry.id]! * 5);
      if (entry.messageIds.isNotEmpty) score += 2;
      score += entry.content.length > 20 ? 1 : 0;
      return (entry: entry, score: score);
    }).toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    final topEntries = scoredEntries
        .where((item) => item.score > 0)
        .take(gs.maxInjectedEntries)
        .map((item) => item.entry)
        .toList();

    if (topEntries.isEmpty) return const MemoryInjectionResult();

    final macroContent = topEntries
        .map((e) => e.content.trim())
        .join('\n\n');

    final contentParts = <String>[];
    if (summaryExcerpt != null && summaryExcerpt.isNotEmpty) {
      contentParts.add('Summary excerpt:\n$summaryExcerpt');
    }
    contentParts.add('Memory context:');
    for (final entry in topEntries) {
      final title = entry.title.isNotEmpty ? entry.title : 'Memory';
      contentParts.add('- $title: ${entry.content.trim()}');
    }

    final injectionTarget =
        gs.injectionTarget == 'summary_macro' ? 'summary_macro' : 'summary_block';

    return MemoryInjectionResult(
      entries: topEntries,
      content: contentParts.join('\n\n'),
      injectionTarget: injectionTarget,
      macroContent: macroContent,
    );
  }

  Future<Map<String, double>> _vectorSearchMemory(
    List<MemoryEntry> entries,
    List<ChatMessageForSearch> history,
    String currentText,
    EmbeddingConfig config,
    MemoryGlobalSettings settings,
    {bool Function()? shouldAbort, CancelToken? cancelToken}
  ) async {
    try {
      if (shouldAbort?.call() == true) return {};
      debugPrint('[mem-vec] reading embeddings from DB...');
      final embeddingRows = await _embeddingRepo.getBySourceType('memory_entry');
      if (shouldAbort?.call() == true) return {};
      final embeddingMap = <String, EmbeddingRow>{};
      for (final row in embeddingRows) {
        embeddingMap[row.entryId] = row;
      }
      debugPrint('[mem-vec] loaded ${embeddingRows.length} embedding rows');

      final candidates = <VectorCandidate>[];
      for (int i = 0; i < entries.length; i++) {
        final entry = entries[i];
        debugPrint('[mem-vec] processing entry ${i + 1}/${entries.length}: id=${entry.id}');
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

        candidates.add(VectorCandidate(
          id: entry.id,
          vectors: vectors.map((v) => VectorChunk(text: '', vector: v)).toList(),
          metadata: {
            'hints': _embeddingRepo.decodeHints(row) ?? [],
          },
        ));
        debugPrint('[mem-vec]   added candidate with ${vectors.length} vectors');
      }
      debugPrint('[mem-vec] valid candidates: ${candidates.length}');

      if (candidates.isEmpty) return {};

      final userMessages = history.where((m) => m.role == 'user').toList().reversed;
      final maxChars = (config.maxChunkTokens * 2).clamp(0, 1024) * 4;
      final buffer = StringBuffer();
      buffer.write(currentText);
      for (final msg in userMessages) {
        final toAdd = '\n${msg.content}';
        if (buffer.length + toAdd.length > maxChars.clamp(0, 6000)) break;
        buffer.write(toAdd);
      }
      final queryText = buffer.toString().trim();
      if (queryText.isEmpty) return {};
      if (shouldAbort?.call() == true) return {};

      debugPrint('[mem-vec] calling embedding API (endpoint=${config.endpoint})...');
      final queryChunks = await _embeddingService.getEmbeddingsWithChunks(
        [queryText],
        config,
        cancelToken: cancelToken,
      )
          .timeout(const Duration(seconds: 15), onTimeout: () => []);
      if (cancelToken?.isCancelled == true) return {};
      debugPrint('[mem-vec] embedding API returned ${queryChunks.length} chunks');
      if (queryChunks.isEmpty) return {};

      final queryVecChunks = queryChunks.map((c) => VectorChunk(text: c.text, vector: c.vector)).toList();
      final results = findTopKMulti(queryVecChunks, candidates, candidates.length, 0);

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

  bool _glazeMatch(String key, String text) {
    return glazeCheckMatch(key, text.toLowerCase(), false, WholeWordMode.glaze);
  }
}

final memoryInjectionServiceProvider = Provider<MemoryInjectionService>((ref) {
  return MemoryInjectionService(
    ref.watch(memoryBookRepoProvider),
    ref.watch(embeddingRepoProvider),
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
