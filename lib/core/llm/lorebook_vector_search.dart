import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/lorebook.dart';
import '../state/db_provider.dart';
import '../db/app_db.dart';
import '../db/repositories/embedding_repo.dart';
import 'embedding_service.dart';
import 'lorebook_embedding_service.dart';
import 'vector_math.dart';

class VectorSearchResult {
  final String entryId;
  final double score;
  final String lorebookId;

  const VectorSearchResult({
    required this.entryId,
    required this.score,
    required this.lorebookId,
  });
}

class LorebookVectorSearch {
  final EmbeddingRepo _repo;
  final EmbeddingService _embeddingService;

  LorebookVectorSearch(this._repo, this._embeddingService);

  Future<List<VectorSearchResult>> search(
    List<ChatMessageForSearch> history,
    String currentText,
    List<Lorebook> lorebooks,
    LorebookGlobalSettings settings,
    EmbeddingConfig config,
  ) async {
    if (settings.searchType == 'keys') return [];

    final activeLorebooks = lorebooks.where((lb) => lb.enabled).toList();

    final vectorEntries = <(LorebookEntry, String)>[];
    for (final lb in activeLorebooks) {
      for (final entry in lb.entries) {
        if (entry.vectorSearch && entry.enabled && !entry.constant) {
          vectorEntries.add((entry, lb.id));
        }
      }
    }

    if (vectorEntries.isEmpty) return [];

    final embeddingRows = await _repo.getBySourceType('lorebook_entry');
    final embeddingMap = <String, EmbeddingRow>{};
    for (final row in embeddingRows) {
      embeddingMap[row.entryId] = row;
    }

    final candidates = <VectorCandidate>[];
    for (final (entry, lbId) in vectorEntries) {
      final row = embeddingMap[entry.id];
      if (row == null || row.vectorsBlob == null) continue;

      final vectors = _repo.decodeVectors(row);
      if (vectors == null || vectors.isEmpty) continue;

      candidates.add(VectorCandidate(
        id: entry.id,
        vectors: vectors.map((v) => VectorChunk(text: '', vector: v)).toList(),
        metadata: {
          'lorebookId': lbId,
          'entry': entry,
          'hints': _repo.decodeHints(row) ?? [],
        },
      ));
    }

    if (candidates.isEmpty) return [];

    final focusedQuery = _buildFocusedQuery(history, currentText, config.maxChunkTokens);
    final fallbackQuery = _buildFallbackQuery(history, currentText, config.maxChunkTokens);

    final allResults = <String, double>{};
    final allLorebookIds = <String, String>{};

    if (focusedQuery.isNotEmpty) {
      final focusedChunks = await _embeddingService.getEmbeddingsWithChunks([focusedQuery], config);
      final focusedVecChunks = focusedChunks.map((c) => VectorChunk(text: c.text, vector: c.vector)).toList();
      final focusedResults = findTopKMulti(focusedVecChunks, candidates, candidates.length, 0);
      for (final r in focusedResults) {
        final entry = r.metadata['entry'] as LorebookEntry;
        final hints = r.metadata['hints'] as List<String>;
        final boosted = _applyHybridBoost(r.score, entry, hints, focusedQuery);
        if (allResults[entry.id] == null || boosted > allResults[entry.id]!) {
          allResults[entry.id] = boosted;
        }
        allLorebookIds[entry.id] = r.metadata['lorebookId'] as String;
      }
    }

    if (fallbackQuery.isNotEmpty && fallbackQuery != focusedQuery) {
      final fallbackChunks = await _embeddingService.getEmbeddingsWithChunks([fallbackQuery], config);
      final fallbackVecChunks = fallbackChunks.map((c) => VectorChunk(text: c.text, vector: c.vector)).toList();
      final fallbackResults = findTopKMulti(fallbackVecChunks, candidates, candidates.length, 0);
      for (final r in fallbackResults) {
        final entry = r.metadata['entry'] as LorebookEntry;
        final hints = r.metadata['hints'] as List<String>;
        final boosted = _applyHybridBoost(r.score, entry, hints, fallbackQuery);
        if (allResults[entry.id] == null || boosted > allResults[entry.id]!) {
          allResults[entry.id] = boosted;
        }
        allLorebookIds[entry.id] = r.metadata['lorebookId'] as String;
      }
    }

    final threshold = settings.vectorThreshold;
    final topK = settings.vectorTopK;

    final sorted = allResults.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted
        .where((e) => e.value >= threshold)
        .take(topK)
        .map((e) => VectorSearchResult(
              entryId: e.key,
              score: e.value,
              lorebookId: allLorebookIds[e.key] ?? '',
            ))
        .toList();
  }

  String _buildFocusedQuery(List<ChatMessageForSearch> history, String currentText, int maxChunkTokens) {
    final userMessages = history.where((m) => m.role == 'user').toList().reversed;
    final maxChars = (maxChunkTokens * 2).clamp(0, 1024) * 4;
    final buffer = StringBuffer();

    buffer.write(currentText);

    for (final msg in userMessages) {
      final toAdd = '\n${msg.content}';
      if (buffer.length + toAdd.length > maxChars.clamp(0, 6000)) break;
      buffer.write(toAdd);
    }

    return _sanitizeQuery(buffer.toString());
  }

  String _buildFallbackQuery(List<ChatMessageForSearch> history, String currentText, int maxChunkTokens) {
    final maxChars = (maxChunkTokens * 3).clamp(0, 1536) * 4;
    final buffer = StringBuffer();

    buffer.write(currentText);

    for (final msg in history.reversed) {
      final toAdd = '\n${msg.content}';
      if (buffer.length + toAdd.length > maxChars.clamp(0, 10000)) break;
      buffer.write(toAdd);
    }

    return _sanitizeQuery(buffer.toString());
  }

  String _sanitizeQuery(String text) {
    var clean = text;
    clean = clean.replaceAll(RegExp(r'<[^>]+>'), '');
    clean = clean.replaceAll(RegExp(r'\(OOC:.*?\)', caseSensitive: false), '');
    clean = clean.replaceAll(RegExp(r'data:image/[^;]+;base64,[^\s]+'), '');
    return clean.trim();
  }

  double _applyHybridBoost(double rawScore, LorebookEntry entry, List<String> hints, String queryText) {
    double boost = 0;
    final queryLower = queryText.toLowerCase();

    final nameInQuery = entry.comment.isNotEmpty && queryLower.contains(entry.comment.toLowerCase());
    if (nameInQuery) {
      boost += 0.18;
    }

    int keyOverlap = 0;
    for (final key in entry.keys) {
      if (queryLower.contains(key.toLowerCase())) {
        keyOverlap++;
      }
    }
    boost += (keyOverlap * 0.04).clamp(0, 0.12);

    int hintOverlap = 0;
    final queryTokens = _tokenize(queryLower);
    for (final hint in hints) {
      final hintTokens = _tokenize(hint.toLowerCase());
      for (final ht in hintTokens) {
        if (queryTokens.contains(ht)) {
          hintOverlap++;
        }
      }
    }
    boost += (hintOverlap * 0.025).clamp(0, 0.10);

    return (rawScore + boost).clamp(0, 1);
  }

  List<String> _tokenize(String text) {
    return text.split(RegExp(r'[\s,.;:!?]+')).where((t) => t.length > 2).toList();
  }
}

class ChatMessageForSearch {
  final String role;
  final String content;

  const ChatMessageForSearch({required this.role, required this.content});
}

final embeddingConfigProvider = StateProvider<EmbeddingConfig>((ref) {
  return const EmbeddingConfig(endpoint: '', model: '');
});

Future<void> initEmbeddingConfigFromDb(WidgetRef ref) async {
  final apiConfigs = await ref.read(apiConfigRepoProvider).getAll();
  final embConfig = apiConfigs.where((c) => c.mode == 'embedding').firstOrNull;
  if (embConfig != null) {
    ref.read(embeddingConfigProvider.notifier).state = EmbeddingConfig(
      endpoint: embConfig.endpoint,
      apiKey: embConfig.apiKey,
      model: embConfig.model,
    );
  } else {
    final chatConfig = apiConfigs.where((c) => c.mode != 'embedding').firstOrNull;
    if (chatConfig != null) {
      ref.read(embeddingConfigProvider.notifier).state = EmbeddingConfig(
        endpoint: chatConfig.endpoint,
        apiKey: chatConfig.apiKey,
        model: chatConfig.model,
      );
    }
  }
}

final lorebookVectorSearchProvider = Provider<LorebookVectorSearch>((ref) {
  return LorebookVectorSearch(
    ref.watch(embeddingRepoProvider),
    EmbeddingService(),
  );
});

final lorebookEmbeddingServiceProvider = Provider<LorebookEmbeddingService>((ref) {
  return LorebookEmbeddingService(
    ref.watch(embeddingRepoProvider),
    EmbeddingService(),
  );
});
