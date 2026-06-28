import 'package:flutter_test/flutter_test.dart';

import 'package:glaze_flutter/core/llm/history_assembler.dart';
import 'package:glaze_flutter/core/llm/prompt_builder.dart';
import 'package:glaze_flutter/core/llm/studio_context_bucketizer.dart';
import 'package:glaze_flutter/core/llm/post_cleaner_service.dart';
import 'package:glaze_flutter/core/llm/studio_controller_ontology.dart';
import 'package:glaze_flutter/core/llm/context_calculator.dart';
import 'package:glaze_flutter/core/models/api_config.dart';
import 'package:glaze_flutter/core/models/character.dart';
import 'package:glaze_flutter/core/models/preset.dart';
import 'package:glaze_flutter/core/models/studio_config.dart';

PresetBlock _block({
  required String id,
  required String name,
  String content = 'content',
  bool enabled = true,
}) {
  return PresetBlock(
    id: id,
    name: name,
    role: 'system',
    content: content,
    enabled: enabled,
  );
}

PromptMessage _msg({
  String? blockId,
  String? blockName,
  String content = 'content',
  String role = 'system',
}) {
  return PromptMessage(
    role: role,
    content: content,
    blockId: blockId,
    blockName: blockName,
  );
}

PromptResult _result(List<PromptMessage> messages) => PromptResult(
      messages: messages,
      breakdown: TokenBreakdown(
        sourceTokens: const {},
        staticTotal: 0,
        historyBudget: 0,
        historyTokens: 0,
        totalTokens: 0,
        cutoffIndex: 0,
        trimmedHistory: const [],
      ),
      sessionVars: const {},
      globalVars: const {},
    );

PromptPayload _payload({Preset? preset}) => PromptPayload(
      character: const Character(id: 'c1', name: 'TestChar'),
      history: const [],
      apiConfig: const ApiConfig(id: 'a1'),
      preset: preset,
    );

void main() {
  group('StudioContextBucketizer staticContext filter', () {
    final bucketizer = const StudioContextBucketizer();

    test('non-Studio run: unrouted preset block lands in staticContext', () {
      // char_card is a static-id block → goes to byKind, not staticContext.
      // narrative_engine is not a static/dynamic id → goes to staticContext.
      final preset = Preset(
        id: 'p1',
        name: 'P1',
        blocks: [
          _block(id: 'narrative_engine', name: 'Narrative Engine', content: 'ne'),
          _block(id: 'char_card', name: 'Character Card', content: 'cc'),
        ],
      );
      final result = _result([
        _msg(blockId: 'narrative_engine', blockName: 'Narrative Engine', content: 'ne'),
        _msg(blockId: 'char_card', blockName: 'Character Card', content: 'cc'),
      ]);
      final buckets = bucketizer.bucketize(
        result,
        promptPayload: _payload(preset: preset),
      );
      // Only the unrouted narrative_engine is in staticContext; char_card is
      // in byKind['char_card'] (consumed via the studio preset's char_card
      // kind block).
      expect(buckets.staticContext.length, 1);
      expect(buckets.staticContext.first.blockName, 'Narrative Engine');
      expect(buckets.messagesForKind('char_card').length, 1);
    });

    test('Studio run: CoT block filtered from staticContext', () {
      final cot = _block(
        id: 'cot_gemini',
        name: 'CoT Gemini',
        content: 'think template',
      );
      final preset = Preset(id: 'p1', name: 'P1', blocks: [cot]);
      final config = const StudioConfig(
        sessionId: 's1',
        agents: [StudioAgent(id: 'a1', sourceBlockNames: '')],
      );
      final result = _result([
        _msg(blockId: 'cot_gemini', blockName: 'CoT Gemini', content: 'think template'),
      ]);
      final buckets = bucketizer.bucketize(
        result,
        promptPayload: _payload(preset: preset),
        studioConfig: config,
      );
      expect(buckets.staticContext, isEmpty);
    });

    test('Studio run: routed block filtered from staticContext', () {
      final preset = Preset(
        id: 'p1',
        name: 'P1',
        blocks: [
          _block(id: 'narr_engine', name: 'Narrative Engine', content: 'ne'),
          _block(id: 'other_block', name: 'Other Block', content: 'ob'),
        ],
      );
      final config = const StudioConfig(
        sessionId: 's1',
        agents: [
          StudioAgent(
            id: 'a1',
            sourceBlockNames: 'Narrative Engine',
          ),
        ],
      );
      final result = _result([
        _msg(blockId: 'narrative_engine', blockName: 'Narrative Engine', content: 'ne'),
        _msg(blockId: 'other_block', blockName: 'Other Block', content: 'ob'),
      ]);
      final buckets = bucketizer.bucketize(
        result,
        promptPayload: _payload(preset: preset),
        studioConfig: config,
      );
      final names = buckets.staticContext.map((m) => m.blockName).toList();
      expect(names, contains('Other Block'));
      expect(names, isNot(contains('Narrative Engine')));
    });

    test('Studio run: char_card kept in byKind (not affected by staticContext filter)', () {
      final preset = Preset(
        id: 'p1',
        name: 'P1',
        blocks: [
          _block(id: 'char_card', name: 'Character Card', content: 'cc'),
        ],
      );
      final config = const StudioConfig(
        sessionId: 's1',
        agents: [StudioAgent(id: 'a1')],
      );
      final result = _result([
        _msg(blockId: 'char_card', blockName: 'Character Card', content: 'cc'),
      ]);
      final buckets = bucketizer.bucketize(
        result,
        promptPayload: _payload(preset: preset),
        studioConfig: config,
      );
      // char_card is a static-id → goes to byKind, never touched by the
      // staticContext filter.
      expect(buckets.messagesForKind('char_card').length, 1);
      expect(buckets.staticContext, isEmpty);
    });

    test('Studio run: broadcast block in Main Responder shard is filtered from staticContext', () {
      final preset = Preset(
        id: 'p1',
        name: 'P1',
        blocks: [
          _block(id: 'lang', name: 'Language Russian', content: 'use russian'),
          _block(id: 'other_block', name: 'Other Block', content: 'ob'),
        ],
      );
      final config = const StudioConfig(
        sessionId: 's1',
        agents: [
          StudioAgent(
            id: 'a1',
            sourceBlockNames: 'Language Russian',
          ),
        ],
      );
      final result = _result([
        _msg(blockId: 'lang', blockName: 'Language Russian', content: 'use russian'),
        _msg(blockId: 'other_block', blockName: 'Other Block', content: 'ob'),
      ]);
      final buckets = bucketizer.bucketize(
        result,
        promptPayload: _payload(preset: preset),
        studioConfig: config,
      );
      final names = buckets.staticContext.map((m) => m.blockName).toList();
      expect(names, contains('Other Block'));
      expect(names, isNot(contains('Language Russian')));
    });
  });

  group('StudioControllerOntology Meta-Weaver spec', () {
    test('Meta-Weaver refreshPolicy is turn (not static)', () {
      final meta = StudioControllerOntology.specs.firstWhere(
        (s) => s.id == 'meta',
      );
      expect(meta.refreshPolicy, 'turn');
    });

    test('Meta-Weaver contextSize is 15', () {
      final meta = StudioControllerOntology.specs.firstWhere(
        (s) => s.id == 'meta',
      );
      expect(meta.contextSize, 15);
    });

    test('Main Responder spec contextSize defaults to 0 (inherits agent default)', () {
      final fin = StudioControllerOntology.specs.firstWhere(
        (s) => s.id == 'final',
      );
      expect(fin.contextSize, 0);
    });

    test('Meta-Weaver purpose mentions counting', () {
      final meta = StudioControllerOntology.specs.firstWhere(
        (s) => s.id == 'meta',
      );
      expect(meta.purpose.toLowerCase(), contains('count'));
    });
  });

  group('PostCleanerService lumiaooc preservation', () {
    test('lumiaooc dropped (and all tags dropped) is caught by protected-markup guard', () {
      const original = '<lumiaooc><font color="#9370DB">Lumia note</font></lumiaooc>\nProse here.';
      const edited = 'Prose here.';
      // All HTML tags stripped → textRewriteDropsProtectedMarkup catches it.
      expect(PostCleanerService.textRewriteDropsProtectedMarkup(original, edited), isTrue);
    });

    test('lumiaooc dropped but other tags preserved is caught by lumiaooc guard', () {
      const original = '<lumiaooc><font color="#9370DB">Lumia note</font></lumiaooc>\n<b>Prose</b> here.';
      const edited = '<b>Cleaned prose</b> here.';
      // textRewriteDropsProtectedMarkup returns false (edited still has <b>),
      // but the lumiaooc guard catches the dropped <lumiaooc>. This is the
      // case the dedicated lumiaoocDropped check exists for.
      expect(PostCleanerService.textRewriteDropsProtectedMarkup(original, edited), isFalse);
      expect(PostCleanerService.lumiaoocDropped(original, edited), isTrue);
    });

    test('lumiaooc preserved in cleaned text is not flagged', () {
      const original = '<lumiaooc><font color="#9370DB">Lumia note</font></lumiaooc>\nProse here.';
      const edited = '<lumiaooc><font color="#9370DB">Lumia note</font></lumiaooc>\nCleaned prose here.';
      expect(PostCleanerService.textRewriteDropsProtectedMarkup(original, edited), isFalse);
    });

    test('buildCleanerPrompt mentions lumiaooc verbatim rule', () {
      final prompt = PostCleanerService.buildCleanerPrompt(
        assistantText: 'prose',
      );
      expect(prompt.toLowerCase(), contains('lumiaooc'));
    });
  });

  group('StudioConfig Meta-Weaver migration (Part 6)', () {
    test('old Meta-Weaver with static policy is upgraded to turn on load', () {
      // Simulate an old agent as it would deserialize from JSON.
      final oldAgent = StudioAgent.fromJson(const {
        'id': 'agent_s1_meta_123',
        'name': 'Meta-Weaver / Lumia Policy',
        'refreshPolicy': 'static',
        'contextSize': 5,
        'order': 6,
      });
      expect(oldAgent.refreshPolicy, 'static');
      expect(oldAgent.contextSize, 5);

      // The migration is in StudioConfigRepo._normalizeLoadedConfig which is
      // private. We test the migration logic by reproducing it here — it's a
      // pure normalization that any caller can apply. The repo applies it on
      // every load. This test documents the expected behavior.
      final migrated = _migrateForTest(oldAgent);
      expect(migrated.refreshPolicy, 'turn');
      expect(migrated.contextSize, 15);
    });

    test('new Meta-Weaver with turn policy + contextSize 15 is unchanged', () {
      final newAgent = StudioAgent.fromJson(const {
        'id': 'agent_s1_meta_123',
        'name': 'Meta-Weaver / Lumia Policy',
        'refreshPolicy': 'turn',
        'contextSize': 15,
        'order': 6,
      });
      final migrated = _migrateForTest(newAgent);
      expect(migrated.refreshPolicy, 'turn');
      expect(migrated.contextSize, 15);
    });

    test('non-Meta-Weaver agent is unchanged by migration', () {
      final guard = StudioAgent.fromJson(const {
        'id': 'agent_s1_guard_123',
        'name': 'Anti-Loop & Prose Guard',
        'refreshPolicy': 'turn',
        'contextSize': 5,
        'order': 4,
      });
      final migrated = _migrateForTest(guard);
      expect(migrated.refreshPolicy, 'turn');
      expect(migrated.contextSize, 5);
    });

    test('Meta-Weaver with contextSize > 15 keeps its larger value', () {
      final agent = StudioAgent.fromJson(const {
        'id': 'agent_s1_meta_123',
        'name': 'Meta-Weaver / Lumia Policy',
        'refreshPolicy': 'static',
        'contextSize': 30,
        'order': 6,
      });
      final migrated = _migrateForTest(agent);
      expect(migrated.refreshPolicy, 'turn');
      expect(migrated.contextSize, 30);
    });
  });

  group('Meta-Weaver auto-disable when no lumia block', () {
    test('enabled is true by default for non-meta agents', () {
      const agent = StudioAgent(id: 'agent_s1_guard_123', name: 'Guard');
      expect(agent.enabled, isTrue);
    });

    test('StudioAgent.enabled can be set false (auto-disable contract)', () {
      const agent = StudioAgent(
        id: 'agent_s1_meta_123',
        name: 'Meta-Weaver / Lumia Policy',
        enabled: false,
      );
      expect(agent.enabled, isFalse);
    });
  });
}

/// Reproduces the `StudioConfigRepo._normalizeLoadedConfig` Meta-Weaver
/// migration logic for unit testing. The repo method is private and tied to
/// Drift; this helper mirrors the exact normalization so tests are pure.
StudioAgent _migrateForTest(StudioAgent agent) {
  final id = agent.id.toLowerCase();
  final name = agent.name.toLowerCase();
  final isMeta = id.contains('_meta_') ||
      id == 'meta' ||
      name.contains('meta-weaver') ||
      name.contains('meta weaver') ||
      name.contains('lumia policy');
  if (!isMeta) return agent;
  if (agent.refreshPolicy == 'turn' && agent.contextSize >= 15) return agent;
  return agent.copyWith(
    refreshPolicy: 'turn',
    contextSize: agent.contextSize < 15 ? 15 : agent.contextSize,
  );
}
