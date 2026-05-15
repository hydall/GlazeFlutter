import '../models/character.dart';
import '../models/lorebook.dart';
import '../db/app_db.dart';
import '../db/repositories/embedding_repo.dart';
import '../utils/cast_helpers.dart';
import 'embedding_service.dart';
import 'embedding_types.dart';
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
    EmbeddingConfig config, {
    String? charWorld,
    Character? character,
  }) async {
    if (settings.searchType == 'keyword') return [];

    final activeLorebooks = lorebooks.where((lb) {
      if (lb.enabled) return true;
      if (charWorld != null && charWorld.isNotEmpty && lb.name == charWorld) return true;
      return false;
    }).toList();

    activeLorebooks.removeWhere((lb) {
      final lbSettings = lb.settings;
      return lbSettings != null && !lbSettings.vectorSearchEnabled;
    });

    var effectiveThreshold = settings.vectorThreshold;
    var effectiveTopK = settings.vectorTopK;
    for (final lb in activeLorebooks) {
      final lbSettings = lb.settings;
      if (lbSettings != null) {
        if (lbSettings.vectorThreshold < effectiveThreshold) {
          effectiveThreshold = lbSettings.vectorThreshold;
        }
        if (lbSettings.vectorTopK > effectiveTopK) {
          effectiveTopK = lbSettings.vectorTopK;
        }
      }
    }

    final vectorEntries = <(LorebookEntry, String)>[];
    for (final lb in activeLorebooks) {
      for (final entry in lb.entries) {
        if (entry.vectorSearch && entry.enabled && !entry.constant) {
          if (_isFilteredByCharacter(entry, character)) continue;
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
      final namespacedId = '${lbId}_${entry.id}';
      final row = embeddingMap[namespacedId];
      if (row == null || row.vectorsBlob == null) continue;

      final text = _getEmbeddingText(entry, lorebooks, lbId);
      final fingerprint = LorebookEmbeddingService.buildEmbeddingFingerprint(entry, text);
      final currentHash = computeHash(fingerprint);
      if (row.textHash != currentHash) continue;

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

    final threshold = effectiveThreshold;
    final topK = effectiveTopK;

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

  String _getEmbeddingText(LorebookEntry entry, List<Lorebook> lorebooks, String lbId) {
    final lb = lorebooks.where((l) => l.id == lbId).firstOrNull;
    final target = lb?.settings?.embeddingTarget ?? 'content';
    if (target == 'keys') {
      return entry.keys.join(', ');
    }
    return entry.content;
  }

  bool _isFilteredByCharacter(LorebookEntry entry, Character? character) {
    if (character == null) return false;
    final filter = entry.characterFilter;
    if (filter == null) return false;
    if (filter.names.isEmpty) return false;
    final charName = character.name.toLowerCase();
    final isInCategory = filter.names.any((n) => charName.contains(n.toLowerCase()));
    if (filter.isExclude && isInCategory) return true;
    if (!filter.isExclude && !isInCategory) return true;
    return false;
  }
}


