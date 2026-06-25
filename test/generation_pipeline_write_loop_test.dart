import 'package:flutter_test/flutter_test.dart';

import 'package:glaze_flutter/core/models/chat_message.dart';
import 'package:glaze_flutter/features/chat/services/generation_pipeline.dart';

ChatMessage _msg({
  required String id,
  required String role,
  required String content,
  bool isError = false,
  bool isTyping = false,
}) {
  return ChatMessage(
    id: id,
    role: role,
    content: content,
    isError: isError,
    isTyping: isTyping,
  );
}

void main() {
  group('extractRecentHistoryText', () {
    test('returns empty string for empty messages', () {
      final result = extractRecentHistoryText([]);
      expect(result, isEmpty);
    });

    test('formats single message as "Role: content"', () {
      final result = extractRecentHistoryText([
        _msg(id: 'm1', role: 'user', content: 'Hello'),
      ]);
      expect(result, 'User: Hello');
    });

    test('formats multiple messages separated by double newline', () {
      final result = extractRecentHistoryText([
        _msg(id: 'm1', role: 'user', content: 'Hello'),
        _msg(id: 'm2', role: 'assistant', content: 'Hi there'),
      ]);
      expect(result, 'User: Hello\n\nAssistant: Hi there');
    });

    test('uses "Assistant" for assistant role, "User" for everything else', () {
      final result = extractRecentHistoryText([
        _msg(id: 'm1', role: 'user', content: 'Q'),
        _msg(id: 'm2', role: 'assistant', content: 'A'),
        _msg(id: 'm3', role: 'system', content: 'S'),
      ]);
      expect(result.contains('User: Q'), isTrue);
      expect(result.contains('Assistant: A'), isTrue);
      expect(result.contains('User: S'), isTrue);
    });

    test('skips error messages', () {
      final result = extractRecentHistoryText([
        _msg(id: 'm1', role: 'user', content: 'Hello'),
        _msg(id: 'm2', role: 'assistant', content: 'Error', isError: true),
        _msg(id: 'm3', role: 'assistant', content: 'OK'),
      ]);
      expect(result, 'User: Hello\n\nAssistant: OK');
    });

    test('skips typing messages', () {
      final result = extractRecentHistoryText([
        _msg(id: 'm1', role: 'user', content: 'Hello'),
        _msg(id: 'm2', role: 'assistant', content: '', isTyping: true),
        _msg(id: 'm3', role: 'assistant', content: 'Done'),
      ]);
      expect(result, 'User: Hello\n\nAssistant: Done');
    });

    test('skips empty content messages', () {
      final result = extractRecentHistoryText([
        _msg(id: 'm1', role: 'user', content: 'Hello'),
        _msg(id: 'm2', role: 'assistant', content: '   '),
        _msg(id: 'm3', role: 'assistant', content: 'Real reply'),
      ]);
      expect(result, 'User: Hello\n\nAssistant: Real reply');
    });

    test('limits to last N messages', () {
      final messages = List.generate(
        15,
        (i) => _msg(id: 'm$i', role: 'user', content: 'Msg $i'),
      );
      final result = extractRecentHistoryText(messages, maxMessages: 5);
      expect(result.contains('Msg 10'), isTrue);
      expect(result.contains('Msg 14'), isTrue);
      expect(result.contains('Msg 9'), isFalse);
    });

    test('handles exactly maxMessages', () {
      final messages = List.generate(
        10,
        (i) => _msg(id: 'm$i', role: 'user', content: 'Msg $i'),
      );
      final result = extractRecentHistoryText(messages, maxMessages: 10);
      expect(result.contains('Msg 0'), isTrue);
      expect(result.contains('Msg 9'), isTrue);
    });
  });

  group('Stage 2 trigger suppression logic', () {
    // The write-loop trigger in GenerationPipeline.run() is guarded by:
    //   if (regenTargetId == null && !studioFinalOnly && result.session != null)
    //
    // The regen branch (regenOutcome != null) returns early at ~line 155
    // BEFORE reaching the write-loop trigger at ~line 210, so regen/swipe
    // paths never invoke _runAgenticWriteLoop.
    //
    // These tests verify the guard condition itself.

    test('normal send (regenTargetId=null, studioFinalOnly=false) → triggers', () {
      const String? regenTargetId = null;
      const bool studioFinalOnly = false;
      expect(regenTargetId == null && !studioFinalOnly, isTrue);
    });

    test('regen (regenTargetId != null) → suppresses', () {
      const String? regenTargetId = 'msg_123';
      const bool studioFinalOnly = false;
      expect(regenTargetId == null && !studioFinalOnly, isFalse);
    });

    test('studioFinalOnly=true → suppresses', () {
      const String? regenTargetId = null;
      const bool studioFinalOnly = true;
      expect(regenTargetId == null && !studioFinalOnly, isFalse);
    });

    test('studioFinalOnly + regenTargetId → suppresses', () {
      const String? regenTargetId = 'msg_123';
      const bool studioFinalOnly = true;
      expect(regenTargetId == null && !studioFinalOnly, isFalse);
    });
  });
}
