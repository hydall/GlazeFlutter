import 'package:flutter_test/flutter_test.dart';
import 'package:glaze_flutter/core/llm/knowledge/character_knowledge_projection.dart';
import 'package:glaze_flutter/core/models/character_knowledge_fact.dart';

void main() {
  CharacterKnowledgeFact fact({
    required String id,
    required String subject,
    double importance = 0.5,
  }) => CharacterKnowledgeFact(
    id: id,
    chatSessionId: 'session-1',
    knowerKey: 'entity:lucy',
    knowerName: 'Lucy',
    subjectKey: 'entity:${subject.toLowerCase()}',
    subjectName: subject,
    factClass: CharacterKnowledgeFactClass.relationship,
    scopeKey: 'relationship:${subject.toLowerCase()}',
    predicate: 'trusts',
    object: 'trusts $subject with vulnerable work',
    epistemicState: CharacterKnowledgeEpistemicState.confirmed,
    importance: importance,
    entities: ['Lucy', subject],
    sourceMessageId: 'm1',
    sourceSwipeId: 0,
    sourceAgentSwipeId: 0,
    lifecycle: CharacterKnowledgeFactLifecycle.active,
  );

  test(
    'projects only context-relevant scoped facts without globalizing them',
    () {
      final content = compileCharacterKnowledgeProjection([
        fact(id: 'danvi', subject: 'Danvi'),
        fact(id: 'david', subject: 'David'),
      ], latestUserText: 'Danvi watches Lucy closely.');

      expect(content, contains('<current_character_state>'));
      expect(content, contains('[relationship:danvi]'));
      expect(content, contains('[relationship:david]'));
      expect(content, contains('within their stated scope'));
    },
  );

  test('caps projected facts by importance', () {
    final content = compileCharacterKnowledgeProjection([
      fact(id: 'low', subject: 'Low', importance: 0.1),
      fact(id: 'high', subject: 'High', importance: 0.9),
    ], maxFacts: 1);

    expect(content, contains('High'));
    expect(content, isNot(contains('Low')));
  });

  test('keeps current relationship truth without a literal context match', () {
    final content = compileCharacterKnowledgeProjection([
      fact(id: 'trust', subject: 'Danvi', importance: 0.9),
    ], latestUserText: 'Продолжаю разговор как обычно.');

    expect(content, contains('[relationship:danvi]'));
    expect(content, contains('override conflicting base-card traits'));
  });
}
