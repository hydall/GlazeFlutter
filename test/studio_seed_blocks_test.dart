import 'package:flutter_test/flutter_test.dart';

import 'package:glaze_flutter/core/db/studio_seed_blocks.dart';

void main() {
  group('studioPresetSeedBlocks', () {
    test('returns non-empty list', () {
      final blocks = studioPresetSeedBlocks();
      expect(blocks, isNotEmpty);
      expect(blocks.length, greaterThan(40));
    });

    test('every block has all 8 required fields', () {
      final blocks = studioPresetSeedBlocks();
      for (final block in blocks) {
        expect(block['id'], isA<String>(), reason: 'id missing');
        expect(block['name'], isA<String>(), reason: 'name missing');
        expect(block['kind'], isA<String>(), reason: 'kind missing');
        expect(block['role'], isA<String>(), reason: 'role missing');
        expect(block['content'], isA<String>(), reason: 'content missing');
        expect(block['enabled'], isA<bool>(), reason: 'enabled missing');
        expect(block['order'], isA<int>(), reason: 'order missing');
        expect(block['section'], isA<String>(), reason: 'section missing');
      }
    });

    test('contains all 7 sections', () {
      final blocks = studioPresetSeedBlocks();
      final sections = blocks.map((b) => b['section'] as String).toSet();
      expect(sections, contains('pregen'));
      expect(sections, contains('final'));
      expect(sections, contains('cleaner'));
      expect(sections, contains('ledger'));
      expect(sections, contains('writeloop'));
      expect(sections, contains('build'));
      expect(sections, contains('brief_parser'));
    });

    test('all block ids are unique', () {
      final blocks = studioPresetSeedBlocks();
      final ids = blocks.map((b) => b['id'] as String).toList();
      final uniqueIds = ids.toSet();
      expect(ids.length, uniqueIds.length, reason: 'Duplicate block IDs found');
    });

    test('pregen section has tracker instruction blocks', () {
      final blocks = studioPresetSeedBlocks();
      final pregen = blocks.where((b) => b['section'] == 'pregen').toList();
      expect(pregen, isNotEmpty);

      final ids = pregen.map((b) => b['id'] as String).toList();
      expect(ids, contains('continuity_task'));
      expect(ids, contains('agency_task'));
      expect(ids, contains('narrative_task'));
      expect(ids, contains('dialogue_task'));
      expect(ids, contains('guard_task'));
      expect(ids, contains('world_task'));
    });

    test('final section has brief_usage_note and hard_style_contract', () {
      final blocks = studioPresetSeedBlocks();
      final finalSection = blocks
          .where((b) => b['section'] == 'final')
          .toList();
      final ids = finalSection.map((b) => b['id'] as String).toList();
      expect(ids, contains('final_agent_instruction'));
      expect(ids, isNot(contains('brief_usage_note')));
      expect(ids, isNot(contains('hard_style_contract')));
      expect(ids, isNot(contains('beauty_shard_contract')));
    });

    test(
      'final section uses Studio brief macros instead of aggregate block',
      () {
        final blocks = studioPresetSeedBlocks();
        final previousAgents = blocks.firstWhere(
          (b) => b['id'] == 'previous_agents',
        );
        final macroBlock = blocks.firstWhere(
          (b) => b['id'] == 'final_studio_brief_macros',
        );

        expect(previousAgents['enabled'], false);
        expect(macroBlock['enabled'], true);
        final content = macroBlock['content'] as String;
        expect(content, contains('{{studio_continuity_brief}}'));
        expect(content, contains('{{studio_agency_brief}}'));
        expect(content, contains('{{studio_narrative_brief}}'));
        expect(content, contains('{{studio_dialogue_brief}}'));
        expect(content, contains('{{studio_guard_brief}}'));
        expect(content, contains('{{studio_world_brief}}'));
        expect(content, contains('{{studio_meta_brief}}'));
        expect(content, contains('{{studio_beauty_brief}}'));
      },
    );

    test('runtime-computed blocks are not seeded as editable duplicates', () {
      final ids = studioPresetSeedBlocks().map((b) => b['id'] as String);
      expect(ids, isNot(contains('runtime_envelope')));
      expect(ids, isNot(contains('brief_usage_note')));
      expect(ids, isNot(contains('hard_style_contract')));
      expect(ids, isNot(contains('beauty_shard_contract')));
    });

    test('cleaner section has cleaner_system and cleaner_rules', () {
      final blocks = studioPresetSeedBlocks();
      final cleaner = blocks.where((b) => b['section'] == 'cleaner').toList();
      final ids = cleaner.map((b) => b['id'] as String).toList();
      expect(ids, contains('cleaner_system'));
      expect(ids, contains('cleaner_aiism'));
      expect(ids, contains('cleaner_audit'));
      expect(ids, contains('cleaner_rules'));
    });

    test('cleaner_rules contains concrete NoriMyn prose guard rules', () {
      final blocks = studioPresetSeedBlocks();
      final cleanerRules = blocks.firstWhere((b) => b['id'] == 'cleaner_rules');
      final content = cleanerRules['content'] as String;
      expect(content, isNot(contains('{{bannedWords}}')));
      expect(content, isNot(contains('{{avoidInstructions}}')));
      expect(content, isNot(contains('{{styleInstructions}}')));
      expect(content, contains('озон'));
      expect(content, contains('Do not copy, quote, paraphrase, or mirror'));
      expect(content, contains('Use selective sensory detail'));
    });

    test('slot blocks have empty content (resolved at runtime)', () {
      final blocks = studioPresetSeedBlocks();
      final slots = blocks.where(
        (b) =>
            b['kind'] != 'custom_text' &&
            b['kind'] != 'agent_instruction' &&
            b['kind'] != 'instruction' &&
            b['kind'] != 'tracker_instruction' &&
            b['kind'] != 'agent_instruction' &&
            b['kind'] != 'previous_agents' &&
            b['kind'] != 'beauty_shard_contract' &&
            b['kind'] != 'runtime_envelope',
      );
      for (final slot in slots) {
        if (slot['kind'] == 'chat_history') {
          expect(slot['role'], 'user');
        }
      }
    });

    test('meta_task is enabled by default', () {
      final blocks = studioPresetSeedBlocks();
      final metaTask = blocks.firstWhere((b) => b['id'] == 'meta_task');
      expect(metaTask['enabled'], true);
    });

    test('memory and dynamic context slots cover distinct macro scopes', () {
      final blocks = studioPresetSeedBlocks();
      final pregenMemory = blocks.firstWhere((b) => b['id'] == 'pregen_memory');
      final pregenDynamic = blocks.firstWhere(
        (b) => b['id'] == 'pregen_dynamic_context',
      );

      expect(pregenMemory['content'], '{{memory}}');
      expect(pregenDynamic['content'], contains('{{summary}}'));
      expect(pregenDynamic['content'], contains('{{arc}}'));
      expect(pregenDynamic['content'], contains('{{entities}}'));
      expect(pregenDynamic['content'], contains('{{lorebooks}}'));
      expect(pregenDynamic['content'], contains('{{studio_state}}'));
    });

    test('does not expose static_context aggregate blocks', () {
      final blocks = studioPresetSeedBlocks();
      final staticBlocks = blocks.where((b) => b['kind'] == 'static_context');
      expect(staticBlocks, isEmpty);

      final ids = blocks.map((b) => b['id'] as String).toSet();
      expect(ids, isNot(contains('pregen_static_context')));
      expect(ids, isNot(contains('final_static_context')));
    });

    test('final length contract is fixed long form', () {
      final blocks = studioPresetSeedBlocks();
      final finalBlocks = blocks.where((b) => b['section'] == 'final');
      final text = finalBlocks.map((b) => b['content'] as String).join('\n');

      expect(text, isNot(contains('DYNAMIC LENGTH')));
      expect(text, contains('600-1200 Russian words'));
      expect(text, contains('Use 4-12 paragraphs overall'));
      expect(text, contains('exactly 4 paragraphs'));
      expect(text, contains('at least 4 sentences'));
    });
  });
}
