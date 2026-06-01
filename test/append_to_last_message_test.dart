import 'package:flutter_test/flutter_test.dart';

import 'package:glaze_flutter/core/llm/history_assembler.dart';
import 'package:glaze_flutter/core/llm/prompt_builder.dart';
import 'package:glaze_flutter/core/models/preset.dart';

void main() {
  group('PresetBlock.appendToLastMessage', () {
    test('defaults to false on a freshly built block', () {
      final block = PresetBlock(
        id: 'lore-jacket',
        name: 'Lore Jacket',
        role: 'system',
        content: 'hello',
      );
      expect(block.appendToLastMessage, isFalse);
    });

    test('roundtrips through JSON', () {
      final json = {
        'id': 'lore-jacket',
        'name': 'Lore Jacket',
        'role': 'system',
        'content': 'hello',
        'appendToLastMessage': true,
      };
      final block = PresetBlock.fromJson(json);
      expect(block.appendToLastMessage, isTrue);
      expect(block.toJson()['appendToLastMessage'], isTrue);
    });

    test('coerces non-bool to false on import (defensive)', () {
      final json = {
        'id': 'lore-jacket',
        'name': 'Lore Jacket',
        'role': 'system',
        'content': 'hello',
        'appendToLastMessage': 'yes',
      };
      final block = PresetBlock.fromJson(json);
      expect(block.appendToLastMessage, isFalse);
    });
  });

  group('applyAppendToLastMessage', () {
    List<PromptMessage> sampleHistory() => [
          const PromptMessage(
            role: 'user',
            content: 'hi',
            isHistory: true,
          ),
          const PromptMessage(
            role: 'assistant',
            content: 'hello there',
            isHistory: true,
          ),
          const PromptMessage(
            role: 'user',
            content: 'how are you?',
            isHistory: true,
          ),
        ];

    test('appends a single block to the last user message', () {
      final history = sampleHistory();
      applyAppendToLastMessage(
        history,
        [(name: 'Lore Jacket', content: '<lore>something</lore>')],
      );

      final lastUser = history.lastWhere((m) => m.role == 'user');
      expect(lastUser.content, contains('how are you?'));
      expect(lastUser.content, contains('<lore>something</lore>'));
      expect(lastUser.content.split('\n\n').length, 2);
      expect(history.length, 3);
    });

    test('appends multiple blocks in preset order, joined with \\n\\n', () {
      final history = sampleHistory();
      applyAppendToLastMessage(history, const [
        (name: 'Block A', content: 'AAA'),
        (name: 'Block B', content: 'BBB'),
      ]);

      final lastUser = history.lastWhere((m) => m.role == 'user');
      expect(lastUser.content, endsWith('AAA\n\nBBB'));
      expect(lastUser.blockName, contains('Block A'));
      expect(lastUser.blockName, contains('Block B'));
    });

    test('updates blockName to reflect merged sources', () {
      final history = [
        const PromptMessage(
          role: 'user',
          content: 'hi',
          isHistory: true,
          blockName: 'Original',
        ),
      ];
      applyAppendToLastMessage(
        history,
        [(name: 'Lore', content: 'XX')],
      );
      expect(history.first.blockName, 'Original + Lore');
    });

    test('no-op when history has no user messages', () {
      final history = [
        const PromptMessage(role: 'assistant', content: 'a', isHistory: true),
        const PromptMessage(role: 'system', content: 'b', isHistory: true),
      ];
      final before = history.map((m) => m.content).toList();
      applyAppendToLastMessage(
        history,
        [(name: 'X', content: 'should not appear')],
      );
      final after = history.map((m) => m.content).toList();
      expect(after, equals(before));
    });

    test('no-op when appendedEntries is empty', () {
      final history = sampleHistory();
      final before = history.map((m) => m.content).toList();
      applyAppendToLastMessage(history, const []);
      final after = history.map((m) => m.content).toList();
      expect(after, equals(before));
    });

    test('skips empty/whitespace-only block contents', () {
      final history = sampleHistory();
      applyAppendToLastMessage(history, const [
        (name: 'Empty', content: '   \n  '),
        (name: 'Real', content: 'real text'),
      ]);
      final lastUser = history.lastWhere((m) => m.role == 'user');
      expect(lastUser.content, contains('real text'));
      expect(lastUser.content, isNot(contains('Empty')));
    });

    test('works when there is exactly one user message at the end', () {
      final history = [
        const PromptMessage(role: 'user', content: 'only', isHistory: true),
      ];
      applyAppendToLastMessage(
        history,
        [(name: 'X', content: 'appended')],
      );
      expect(history.single.content, 'only\n\nappended');
      expect(history.single.role, 'user');
    });
  });
}
