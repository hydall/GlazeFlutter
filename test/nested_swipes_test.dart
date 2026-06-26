import 'package:flutter_test/flutter_test.dart';

import 'package:glaze_flutter/core/models/chat_message.dart';
import 'package:glaze_flutter/features/chat/services/saved_message_writer.dart';

void main() {
  group('AgentSwipe', () {
    test('toJson/fromJson roundtrip preserves all fields', () {
      final swipe = AgentSwipe(
        content: 'hello',
        kind: 'cleaned',
        reasoning: 'thought',
        genTime: '1.5s',
        tokens: 42,
        studioOutputs: [
          {'id': 'out1', 'content': 'brief'},
        ],
        parentSwipeId: 0,
      );
      final json = swipe.toJson();
      final restored = AgentSwipe.fromJson(json);
      expect(restored.content, 'hello');
      expect(restored.kind, 'cleaned');
      expect(restored.reasoning, 'thought');
      expect(restored.genTime, '1.5s');
      expect(restored.tokens, 42);
      expect(restored.parentSwipeId, 0);
      expect(restored.studioOutputs.length, 1);
      expect(restored.studioOutputs[0]['id'], 'out1');
    });

    test('fromJson defaults kind to final when missing', () {
      final restored = AgentSwipe.fromJson({'content': 'text'});
      expect(restored.kind, 'final');
      expect(restored.content, 'text');
    });

    test('fromJson defaults studioOutputs to empty list when missing', () {
      final restored = AgentSwipe.fromJson({'content': 'text'});
      expect(restored.studioOutputs, isEmpty);
    });

    test('copyWith creates a modified copy', () {
      const original = AgentSwipe(content: 'a', kind: 'final');
      final modified = original.copyWith(content: 'b', kind: 'cleaned');
      expect(modified.content, 'b');
      expect(modified.kind, 'cleaned');
      expect(modified.reasoning, isNull);
    });
  });

  group('ChatMessage agentSwipes serialization', () {
    test('toJson includes agentSwipes and agentSwipeId', () {
      final msg = ChatMessage(
        id: 'm1',
        role: 'assistant',
        content: 'active',
        swipes: ['active', 'old'],
        swipeId: 1,
        agentSwipes: [
          const AgentSwipe(content: 'final', kind: 'final'),
          const AgentSwipe(content: 'cleaned', kind: 'cleaned'),
        ],
        agentSwipeId: 1,
      );
      final json = msg.toJson();
      expect(json['agentSwipes'], isA<List>());
      expect((json['agentSwipes'] as List).length, 2);
      expect(json['agentSwipeId'], 1);
    });

    test('fromJson restores agentSwipes with correct kinds', () {
      final json = {
        'id': 'm1',
        'role': 'assistant',
        'content': 'active',
        'swipes': ['a', 'b'],
        'swipeId': 1,
        'agentSwipes': [
          {'content': 'final', 'kind': 'final'},
          {'content': 'cleaned', 'kind': 'cleaned'},
        ],
        'agentSwipeId': 1,
      };
      final msg = ChatMessage.fromJson(json);
      expect(msg.agentSwipes.length, 2);
      expect(msg.agentSwipes[0].kind, 'final');
      expect(msg.agentSwipes[1].kind, 'cleaned');
      expect(msg.agentSwipeId, 1);
    });

    test('fromJson defaults agentSwipes to empty when absent', () {
      final json = {
        'id': 'm1',
        'role': 'assistant',
        'content': 'text',
        'swipes': ['text'],
        'swipeId': 0,
      };
      final msg = ChatMessage.fromJson(json);
      expect(msg.agentSwipes, isEmpty);
      expect(msg.agentSwipeId, 0);
    });
  });

  group('SavedMessageWriter nested swipes', () {
    const writer = SavedMessageWriter();

    ChatSession makeSessionWithMessage(ChatMessage msg) {
      return ChatSession(
        id: 's1',
        characterId: 'c1',
        sessionIndex: 0,
        messages: [msg],
      );
    }

    test('new generation seeds agentSwipes with a single final', () {
      final session = makeSessionWithMessage(
        ChatMessage(
          id: 'u1',
          role: 'user',
          content: 'hello',
        ),
      );
      final state = writer.writeAssistant(
        text: 'response',
        reasoning: null,
        currentSession: session,
        isAborted: () => false,
      );
      final assistant = state.session!.messages.last;
      expect(assistant.agentSwipes.length, 1);
      expect(assistant.agentSwipes[0].kind, 'final');
      expect(assistant.agentSwipes[0].content, 'response');
      expect(assistant.agentSwipeId, 0);
    });

    test('full regen resets agentSwipes to a single final', () {
      final existing = ChatMessage(
        id: 'a1',
        role: 'assistant',
        content: 'old',
        swipes: ['old'],
        swipeId: 0,
        agentSwipes: [
          const AgentSwipe(content: 'old', kind: 'final'),
          const AgentSwipe(content: 'cleaned', kind: 'cleaned'),
        ],
        agentSwipeId: 1,
      );
      final session = makeSessionWithMessage(existing);
      final state = writer.writeAssistant(
        text: 'new response',
        reasoning: null,
        currentSession: session,
        isAborted: () => false,
        previousSwipes: ['old'],
        previousSwipeId: 0,
        regenTargetId: 'a1',
        studioFinalOnly: false,
      );
      final updated = state.session!.messages.first;
      expect(updated.agentSwipes.length, 1);
      expect(updated.agentSwipes[0].kind, 'final');
      expect(updated.agentSwipes[0].content, 'new response');
      expect(updated.agentSwipeId, 0);
      // Full regen adds to swipes (green).
      expect(updated.swipes.length, 2);
      expect(updated.swipeId, 1);
    });

    test('studioFinalOnly appends to agentSwipes, freezes swipes', () {
      final existing = ChatMessage(
        id: 'a1',
        role: 'assistant',
        content: 'final v1',
        swipes: ['final v1'],
        swipeId: 0,
        agentSwipes: [
          const AgentSwipe(content: 'final v1', kind: 'final'),
        ],
        agentSwipeId: 0,
      );
      final session = makeSessionWithMessage(existing);
      final state = writer.writeAssistant(
        text: 'final v2',
        reasoning: null,
        currentSession: session,
        isAborted: () => false,
        previousSwipes: ['final v1'],
        previousSwipeId: 0,
        regenTargetId: 'a1',
        studioFinalOnly: true,
      );
      final updated = state.session!.messages.first;
      // agentSwipes gets the new 'final' appended.
      expect(updated.agentSwipes.length, 2);
      expect(updated.agentSwipes[0].content, 'final v1');
      expect(updated.agentSwipes[1].content, 'final v2');
      expect(updated.agentSwipes[1].kind, 'final');
      expect(updated.agentSwipeId, 1);
      // swipes[] frozen — not modified.
      expect(updated.swipes.length, 1);
      expect(updated.swipeId, 0);
      // content = new final.
      expect(updated.content, 'final v2');
    });

    test('studioFinalOnly backfills final from content if agentSwipes empty', () {
      final existing = ChatMessage(
        id: 'a1',
        role: 'assistant',
        content: 'old final',
        swipes: ['old final'],
        swipeId: 0,
        // agentSwipes empty — old message predating nested swipes.
      );
      final session = makeSessionWithMessage(existing);
      final state = writer.writeAssistant(
        text: 'new final',
        reasoning: null,
        currentSession: session,
        isAborted: () => false,
        previousSwipes: ['old final'],
        previousSwipeId: 0,
        regenTargetId: 'a1',
        studioFinalOnly: true,
      );
      final updated = state.session!.messages.first;
      // Backfilled 'old final' + new 'new final'.
      expect(updated.agentSwipes.length, 2);
      expect(updated.agentSwipes[0].content, 'old final');
      expect(updated.agentSwipes[0].kind, 'final');
      expect(updated.agentSwipes[1].content, 'new final');
    });
  });
}
