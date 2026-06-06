import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:glaze_flutter/core/llm/prompt_builder.dart';
import 'package:glaze_flutter/core/models/api_config.dart';
import 'package:glaze_flutter/core/models/character.dart';
import 'package:glaze_flutter/core/models/chat_message.dart';
import 'package:glaze_flutter/core/models/preset.dart';
import 'package:glaze_flutter/features/extensions/services/runtime_prompt_injection_service.dart';

void main() {
  test('runtime prompt injections are session-scoped and removable', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(runtimePromptInjectionProvider.notifier);
    notifier.inject(
      sessionId: 's1',
      id: 'mood',
      content: 'Keep the scene tense.',
      depth: 1,
      role: 'system',
    );
    notifier.inject(
      sessionId: 's2',
      id: 'mood',
      content: 'Keep the scene quiet.',
    );

    expect(notifier.bySession('s1').single.content, 'Keep the scene tense.');
    expect(notifier.bySession('s2').single.content, 'Keep the scene quiet.');

    expect(notifier.uninject(sessionId: 's1', id: 'mood'), isTrue);
    expect(notifier.bySession('s1'), isEmpty);
    expect(notifier.bySession('s2'), hasLength(1));
  });

  test(
    'runtime prompt blocks are inserted by depth during prompt assembly',
    () {
      final result = buildPrompt(
        PromptPayload(
          character: Character(id: 'c1', name: 'Alice'),
          preset: const Preset(
            id: 'p1',
            name: 'Prompt',
            blocks: [
              PresetBlock(
                id: 'chat_history',
                name: 'History',
                role: 'system',
                content: '',
              ),
            ],
          ),
          history: const [
            ChatMessage(id: 'm1', role: 'user', content: 'First'),
            ChatMessage(id: 'm2', role: 'assistant', content: 'Second'),
          ],
          apiConfig: const ApiConfig(
            id: 'api',
            name: 'API',
            contextSize: 10000,
            maxTokens: 100,
          ),
          runtimePromptBlocks: const [
            RuntimePromptBlock(
              id: 'mood',
              content: 'Keep the scene tense.',
              depth: 1,
              role: 'system',
            ),
          ],
        ),
      );

      expect(result.messages.map((message) => message.content).toList(), [
        'First',
        'Keep the scene tense.',
        'Second',
      ]);
      expect(result.messages[1].blockId, 'runtime_prompt:mood');
      expect(result.messages[1].isDepth, isTrue);
    },
  );
}
