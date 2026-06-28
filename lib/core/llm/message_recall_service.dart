import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../db/app_db.dart' show EmbeddingRow;
import '../db/repositories/embedding_repo.dart';
import 'embedding_service.dart';
import 'vector_math.dart';

/// Cosine-similarity recall over raw chat-message chunks embedded by
/// [ChatMessageEmbeddingService]. Returns the top-K raw message chunks
/// semantically closest to the current user message — a lossless backstop
/// for the lossy MemoryBook compression (Marinara `memory-recall.ts`
/// analog).
///
/// Injection into the prompt is the caller's responsibility — this service
/// only returns the matched chunk texts. The caller wraps them in
/// `<recalled_messages>...</recalled_messages>` and adds the block to
/// `PromptPayload`.
///
/// ADR: see docs/plans/PLAN_MEMORY_CONTINUITY.md §2.1 — if mobile latency
/// or binary size becomes prohibitive, this service can be feature-flagged
/// off per-chat (`enableMessageRecall`) or dropped entirely. MemoryBook +
/// chat history within the context window already covers ~80% of cases.
class MessageRecallService {
  final EmbeddingRepo _repo;
  final EmbeddingService _embeddingService;

  /// Cosine similarity threshold below which a match is considered noise.
  /// Marinara uses 0.25; we match.
  static const double defaultSimilarityThreshold = 0.25;

  /// Maximum number of chunks to return per query. Marinara default 8.
  static const int defaultTopK = 8;

  /// Soft cap on total recalled characters injected into the prompt.
  /// Marinara caps at 15% of context (~384-1536 tokens); we use a simpler
  /// character cap (~6000 chars ≈ 1500 tokens) which the caller can trim
  /// further to fit the model's context budget.
  static const int defaultMaxChars = 6000;

  MessageRecallService(this._repo, this._embeddingService);

  /// Cosine-search [currentText] against every `chat_message` embedding
  /// row for [sessionId]. Returns the matched chunk texts sorted by
  /// descending similarity, filtered by [threshold] and capped to [topK]
  /// chunks and [maxChars] total characters.
  ///
  /// Never throws — on any error (embedding API failure, timeout, decode
  /// error) returns an empty [MessageRecallResult]. The caller should
  /// treat recall as best-effort insurance, not a hard dependency.
  Future<MessageRecallResult> recall({
    required String sessionId,
    required String currentText,
    required EmbeddingConfig config,
    double threshold = defaultSimilarityThreshold,
    int topK = defaultTopK,
    int maxChars = defaultMaxChars,
    CancelToken? cancelToken,
    bool Function()? shouldAbort,
  }) async {
    try {
      if (config.endpoint.isEmpty) return const MessageRecallResult();
      if (currentText.trim().isEmpty) return const MessageRecallResult();
      if (shouldAbort?.call() == true) return const MessageRecallResult();

      final rows = await _repo.getBySourceType('chat_message');
      if (shouldAbort?.call() == true) return const MessageRecallResult();
      // Keep only rows for this session (the embeddings table is shared
      // across sessions under one sourceType).
      final sessionRows =
          rows.where((r) => r.sourceId == sessionId).toList();
      if (sessionRows.isEmpty) return const MessageRecallResult();

      final candidates = <VectorCandidate>[];
      for (final row in sessionRows) {
        if (!_repo.hasUsableVectors(row)) continue;
        final vectors = _repo.decodeVectors(row);
        if (vectors == null || vectors.isEmpty) continue;
        final chunkTexts = _decodeChunkTexts(row, vectors.length);
        candidates.add(
          VectorCandidate(
            id: row.entryId,
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
            metadata: {'chunkTexts': chunkTexts},
          ),
        );
      }
      if (candidates.isEmpty) return const MessageRecallResult();

      if (shouldAbort?.call() == true) {
        return const MessageRecallResult();
      }

      final queryChunks = await _embeddingService
          .getEmbeddingsWithChunks(
            [currentText],
            config,
            cancelToken: cancelToken,
          )
          .timeout(const Duration(seconds: 15), onTimeout: () => []);
      if (cancelToken?.isCancelled == true) {
        return const MessageRecallResult();
      }
      if (queryChunks.isEmpty) return const MessageRecallResult();

      final queryVecChunks = queryChunks
          .map((c) => VectorChunk(text: c.text, vector: c.vector))
          .toList();

      // §6: dimension-mismatch detection. If the user switched embedding
      // models after chunks were stored, the candidate vectors will have a
      // different dimension from the query. cosineSimilarity silently
      // returns 0 in that case (which the threshold filters out), but
      // without a warning the user would see empty recall with no clue why.
      // Filter out stale candidates and log a warning once per recall.
      final queryDim = queryVecChunks.isEmpty
          ? 0
          : queryVecChunks.first.vector.length;
      var mismatchLogged = false;
      final dimFilteredCandidates = <VectorCandidate>[];
      for (final candidate in candidates) {
        final chunks = candidate.vectors ?? const <VectorChunk>[];
        final allMatch = chunks.every((c) => c.vector.length == queryDim);
        if (allMatch) {
          dimFilteredCandidates.add(candidate);
        } else if (!mismatchLogged && kDebugMode) {
          debugPrint(
            '[msg-recall] dimension mismatch: query=$queryDim '
            'candidate has ${chunks.isNotEmpty ? chunks.first.vector.length : 0} '
            '(entryId=${candidate.id}). Embedding model may have changed — '
            're-index chat message embeddings to restore recall.',
          );
          mismatchLogged = true;
        }
      }
      if (dimFilteredCandidates.isEmpty && mismatchLogged) {
        return const MessageRecallResult();
      }

      final results = findTopKMulti(
        queryVecChunks,
        dimFilteredCandidates,
        dimFilteredCandidates.length,
        0,
      );

      final matched = <MessageRecallMatch>[];
      var totalChars = 0;
      for (final result
          in results.where((r) => r.score >= threshold).take(topK)) {
        final chunkTexts = result.metadata['chunkTexts'];
        if (chunkTexts is! List) continue;
        if (result.bestCandidateChunk == null) continue;
        final bestIndex = result.bestCandidateChunk!;
        if (bestIndex < 0 || bestIndex >= chunkTexts.length) continue;
        final text = chunkTexts[bestIndex];
        if (text is! String || text.trim().isEmpty) continue;

        if (totalChars + text.length > maxChars) {
          // Soft cap: stop adding once we exceed the budget. Caller can
          // further trim if needed.
          break;
        }
        matched.add(MessageRecallMatch(entryId: result.id, text: text, score: result.score));
        totalChars += text.length;
      }
      return MessageRecallResult(matches: matched);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[msg-recall] error: $e');
      }
      return const MessageRecallResult();
    }
  }

  List<String> _decodeChunkTexts(EmbeddingRow row, int vectorCount) {
    // ChatMessageEmbeddingService stores chunk text directly in
    // retrievalMetadata['chunks'][i]['text'] — same shape as
    // MemoryEmbeddingService. But for chat messages we only ever embed
    // one chunk text per row (the chunk-of-5-messages text), so the
    // list has exactly one element. We still return a list for
    // consistency with VectorCandidate's contract.
    final metadata = _repo.decodeMetadata(row);
    final chunks = metadata?['chunks'];
    if (chunks is! List) {
      // Fallback: no chunk metadata. Return empty strings so the
      // candidate's vector is still searchable but yields no text.
      return List<String>.filled(vectorCount, '');
    }
    final texts = List<String>.filled(vectorCount, '');
    for (final chunk in chunks) {
      if (chunk is! Map) continue;
      final index = chunk['index'];
      final text = chunk['text'];
      if (index is! int || text is! String) continue;
      if (index < 0 || index >= texts.length) continue;
      texts[index] = text;
    }
    return texts;
  }
}

/// One matched raw-message chunk.
class MessageRecallMatch {
  final String entryId;
  final String text;
  final double score;
  const MessageRecallMatch({
    required this.entryId,
    required this.text,
    required this.score,
  });
}

/// Result of a recall query. Empty on any error or when no chunks clear
/// the [MessageRecallService.defaultSimilarityThreshold].
class MessageRecallResult {
  final List<MessageRecallMatch> matches;
  const MessageRecallResult({this.matches = const []});
  bool get isEmpty => matches.isEmpty;
}
