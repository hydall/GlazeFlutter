import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:glaze_flutter/core/db/app_db.dart';
import 'package:glaze_flutter/core/models/chat_message.dart';
import 'package:glaze_flutter/core/state/db_provider.dart';
import 'package:glaze_flutter/features/chat/chat_message_service.dart';

final _messageServiceProvider = Provider(ChatMessageService.new);

void main() {
  test(
    'bulk delete persists final state and clears raw-message index',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [appDbProvider.overrideWithValue(db)],
      );
      addTearDown(() async {
        container.dispose();
        await db.close();
      });

      final messages = [
        for (var i = 0; i < 39; i++)
          ChatMessage(
            id: 'm$i',
            role: i.isEven ? 'user' : 'assistant',
            content: 'message $i',
          ),
      ];
      final session = ChatSession(
        id: 's1',
        characterId: 'c1',
        sessionIndex: 0,
        messages: messages,
      );
      await container.read(chatRepoProvider).put(session);
      await container
          .read(embeddingRepoProvider)
          .putEmbeddingVector(
            entryId: 's1_0',
            sourceType: 'chat_message',
            sourceId: 's1',
            vectors: const [
              [1, 0],
            ],
            textHash: 'old',
            retrievalMetadata: const {'chunkIndex': 0},
          );

      final updated = await container
          .read(_messageServiceProvider)
          .deleteMessages(session, {for (var i = 0; i < 30; i++) i});

      expect(updated.messages.map((message) => message.id), [
        for (var i = 30; i < 39; i++) 'm$i',
      ]);
      final persisted = await container.read(chatRepoProvider).getById('s1');
      expect(persisted?.messages.map((message) => message.id), [
        for (var i = 30; i < 39; i++) 'm$i',
      ]);
      expect(
        await container.read(embeddingRepoProvider).getBySourceId('s1'),
        isEmpty,
      );
    },
  );
}
