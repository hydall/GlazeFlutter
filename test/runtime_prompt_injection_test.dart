import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:glaze_flutter/core/llm/prompt_builder.dart';
import 'package:glaze_flutter/core/llm/memory_selector.dart';
import 'package:glaze_flutter/core/models/api_config.dart';
import 'package:glaze_flutter/core/models/character.dart';
import 'package:glaze_flutter/core/models/chat_message.dart';
import 'package:glaze_flutter/core/models/memory_book.dart';
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

  test('factual-continuity guard is opt-in and prompt-only', () {
    PromptPayload payload({required bool guardActive}) => PromptPayload(
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
        ChatMessage(id: 'm1', role: 'user', content: 'Do you remember?'),
      ],
      apiConfig: const ApiConfig(
        id: 'api',
        name: 'API',
        contextSize: 10000,
        maxTokens: 100,
      ),
      memorySelection: const MemorySelection(),
      memoryCoverage: {
        'diagnostics': {
          'missingContextSuspected': true,
          'reliableCandidateFound': false,
          'factualContinuityGuardActive': guardActive,
        },
      },
    );

    final defaultResult = buildPrompt(payload(guardActive: false));
    expect(
      defaultResult.messages.any(
        (message) => message.content.contains('Factual continuity note'),
      ),
      isFalse,
    );

    final guardedResult = buildPrompt(payload(guardActive: true));
    expect(
      guardedResult.messages.any(
        (message) => message.content.contains('Factual continuity note'),
      ),
      isTrue,
    );
    expect(guardedResult.messages.where((m) => m.isHistory), hasLength(1));
  });

  test('deferred memory injection can inject source-linked excerpts', () {
    final content = [
      'The bridge scene opened with rain and silence.',
      'Sable promised Ren she would hide the ritual map until the debt was paid.',
      'They argued about lanterns and horses for several minutes.',
    ].join('\n\n');
    final entry = MemoryEntry(
      id: 'm1',
      title: 'Bridge memory',
      content: content,
      keys: const ['ritual map', 'debt'],
      status: 'active',
    );
    final selection = MemorySelector.select(
      MemorySelectionInput(
        entries: [entry],
        keywordMatchedTerms: const {
          'm1': ['ritual map', 'debt'],
        },
        maxInjectionTokens: 12,
        maxInjectedEntries: 1,
        vectorWeight: 0,
        recencyBoost: false,
        importanceBoost: false,
        diversityAware: false,
      ),
      tokenCounter: (entry) => entry.content.split(RegExp(r'\s+')).length,
    );

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
          ChatMessage(id: 'u1', role: 'user', content: 'What about the map?'),
        ],
        apiConfig: const ApiConfig(
          id: 'api',
          name: 'API',
          contextSize: 10000,
          maxTokens: 100,
        ),
        memorySelection: selection,
        memoryInjectionTarget: 'hard_block',
      ),
    );

    final memoryMessage = result.messages.firstWhere(
      (message) => message.blockId == 'memory',
    );
    expect(memoryMessage.content, contains('Excerpt from Bridge memory'));
    expect(memoryMessage.content, contains('ritual map'));
    expect(
      memoryMessage.content,
      contains('Excerpted from a larger Memory Book entry'),
    );

    final diagnostics = result.memoryCoverage['diagnostics'] as Map;
    final candidates = diagnostics['candidates'] as List;
    final candidate = candidates.single as Map;
    expect(candidate['injectionType'], 'excerpt');
    expect(
      candidate['originalTokenCost'] as int,
      greaterThan(candidate['tokenCost'] as int),
    );
  });

  test('deferred memory macro placement receives final excerpts', () {
    final content = [
      'The bridge scene opened with rain and silence.',
      'Sable promised Ren she would hide the ritual map until the debt was paid.',
      'They argued about lanterns and horses for several minutes.',
    ].join('\n\n');
    final entry = MemoryEntry(
      id: 'm1',
      title: 'Bridge memory',
      content: content,
      keys: const ['ritual map', 'debt'],
      status: 'active',
    );
    final selection = MemorySelector.select(
      MemorySelectionInput(
        entries: [entry],
        keywordMatchedTerms: const {
          'm1': ['ritual map', 'debt'],
        },
        maxInjectionTokens: 12,
        maxInjectedEntries: 1,
        vectorWeight: 0,
        recencyBoost: false,
        importanceBoost: false,
        diversityAware: false,
      ),
      tokenCounter: (entry) => entry.content.split(RegExp(r'\s+')).length,
    );

    final result = buildPrompt(
      PromptPayload(
        character: Character(id: 'c1', name: 'Alice'),
        preset: const Preset(
          id: 'p1',
          name: 'Prompt',
          blocks: [
            PresetBlock(
              id: 'memory_slot',
              name: 'Memory Slot',
              role: 'system',
              content: 'Selected memories:\n{{memory}}',
            ),
            PresetBlock(
              id: 'chat_history',
              name: 'History',
              role: 'system',
              content: '',
            ),
          ],
        ),
        history: const [
          ChatMessage(id: 'u1', role: 'user', content: 'What about the map?'),
        ],
        apiConfig: const ApiConfig(
          id: 'api',
          name: 'API',
          contextSize: 10000,
          maxTokens: 100,
        ),
        memorySelection: selection,
        memoryInjectionTarget: 'macro',
      ),
    );

    final memorySlot = result.messages.firstWhere(
      (message) => message.blockId == 'memory_slot',
    );
    expect(memorySlot.content, contains('Selected memories:'));
    expect(memorySlot.content, contains('ritual map'));
    expect(memorySlot.content, isNot(contains('GLAZE_DEFERRED')));
    expect(result.messages.where((m) => m.blockId == 'memory'), isEmpty);
    expect(result.breakdown.memoryTokens, greaterThan(0));
  });
}
