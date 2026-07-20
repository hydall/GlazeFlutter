import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:glaze_flutter/core/db/app_db.dart';
import 'package:glaze_flutter/core/db/repositories/embedding_repo.dart';
import 'package:glaze_flutter/core/llm/embedding_service.dart';
import 'package:glaze_flutter/core/llm/lorebook_embedding_service.dart';
import 'package:glaze_flutter/core/llm/lorebook_vector_search.dart';
import 'package:glaze_flutter/core/models/lorebook.dart';
import 'package:glaze_flutter/core/utils/cast_helpers.dart';

class _BlockingEmbeddingService extends EmbeddingService {
  final release = Completer<void>();
  int calls = 0;
  int active = 0;
  int maxActive = 0;

  @override
  Future<List<EmbeddingChunk>> getEmbeddingsWithChunks(
    List<String> texts,
    EmbeddingConfig config, {
    CancelToken? cancelToken,
  }) async {
    calls++;
    active++;
    if (active > maxActive) maxActive = active;
    try {
      await release.future;
      return [
        for (final text in texts)
          EmbeddingChunk(text: text, vector: const [1, 0]),
      ];
    } finally {
      active--;
    }
  }
}

void main() {
  testWidgets('shares focused query embedding across vector pools', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = EmbeddingRepo(db);
    final embeddings = _BlockingEmbeddingService();
    final search = LorebookVectorSearch(repo, embeddings);

    const mainEntry = LorebookEntry(
      id: 'main',
      content: 'main content',
      keys: ['main'],
      vectorSearch: true,
    );
    const keylessEntry = LorebookEntry(
      id: 'keyless',
      content: 'keyless content',
    );
    const lorebook = Lorebook(
      id: 'lb',
      name: 'Test',
      entries: [mainEntry, keylessEntry],
    );

    for (final entry in lorebook.entries) {
      final fingerprint = LorebookEmbeddingService.buildEmbeddingFingerprint(
        entry,
        entry.content,
      );
      await repo.putEmbeddingVector(
        entryId: 'lb_${entry.id}',
        sourceType: 'lorebook_entry',
        sourceId: 'lb',
        vectors: const [
          [1, 0],
        ],
        textHash: computeHash(fingerprint),
      );
    }

    final pending = search.search(
      const [],
      'focused query',
      const [lorebook],
      const LorebookGlobalSettings(
        searchType: 'vector',
        vectorThreshold: 0,
        fallbackThreshold: 0,
      ),
      const EmbeddingConfig(endpoint: 'test', model: 'test'),
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(embeddings.calls, 1);
    expect(embeddings.maxActive, 1);

    embeddings.release.complete();
    await tester.pump();
    final results = await pending;
    expect(results.map((r) => r.entryId).toSet(), {'main', 'keyless'});
  });
}
