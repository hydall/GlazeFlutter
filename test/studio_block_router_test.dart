import 'package:flutter_test/flutter_test.dart';
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
    final router = StudioBlockRouter((p, {apiConfig, cancelToken}) async => null);
    final validBuckets = {'continuity', 'agency', 'final'};
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
      final map = router.parseForTest('not json at all', validBuckets, validBlocks);
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
      final router = StudioBlockRouter((p, {apiConfig, cancelToken}) async => '');
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
      final router = StudioBlockRouter((p, {apiConfig, cancelToken}) async => null);
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
  });
}
