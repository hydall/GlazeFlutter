import 'dart:convert';

import '../models/lorebook.dart';
import '../db/repositories/embedding_repo.dart';
import '../utils/cast_helpers.dart';
import 'embedding_service.dart';
import 'retrieval_hints.dart';

class LorebookEmbeddingService {
  final EmbeddingRepo _repo;
  final EmbeddingService _embeddingService;
  final String _embeddingTarget;

  LorebookEmbeddingService(this._repo, this._embeddingService, [this._embeddingTarget = 'content']);

  Future<void> clearLorebookEmbeddings(String lorebookId) {
    return _repo.deleteBySourceId(lorebookId);
  }

  Future<IndexResult> indexLorebookEntries(
    String lorebookId,
    List<LorebookEntry> entries,
    EmbeddingConfig config, {
    void Function(int current, int total, String entryName)? onProgress,
    bool retryFailedOnly = false,
    bool forceReindex = false,
    String embeddingTarget = 'content',
  }) async {
    int indexed = 0;
    int skipped = 0;
    int failed = 0;
    bool rateLimited = false;
    int retryAfter = 0;

    final vectorEntries = entries.where((e) => e.vectorSearch && e.enabled && !e.constant).toList();

    for (int i = 0; i < vectorEntries.length; i++) {
      final entry = vectorEntries[i];
      onProgress?.call(i, vectorEntries.length, entry.comment.isNotEmpty ? entry.comment : entry.id);

      final text = _getEmbeddingText(entry, config);
      final hints = extractRetrievalHints(entry);
      final fingerprint = buildEmbeddingFingerprint(entry, text);
      final textHash = computeHash(fingerprint);

      final namespacedId = '${lorebookId}_${entry.id}';
      final existing = forceReindex ? null : await _repo.getByEntryId(namespacedId);

      // Skip if already indexed with matching hash (unless forcing reindex)
      if (existing != null &&
          existing.textHash == textHash &&
          _repo.hasUsableVectors(existing) &&
          existing.errorJson == null) {
        skipped++;
        continue;
      }

      // retryFailedOnly: skip entries that have no error (i.e. already good or just not indexed)
      if (retryFailedOnly && existing != null && existing.errorJson == null) {
        skipped++;
        continue;
      }

      if (text.trim().isEmpty) {
        await _repo.putEmbeddingError(
          entryId: namespacedId,
          sourceType: 'lorebook_entry',
          sourceId: lorebookId,
          textHash: textHash,
          error: {'type': 'empty_text', 'message': 'Entry content is empty', 'retryable': false},
          retrievalHints: hints,
        );
        failed++;
        continue;
      }

      try {
        final chunks = await _embeddingService.getEmbeddingsWithChunks([text], config);
        final vectors = chunks.map((c) => c.vector).toList();

        await _repo.putEmbeddingVector(
          entryId: namespacedId,
          sourceType: 'lorebook_entry',
          sourceId: lorebookId,
          vectors: vectors,
          textHash: textHash,
          retrievalHints: hints,
        );
        indexed++;
      } on RateLimitException catch (e) {
        rateLimited = true;
        retryAfter = e.retryAfter;

        for (int j = i + 1; j < vectorEntries.length; j++) {
          final laterEntry = vectorEntries[j];
          final laterText = _getEmbeddingText(laterEntry, config);
          final laterHash = computeHash(buildEmbeddingFingerprint(laterEntry, laterText));
          await _repo.putEmbeddingError(
            entryId: '${lorebookId}_${laterEntry.id}',
            sourceType: 'lorebook_entry',
            sourceId: lorebookId,
            textHash: laterHash,
            error: {'type': 'rate_limit', 'message': 'Rate limited, deferred', 'retryable': true},
            retrievalHints: extractRetrievalHints(laterEntry),
          );
          failed++;
        }
        break;
      } catch (e) {
        final laterHash = computeHash(buildEmbeddingFingerprint(entry, text));
        await _repo.putEmbeddingError(
          entryId: namespacedId,
          sourceType: 'lorebook_entry',
          sourceId: lorebookId,
          textHash: laterHash,
          error: {'type': 'api_error', 'message': e.toString(), 'retryable': true},
          retrievalHints: hints,
        );
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

  String _getEmbeddingText(LorebookEntry entry, EmbeddingConfig config) {
    if (_embeddingTarget == 'keys') {
      return entry.keys.join(', ');
    }
    return entry.content;
  }

  static String buildEmbeddingFingerprint(LorebookEntry entry, String text) {
    return jsonEncode({
      'text': text,
      'retrievalHints': extractRetrievalHints(entry),
    });
  }

  static List<String> extractRetrievalHints(LorebookEntry entry) {
    return extractRetrievalHintsFrom(
      label: entry.comment,
      keys: entry.keys,
      content: entry.content,
    );
  }

}

class IndexResult {
  final int indexed;
  final int skipped;
  final int failed;
  final bool rateLimited;
  final int retryAfter;

  const IndexResult({
    this.indexed = 0,
    this.skipped = 0,
    this.failed = 0,
    this.rateLimited = false,
    this.retryAfter = 0,
  });
}
