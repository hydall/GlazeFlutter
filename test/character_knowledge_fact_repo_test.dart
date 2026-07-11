import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glaze_flutter/core/db/app_db.dart';
import 'package:glaze_flutter/core/db/repositories/character_knowledge_fact_repo.dart';
import 'package:glaze_flutter/core/models/character_knowledge_fact.dart';

void main() {
  late AppDatabase db;
  late CharacterKnowledgeFactRepo repo;

  CharacterKnowledgeFact fact({
    String id = 'fact-1',
    String sessionId = 'session-1',
    String messageId = 'message-1',
    int swipeId = 0,
    int agentSwipeId = 0,
  }) => CharacterKnowledgeFact(
    id: id,
    chatSessionId: sessionId,
    knowerKey: 'entity:lucy',
    knowerName: 'Lucy',
    subjectKey: 'entity:danvi',
    subjectName: 'Danvi',
    factClass: CharacterKnowledgeFactClass.relationship,
    scopeKey: 'relationship:danvi',
    predicate: 'trusts',
    object: 'trusts Danvi with netrunning work',
    epistemicState: CharacterKnowledgeEpistemicState.confirmed,
    confidence: 0.9,
    importance: 0.8,
    entities: const ['Lucy', 'Danvi'],
    topics: const ['trust', 'netrunning'],
    sourceMessageId: messageId,
    sourceSwipeId: swipeId,
    sourceAgentSwipeId: agentSwipeId,
  );

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = CharacterKnowledgeFactRepo(db);
  });
  tearDown(() => db.close());

  test('tentative facts stay invisible until their anchor commits', () async {
    await repo.insertTentative(fact());

    expect(await repo.getActiveForSession('session-1'), isEmpty);

    await repo.activateAnchor(
      sessionId: 'session-1',
      messageId: 'message-1',
      swipeId: 0,
      agentSwipeId: 0,
    );

    expect((await repo.getActiveForSession('session-1')).single.id, 'fact-1');
  });

  test(
    'replaying an anchor replaces its tentative export instead of duplicating',
    () async {
      await repo.insertTentative(fact(id: 'old'));
      await repo.insertTentative(fact(id: 'replacement'));

      final atAnchor = await repo.getBySourceAnchor(
        sessionId: 'session-1',
        messageId: 'message-1',
        swipeId: 0,
        agentSwipeId: 0,
      );
      expect(atAnchor.map((item) => item.id), ['replacement']);
    },
  );

  test(
    'superseding preserves the old row but excludes it from active retrieval',
    () async {
      await repo.insertTentative(fact(id: 'old'));
      await repo.activateAnchor(
        sessionId: 'session-1',
        messageId: 'message-1',
        swipeId: 0,
        agentSwipeId: 0,
      );

      await repo.supersede('old', fact(id: 'new', messageId: 'message-2'));

      expect(
        (await repo.getActiveForSession('session-1')).map((item) => item.id),
        ['new'],
      );
      final old = await repo.getById('old');
      expect(old!.lifecycle, CharacterKnowledgeFactLifecycle.superseded);
      expect((await repo.getById('new'))!.supersedesId, 'old');
    },
  );

  test(
    'retracting an anchor removes facts from active retrieval without delete',
    () async {
      await repo.insertTentative(fact());
      await repo.activateAnchor(
        sessionId: 'session-1',
        messageId: 'message-1',
        swipeId: 0,
        agentSwipeId: 0,
      );

      await repo.retractAnchor(
        sessionId: 'session-1',
        messageId: 'message-1',
        swipeId: 0,
        agentSwipeId: 0,
      );

      expect(await repo.getActiveForSession('session-1'), isEmpty);
      expect(
        (await repo.getById('fact-1'))!.lifecycle,
        CharacterKnowledgeFactLifecycle.retracted,
      );
    },
  );

  test(
    'retracting a deleted message tombstones every swipe at that message',
    () async {
      await repo.insertTentative(fact(id: 'swipe-0', swipeId: 0));
      await repo.insertTentative(fact(id: 'swipe-1', swipeId: 1));
      await repo.activateAnchor(
        sessionId: 'session-1',
        messageId: 'message-1',
        swipeId: 0,
        agentSwipeId: 0,
      );
      await repo.activateAnchor(
        sessionId: 'session-1',
        messageId: 'message-1',
        swipeId: 1,
        agentSwipeId: 0,
      );

      await repo.retractForMessage('session-1', 'message-1');

      expect(await repo.getActiveForSession('session-1'), isEmpty);
      expect(
        (await repo.getById('swipe-0'))!.lifecycle,
        CharacterKnowledgeFactLifecycle.retracted,
      );
      expect(
        (await repo.getById('swipe-1'))!.lifecycle,
        CharacterKnowledgeFactLifecycle.retracted,
      );
    },
  );

  test(
    'branch copies only facts whose source messages exist in the slice',
    () async {
      await repo.insertTentative(fact(id: 'kept', messageId: 'message-1'));
      await repo.insertTentative(fact(id: 'skipped', messageId: 'message-2'));
      await repo.activateAnchor(
        sessionId: 'session-1',
        messageId: 'message-1',
        swipeId: 0,
        agentSwipeId: 0,
      );
      await repo.activateAnchor(
        sessionId: 'session-1',
        messageId: 'message-2',
        swipeId: 0,
        agentSwipeId: 0,
      );

      await repo.copyForSessionBranch(
        fromSessionId: 'session-1',
        toSessionId: 'branch-1',
        messageIds: const {'message-1'},
      );

      expect(
        (await repo.getActiveForSession('branch-1')).map((item) => item.id),
        ['kept@branch-1'],
      );
    },
  );
}
