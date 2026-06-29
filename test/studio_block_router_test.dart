import 'package:flutter_test/flutter_test.dart';
import 'package:glaze_flutter/core/llm/studio_block_classifier.dart';
import 'package:glaze_flutter/core/llm/studio_block_router.dart';
import 'package:glaze_flutter/core/llm/studio_decomposition_service.dart';
import 'package:glaze_flutter/core/models/preset.dart';

PresetBlock _block({
  required String id,
  String name = '',
  String role = 'system',
  String content = '',
}) {
  return PresetBlock(id: id, name: name, role: role, content: content);
}

const _buckets = [
  RouterBucket(id: 'continuity', name: 'Continuity', purpose: 'facts'),
  RouterBucket(id: 'agency', name: 'Agency', purpose: 'autonomy'),
  RouterBucket(id: 'final', name: 'Main Responder', purpose: 'final reply'),
];

void main() {
  group('StudioBlockRouter.parse', () {
    final router = StudioBlockRouter(
      (p, {apiConfig, cancelToken}) async => null,
    );
    final validBuckets = {'continuity', 'agency', 'final', kRouterDropBucketId};
    final validBlocks = {'b1', 'b2', 'b3'};

    test('parses clean JSON assignments', () {
      const json =
          '{"assignments":[{"block":"b1","bucket":"continuity"},'
          '{"block":"b2","bucket":"agency"}]}';
      final map = router.parseForTest(json, validBuckets, validBlocks);
      expect(map, {'b1': 'continuity', 'b2': 'agency'});
    });

    test('tolerates markdown fences and surrounding prose', () {
      const json =
          'Here you go:\n```json\n'
          '{"assignments":[{"block":"b3","bucket":"final"}]}\n```\nDone.';
      final map = router.parseForTest(json, validBuckets, validBlocks);
      expect(map, {'b3': 'final'});
    });

    test('drops unknown bucket ids', () {
      const json =
          '{"assignments":[{"block":"b1","bucket":"nonexistent"},'
          '{"block":"b2","bucket":"agency"}]}';
      final map = router.parseForTest(json, validBuckets, validBlocks);
      expect(map, {'b2': 'agency'});
    });

    test('drops unknown block ids', () {
      const json =
          '{"assignments":[{"block":"ghost","bucket":"final"},'
          '{"block":"b1","bucket":"continuity"}]}';
      final map = router.parseForTest(json, validBuckets, validBlocks);
      expect(map, {'b1': 'continuity'});
    });

    test('returns empty on malformed JSON', () {
      final map = router.parseForTest(
        'not json at all',
        validBuckets,
        validBlocks,
      );
      expect(map, isEmpty);
    });

    test('returns empty when assignments missing', () {
      final map = router.parseForTest('{"foo":1}', validBuckets, validBlocks);
      expect(map, isEmpty);
    });

    test('last assignment wins on duplicate block id', () {
      const json =
          '{"assignments":[{"block":"b1","bucket":"continuity"},'
          '{"block":"b1","bucket":"agency"}]}';
      final map = router.parseForTest(json, validBuckets, validBlocks);
      expect(map, {'b1': 'agency'});
    });

    test('accepts the special drop bucket for reasoning blocks', () {
      const json =
          '{"assignments":[{"block":"b1","bucket":"drop"},'
          '{"block":"b2","bucket":"final"}]}';
      final map = router.parseForTest(json, validBuckets, validBlocks);
      expect(map, {'b1': kRouterDropBucketId, 'b2': 'final'});
    });
  });

  group('StudioBlockClassifier beauty routing', () {
    test('routes reusable color/font settings to Beauty Shard', () {
      final block = _block(
        id: 'colored_dialogue',
        name: 'Colored Character Dialogue',
        content:
            'Wrap dialogue in <font color=#abc123> tags. Reuse colors for the same speaker. Palette: dark. Font-family: sans-serif.',
      );

      expect(StudioBlockClassifier.bucketForBlock(block), 'beauty');
    });

    test('does not route concrete HTML widgets to Beauty Shard', () {
      final block = _block(
        id: 'phone_ui',
        name: 'HTML Phone Screen',
        content:
            'Create a concrete phone screen taxi-call menu with checkbox hack, buttons, and carousel UI.',
      );

      expect(StudioBlockClassifier.bucketForBlock(block), isNot('beauty'));
    });

    test('does not route image generation blocks to Beauty Shard', () {
      final block = _block(
        id: 'img_gen',
        name: 'IMG:GEN Output',
        content:
            'Append visual HTML card with <img data-iig-instruction={} src="[IMG:GEN]">.',
      );

      expect(StudioBlockClassifier.bucketForBlock(block), isNot('beauty'));
    });

    test('does not steal Lumia/OOC block just because it has a color', () {
      final block = _block(
        id: 'lumia_ooc',
        name: 'Lumia OOCs',
        content:
            'Every 4 weaves append <lumiaooc><font color="#9370DB">commentary</font></lumiaooc>.',
      );

      expect(StudioBlockClassifier.bucketForBlock(block), 'meta');
    });
  });

  group('StudioBlockRouter.route drop bucket', () {
    test('route() accepts drop without falling back to keywords', () async {
      final router = StudioBlockRouter(
        (p, {apiConfig, cancelToken}) async =>
            '{"assignments":[{"block":"b1","bucket":"drop"}]}',
      );
      final result = await router.route(
        blocks: [_block(id: 'b1', name: 'CoT Gemini')],
        buckets: _buckets,
      );
      expect(result.fromLlm, isTrue);
      expect(result.isDropped('b1'), isTrue);
      expect(result.bucketFor('b1'), kRouterDropBucketId);
    });

    test('prompt documents the drop bucket and its narrow use', () {
      final router = StudioBlockRouter(
        (p, {apiConfig, cancelToken}) async => null,
      );
      final prompt = router.buildPromptForTest(
        blocks: [_block(id: 'b1', name: 'CoT')],
        buckets: _buckets,
      );
      expect(prompt, contains(kRouterDropBucketId));
      expect(prompt.toLowerCase(), contains('chain-of-thought'));
      // Must warn against dropping mere mentions (language/meta blocks).
      expect(prompt.toLowerCase(), contains('language'));
    });
  });

  group('StudioBlockRouter.route (LLM)', () {
    test('uses LLM map when classifier returns valid JSON', () async {
      final router = StudioBlockRouter(
        (p, {apiConfig, cancelToken}) async =>
            '{"assignments":[{"block":"b1","bucket":"agency"}]}',
      );
      final result = await router.route(
        blocks: [_block(id: 'b1', name: 'Persona')],
        buckets: _buckets,
      );
      expect(result.fromLlm, isTrue);
      expect(result.bucketFor('b1'), 'agency');
    });

    test('falls back (empty) when classifier returns empty string', () async {
      final router = StudioBlockRouter(
        (p, {apiConfig, cancelToken}) async => '',
      );
      final result = await router.route(
        blocks: [_block(id: 'b1')],
        buckets: _buckets,
      );
      expect(result.fromLlm, isFalse);
      expect(result.blockToBucket, isEmpty);
    });

    test('falls back (empty) on classifier exception', () async {
      final router = StudioBlockRouter(
        (p, {apiConfig, cancelToken}) async => throw StateError('boom'),
      );
      final result = await router.route(
        blocks: [_block(id: 'b1')],
        buckets: _buckets,
      );
      expect(result.fromLlm, isFalse);
      expect(result.blockToBucket, isEmpty);
    });

    test('empty for empty inputs without calling LLM', () async {
      var called = false;
      final router = StudioBlockRouter((p, {apiConfig, cancelToken}) async {
        called = true;
        return '{}';
      });
      final result = await router.route(blocks: const [], buckets: _buckets);
      expect(result, same(BlockRoutingMap.empty));
      expect(called, isFalse);
    });

    test('prompt lists every bucket and block', () async {
      final router = StudioBlockRouter(
        (p, {apiConfig, cancelToken}) async => null,
      );
      final prompt = router.buildPromptForTest(
        blocks: [
          _block(id: 'b1', name: 'CoT Gemini', content: 'think step by step'),
          _block(id: 'b2', name: 'Persona'),
        ],
        buckets: _buckets,
      );
      expect(prompt, contains('continuity'));
      expect(prompt, contains('agency'));
      expect(prompt, contains('final'));
      expect(prompt, contains('b1'));
      expect(prompt, contains('b2'));
      expect(prompt, contains('CoT Gemini'));
    });
  });

  group('isReasoningBlock', () {
    test('detects CoT by name (the reported "CoT Gemini" case)', () {
      expect(
        StudioDecompositionService.isReasoningBlock(
          _block(id: 'x', name: 'CoT Gemini', content: 'whatever'),
        ),
        isTrue,
      );
    });

    test('detects chain of thought / reasoning / thinking by name', () {
      for (final n in [
        'Chain of Thought',
        'chain-of-thought scaffold',
        'Reasoning template',
        'Thinking block',
        'Think Template',
      ]) {
        expect(
          StudioDecompositionService.isReasoningBlock(_block(id: 'x', name: n)),
          isTrue,
          reason: 'expected "$n" to be reasoning',
        );
      }
    });

    test('detects by <think> tags in content', () {
      expect(
        StudioDecompositionService.isReasoningBlock(
          _block(
            id: 'x',
            name: 'Hidden planning',
            content: 'Before replying, <think>plan here</think> then answer.',
          ),
        ),
        isTrue,
      );
    });

    test('does NOT flag normal blocks that merely mention thinking', () {
      expect(
        StudioDecompositionService.isReasoningBlock(
          _block(
            id: 'x',
            name: 'Character Personality',
            content: 'She thinks carefully before she speaks.',
          ),
        ),
        isFalse,
      );
    });

    test('does NOT flag persona/scenario blocks', () {
      for (final n in ['User Persona', 'Scenario', 'Character Description']) {
        expect(
          StudioDecompositionService.isReasoningBlock(_block(id: 'x', name: n)),
          isFalse,
          reason: '"$n" should not be reasoning',
        );
      }
    });

    test('detects CoT by id', () {
      expect(
        StudioDecompositionService.isReasoningBlock(
          _block(id: 'cot_gemini', name: ''),
        ),
        isTrue,
      );
    });

    test('does NOT flag a LANGUAGE block that merely mentions </think>', () {
      // Regression: this block was previously dropped, losing the output
      // language. It references <think> only to scope a language rule.
      const content =
          '{{setvar::output_language::Russian}}\n'
          '<language>\nRUSSIAN ONLY - ABSOLUTE COMPLIANCE REQUIRED\n'
          'CRITICAL EXCEPTION:\n'
          '- The <think> block must be written in English as technical '
          'planning.\n'
          '- Everything AFTER </think> must be written in Russian.\n'
          'RUSSIAN OUTPUT RULES:\n- Dialogue uses double quotes.\n'
          '- Do not use em-dashes as narration separators.\n</language>';
      expect(
        StudioDecompositionService.isReasoningBlock(
          _block(
            id: 'lang_ru',
            name: '🇷🇺 LANGUAGE: Russian (Русский)',
            content: content,
          ),
        ),
        isFalse,
        reason: 'a language rule is not a reasoning template',
      );
    });

    test('does NOT flag a meta/lore block that describes a <think> block', () {
      const content =
          '<lumia_ghost>\n# Lumia: Ghost in the Machine\n'
          'You are accompanied by Lumia, an invisible meta-weaver.\n'
          'Lumia silently guides storycraft, continuity, pacing, emotion.\n'
          '## Language Rule\n'
          '- The hidden <think> block remains English if the preset requires '
          'it.\n'
          '- All visible narrative and Lumia OOC replies after </think> must '
          'follow the active language preset, usually Russian.\n</lumia_ghost>';
      expect(
        StudioDecompositionService.isReasoningBlock(
          _block(
            id: 'lumia',
            name: 'Lumia: Ghost in the Machine',
            content: content,
          ),
        ),
        isFalse,
        reason: 'a meta/lore block is not a reasoning template',
      );
    });

    test('DOES flag a real CoT scaffold dominated by <think> content', () {
      // Mimics the real "CoT Gemini" block: most content lives inside <think>.
      final inside = 'INTERNAL PLANNING STEP. ' * 60; // long body
      final content =
          'After </think>, output ONLY the final reply.\n'
          '<think>\n$inside\n</think>';
      expect(
        StudioDecompositionService.isReasoningBlock(
          _block(id: 'cot_block', name: 'Hidden Planner', content: content),
        ),
        isTrue,
      );
    });
  });

  group('isBroadcastBlock', () {
    test('flags language blocks', () {
      expect(
        StudioDecompositionService.isBroadcastBlock(
          _block(id: 'x', name: '🇷🇺 LANGUAGE: Russian (Русский)'),
        ),
        isTrue,
      );
    });

    test('flags prose-quality guard blocks', () {
      for (final n in [
        '🔁 Anti-Loop System ~ Анти-луп',
        '✨ Anti-Cliché Filter ~ Анти-клише',
        '🤐 Anti-Echo ~ Анти-эхо',
        '❌Ban Rus',
      ]) {
        expect(
          StudioDecompositionService.isBroadcastBlock(_block(id: 'x', name: n)),
          isTrue,
          reason: '"$n" should broadcast to final + cleaner',
        );
      }
    });

    test('does NOT flag normal narrative/persona blocks', () {
      for (final n in [
        '🎭 Character Personality',
        '📍 Scenario',
        '✍🏻Writer style ~ Стиль автора',
        '💕 Romantic ~ Романтика',
      ]) {
        expect(
          StudioDecompositionService.isBroadcastBlock(_block(id: 'x', name: n)),
          isFalse,
          reason: '"$n" is agent-local, not broadcast',
        );
      }
    });

    test('does NOT flag reasoning blocks', () {
      expect(
        StudioDecompositionService.isBroadcastBlock(
          _block(id: 'cot', name: 'CoT Gemini'),
        ),
        isFalse,
      );
    });

    test('flags LENGTH blocks', () {
      for (final n in [
        '📏 LENGTH: Medium ~ Средний ответ',
        '📏 LENGTH: Long ~ Длинный ответ',
        '📏 LENGTH: Short ~ Короткий ответ',
      ]) {
        expect(
          StudioDecompositionService.isBroadcastBlock(_block(id: 'x', name: n)),
          isTrue,
          reason: '"$n" should broadcast to final + cleaner',
        );
      }
    });
  });

  group('expandBlocksForRouting (setvar/getvar pipeline)', () {
    test('surfaces setvar-only block rules as content', () {
      // LENGTH block: pure setvar, no visible text after expansion.
      final lengthBlock = PresetBlock(
        id: 'length_medium',
        name: '📏 LENGTH: Medium ~ Средний ответ',
        role: 'system',
        content:
            '{{setvar::length_words_min::800}}{{trim}}\n'
            '{{setvar::length_words_max::900}}{{trim}}\n'
            '{{setvar::length_mode::medium}}{{trim}}\n'
            '{{setvar::length_target::800-900 Russian words, 6-8 paragraphs}}{{trim}}\n'
            '{{setvar::length_rules::\n'
            '- Main narrative must be 800-900 Russian words.\n'
            '- Use 6-8 paragraphs.\n'
            '- Each paragraph should be 3-5 sentences.}}{{trim}}',
      );
      final result = StudioDecompositionService.expandBlocksForRouting([
        lengthBlock,
      ]);
      expect(result, hasLength(1));
      expect(result.first.content, contains('800-900 Russian words'));
      expect(result.first.content, contains('6-8 paragraphs'));
      // Technical flags (mode/min/max) should NOT appear as standalone.
      expect(result.first.content, isNot(contains('medium')));
    });

    test('resolves getvar in a self-contained block (Ban)', () {
      final banBlock = PresetBlock(
        id: 'ban_rus',
        name: '❌Ban Rus',
        role: 'system',
        content:
            '{{setvar::ban_rules::\n'
            'Forbidden words:\n- озон\n- мускус\n}}{{trim}}\n\n'
            '<ban_rules>\n{{getvar::ban_rules}}\n</ban_rules>',
      );
      final result = StudioDecompositionService.expandBlocksForRouting([
        banBlock,
      ]);
      expect(result, hasLength(1));
      // getvar should be resolved to the ban list text.
      expect(result.first.content, contains('Forbidden words'));
      expect(result.first.content, contains('озон'));
      expect(result.first.content, contains('мускус'));
      // No raw macro tags should remain.
      expect(result.first.content, isNot(contains('{{')));
    });

    test('resolves getvar across blocks (setvar in A, getvar in B)', () {
      final setter = PresetBlock(
        id: 'core_vars',
        name: '✨ Core Variables',
        role: 'system',
        content:
            '{{setvar::agency_rules::\n'
            '- Never write for {{user}}.\n'
            '- Characters act from established knowledge.}}{{trim}}',
      );
      final getter = PresetBlock(
        id: 'cot_gemini',
        name: 'CoT Gemini',
        role: 'system',
        content: 'Rules:\n{{getvar::agency_rules}}\nEnd.',
      );
      final result = StudioDecompositionService.expandBlocksForRouting([
        setter,
        getter,
      ]);
      // setter is setvar-only → surfaced as content.
      expect(result, hasLength(2));
      expect(result[0].content, contains('Never write for'));
      expect(result[0].content, contains('established knowledge'));
      // getter has getvar resolved from setter's variable.
      expect(result[1].content, contains('Never write for'));
      expect(result[1].content, contains('End.'));
      expect(result[1].content, isNot(contains('{{getvar')));
    });

    test(
      'drops blocks that are empty after expansion (no setvar, no text)',
      () {
        final empty = PresetBlock(
          id: 'empty_block',
          name: 'Empty',
          role: 'system',
          content: '{{trim}}',
        );
        final result = StudioDecompositionService.expandBlocksForRouting([
          empty,
        ]);
        expect(result, isEmpty);
      },
    );

    test('leaves non-variable macros untouched for chat-time expansion', () {
      final block = PresetBlock(
        id: 'narrative',
        name: 'Narrative',
        role: 'system',
        content:
            '{{char}} looks at {{user}} and says: hello.\n'
            '{{setvar::pov_mode::third}}{{trim}}',
      );
      final result = StudioDecompositionService.expandBlocksForRouting([block]);
      // {{char}} and {{user}} should remain as literals.
      expect(result.first.content, contains('{{char}}'));
      expect(result.first.content, contains('{{user}}'));
      // setvar should be removed.
      expect(result.first.content, isNot(contains('{{setvar')));
    });

    test('surfaces multiple rule variables from one setvar-only block', () {
      final coreVars = PresetBlock(
        id: 'core_vars',
        name: '✨ Core Variables',
        role: 'system',
        content:
            '{{setvar::ground_truth_mode::strict}}{{trim}}\n'
            '{{setvar::ground_truth_rules::\n'
            '- Explicit user facts override drama.}}{{trim}}\n'
            '{{setvar::agency_mode::enforce}}{{trim}}\n'
            '{{setvar::agency_rules::\n'
            '- Never write for {{user}}.}}{{trim}}',
      );
      final result = StudioDecompositionService.expandBlocksForRouting([
        coreVars,
      ]);
      expect(result, hasLength(1));
      // Both *_rules values should be surfaced.
      expect(result.first.content, contains('Explicit user facts override'));
      expect(result.first.content, contains('Never write for'));
      // Technical modes should NOT appear.
      expect(result.first.content, isNot(contains('strict')));
      expect(result.first.content, isNot(contains('enforce')));
    });
  });
}
