import 'package:flutter_test/flutter_test.dart';
import 'package:glaze_flutter/core/models/chat_message.dart';
import 'package:glaze_flutter/features/chat/chat_state.dart';
import 'package:glaze_flutter/features/chat/services/image_gen_processor.dart';

void main() {
  ChatSession session(String id, String content) => ChatSession(
    id: id,
    characterId: 'character',
    sessionIndex: 0,
    messages: [
      ChatMessage(id: 'assistant', role: 'assistant', content: content),
    ],
  );

  group('ImageGenProcessor owned state merging', () {
    test('merges a current image update onto live chat state', () {
      final originalSession = session('session-1', '[IMG:GEN]');
      final liveState = ChatState(
        session: originalSession,
        isGenerating: true,
        isGeneratingImage: true,
        isPostGenRunning: true,
        error: 'unrelated live state',
        visibleStartIndex: 4,
      );
      final imageUpdate = ChatState(
        session: session('session-1', '[IMG:RESULT:/images/result.png]'),
        isGeneratingImage: false,
      );

      final merged = ImageGenProcessor.mergeOwnedStateUpdate(
        liveState: liveState,
        update: imageUpdate,
        sessionId: 'session-1',
        ownsOperation: true,
      );

      expect(merged, isNotNull);
      expect(
        merged!.messages.single.content,
        '[IMG:RESULT:/images/result.png]',
      );
      expect(merged.isGenerating, isTrue);
      expect(merged.isPostGenRunning, isTrue);
      expect(merged.error, 'unrelated live state');
      expect(merged.visibleStartIndex, 4);
      expect(merged.isGeneratingImage, isFalse);
    });

    test('drops late callbacks after stop or replacement generation', () {
      final liveState = ChatState(
        session: session('session-1', '[IMG:GEN]'),
        isGeneratingImage: false,
      );
      final staleUpdate = ChatState(
        session: session('session-1', '[IMG:RESULT:/images/stale.png]'),
        isGeneratingImage: false,
      );

      final merged = ImageGenProcessor.mergeOwnedStateUpdate(
        liveState: liveState,
        update: staleUpdate,
        sessionId: 'session-1',
        ownsOperation: false,
      );

      expect(merged, isNull);
      expect(liveState.messages.single.content, '[IMG:GEN]');
      expect(liveState.isGeneratingImage, isFalse);
    });

    test('drops an owned callback when the live session changed', () {
      final liveState = ChatState(
        session: session('new-session', 'new generation'),
        isGenerating: true,
      );
      final staleUpdate = ChatState(
        session: session('old-session', '[IMG:RESULT:/images/old.png]'),
        isGeneratingImage: false,
      );

      final merged = ImageGenProcessor.mergeOwnedStateUpdate(
        liveState: liveState,
        update: staleUpdate,
        sessionId: 'old-session',
        ownsOperation: true,
      );

      expect(merged, isNull);
      expect(liveState.messages.single.content, 'new generation');
      expect(liveState.isGenerating, isTrue);
    });
  });
}
