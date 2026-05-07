import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/lorebook.dart';
import '../db/repositories/embedding_repo.dart';
import 'embedding_service.dart';

class LorebookEmbeddingService {
  final EmbeddingRepo _repo;
  final EmbeddingService _embeddingService;
  final String _embeddingTarget;

  LorebookEmbeddingService(this._repo, this._embeddingService, [this._embeddingTarget = 'content']);

  Future<IndexResult> indexLorebookEntries(
    String lorebookId,
    List<LorebookEntry> entries,
    EmbeddingConfig config, {
    void Function(int current, int total, String entryName)? onProgress,
    bool retryFailedOnly = false,
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
      final textHash = _computeHash(fingerprint);

      final existing = await _repo.getByEntryId(entry.id);
      if (existing != null && existing.textHash == textHash && existing.vectorsBlob != null && existing.errorJson == null) {
        if (retryFailedOnly) {
          skipped++;
          continue;
        }
        skipped++;
        continue;
      }

      if (retryFailedOnly && existing != null && existing.errorJson == null) {
        skipped++;
        continue;
      }

      if (text.trim().isEmpty) {
        await _repo.putEmbeddingError(
          entryId: entry.id,
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
          entryId: entry.id,
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
          final laterHash = _computeHash(buildEmbeddingFingerprint(laterEntry, laterText));
          await _repo.putEmbeddingError(
            entryId: laterEntry.id,
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
        final laterHash = _computeHash(buildEmbeddingFingerprint(entry, text));
        await _repo.putEmbeddingError(
          entryId: entry.id,
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
    final hints = <String>{};

    if (entry.comment.isNotEmpty) hints.add(entry.comment);

    for (final key in entry.keys) {
      if (key.isNotEmpty) hints.add(key);
    }

    final lines = entry.content.split('\n');
    int lineCount = 0;
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      hints.add(line.trim());
      lineCount++;
      if (lineCount >= 8) break;
    }

    final labelPattern = RegExp(r'^[\w\s]+:\s*(.+)$', multiLine: true);
    for (final match in labelPattern.allMatches(entry.content)) {
      final value = match.group(1);
      if (value != null && value.isNotEmpty) {
        for (final part in value.split(RegExp(r'[;,]'))) {
          final trimmed = part.trim();
          if (trimmed.isNotEmpty) hints.add(trimmed);
        }
      }
    }

    final normalized = hints.map((h) => h.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').trim()).toSet();
    return hints.where((h) {
      final n = h.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').trim();
      return n.isNotEmpty && normalized.contains(n);
    }).take(32).toList();
  }

  String _computeHash(String input) {
    return sha256.convert(utf8.encode(input)).toString();
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
