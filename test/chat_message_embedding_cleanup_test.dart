import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:glaze_flutter/core/db/app_db.dart';
import 'package:glaze_flutter/core/db/repositories/embedding_repo.dart';
import 'package:glaze_flutter/core/llm/chat_message_embedding_service.dart';
import 'package:glaze_flutter/core/llm/embedding_service.dart';
import 'package:glaze_flutter/core/models/chat_message.dart';

class _FakeEmbeddingService extends EmbeddingService {
  @override
  Future<List<EmbeddingChunk>> getEmbeddingsWithChunks(
    List<String> texts,
    EmbeddingConfig config, {
    cancelToken,
  }) async {
    return [
      for (final text in texts)
        EmbeddingChunk(text: text, vector: const [1, 0]),
    ];
  }
}

void main() {
  late AppDatabase db;
  late EmbeddingRepo repo;
  late ChatMessageEmbeddingService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = EmbeddingRepo(db);
    service = ChatMessageEmbeddingService(repo, _FakeEmbeddingService());
  });

  tearDown(() => db.close());

  Future<void> seedChunk(int index) {
    return repo.putEmbeddingVector(
      entryId: 's1_$index',
      sourceType: 'chat_message',
      sourceId: 's1',
      vectors: const [
        [1, 0],
      ],
      textHash: 'stale',
      retrievalMetadata: {'chunkIndex': index},
    );
  }

  List<ChatMessage> messages(int count) => [
    for (var i = 0; i < count; i++)
      ChatMessage(
        id: 'm$i',
        role: i.isEven ? 'user' : 'assistant',
        content: 'message $i',
      ),
  ];

  test('removes tail chunks after the chat shrinks', () async {
    await seedChunk(0);
    await seedChunk(1);

    await service.indexSessionMessages(
      sessionId: 's1',
      messages: messages(5),
      config: const EmbeddingConfig(endpoint: 'test'),
    );

    expect(await repo.getByEntryId('s1_0'), isNotNull);
    expect(await repo.getByEntryId('s1_1'), isNull);
  });

  test('removes every chunk when fewer than five messages remain', () async {
    await seedChunk(0);
    await seedChunk(1);

    await service.indexSessionMessages(
      sessionId: 's1',
      messages: messages(4),
      config: const EmbeddingConfig(endpoint: 'test'),
    );

    expect(await repo.getBySourceId('s1'), isEmpty);
  });
}
