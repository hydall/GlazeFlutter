import 'dart:convert';

import '../models/memory_book.dart';
import '../db/repositories/embedding_repo.dart';
import '../utils/cast_helpers.dart';
import 'embedding_service.dart';
import 'lorebook_embedding_service.dart';
import 'retrieval_hints.dart';

class MemoryEmbeddingService {
  final EmbeddingRepo _repo;
  final EmbeddingService _embeddingService;

  MemoryEmbeddingService(this._repo, this._embeddingService);

  Future<void> indexMemoryEntry(
    MemoryEntry entry, {
    required String charId,
    required String sessionId,
    required EmbeddingConfig config,
    String embeddingTarget = 'content',
  }) async {
    if (!entry.vectorSearch) return;
    if (config.endpoint.isEmpty) return;

    final text = _getEmbeddingText(entry, embeddingTarget);
    if (text.trim().isEmpty) return;

    final hints = extractMemoryRetrievalHints(entry);
    final fingerprint = _buildFingerprint(entry, text);
    final textHash = computeHash(fingerprint);

    final existing = await _repo.getByEntryId(entry.id);
    if (existing != null && existing.textHash == textHash && existing.vectorsBlob != null && existing.errorJson == null) {
      return;
    }

    try {
      final chunks = await _embeddingService.getEmbeddingsWithChunks([text], config);
      final vectors = chunks.map((c) => c.vector).toList();

      await _repo.putEmbeddingVector(
        entryId: entry.id,
        sourceType: 'memory_entry',
        sourceId: 'memorybook_${charId}_$sessionId',
        vectors: vectors,
        textHash: textHash,
        retrievalHints: hints,
      );
    } on RateLimitException {
      await _repo.putEmbeddingError(
        entryId: entry.id,
        sourceType: 'memory_entry',
        sourceId: 'memorybook_${charId}_$sessionId',
        textHash: textHash,
        error: {'type': 'rate_limit', 'message': 'Rate limited, deferred', 'retryable': true},
        retrievalHints: hints,
      );
      rethrow;
    } catch (e) {
      await _repo.putEmbeddingError(
        entryId: entry.id,
        sourceType: 'memory_entry',
        sourceId: 'memorybook_${charId}_$sessionId',
        textHash: textHash,
        error: {'type': 'api_error', 'message': e.toString(), 'retryable': true},
        retrievalHints: hints,
      );
    }
  }

  Future<IndexResult> reindexAll(
    MemoryBook book, {
    required String charId,
    required String sessionId,
    required EmbeddingConfig config,
    String embeddingTarget = 'content',
    void Function(int current, int total)? onProgress,
  }) async {
    int indexed = 0;
    int skipped = 0;
    int failed = 0;
    bool rateLimited = false;
    int retryAfter = 0;

    final entries = book.entries.where((e) => e.vectorSearch && e.status == 'active').toList();

    for (int i = 0; i < entries.length; i++) {
      onProgress?.call(i, entries.length);
      try {
        final existing = await _repo.getByEntryId(entries[i].id);
        final text = _getEmbeddingText(entries[i], embeddingTarget);
        final hints = extractMemoryRetrievalHints(entries[i]);
        final fingerprint = _buildFingerprint(entries[i], text);
    final textHash = computeHash(fingerprint);

        if (existing != null && existing.textHash == textHash && existing.vectorsBlob != null && existing.errorJson == null) {
          skipped++;
          continue;
        }

        await indexMemoryEntry(
          entries[i],
          charId: charId,
          sessionId: sessionId,
          config: config,
          embeddingTarget: embeddingTarget,
        );
        indexed++;
      } on RateLimitException catch (e) {
        rateLimited = true;
        retryAfter = e.retryAfter;
        failed++;
        break;
      } catch (_) {
        failed++;
      }
    }

    return IndexResult(
      indexed: indexed,
      skipped: skipped,
      failed: failed,
      rateLimited: rateLimited,
      retryAfter: retryAfter,
    );
  }

  Future<void> deleteMemoryEntryIndex(String entryId) async {
    await _repo.deleteByEntryId(entryId);
  }

  Future<void> deleteAllMemoryIndexes() async {
    await _repo.deleteBySourceType('memory_entry');
  }

  String _getEmbeddingText(MemoryEntry entry, String target) {
    if (target == 'keys') {
      return entry.keys.join(', ');
    }
    return entry.content;
  }

  String _buildFingerprint(MemoryEntry entry, String text) {
    return jsonEncode({
      'text': text,
      'retrievalHints': extractMemoryRetrievalHints(entry),
    });
  }

  static List<String> extractMemoryRetrievalHints(MemoryEntry entry) {
    return extractRetrievalHintsFrom(
      label: entry.title,
      keys: entry.keys,
      content: entry.content,
    );
  }
}
