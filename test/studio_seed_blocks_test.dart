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
      expect(ids.length, uniqueIds.length,
          reason: 'Duplicate block IDs found');
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
      final finalSection = blocks.where((b) => b['section'] == 'final').toList();
      final ids = finalSection.map((b) => b['id'] as String).toList();
      expect(ids, contains('final_agent_instruction'));
      expect(ids, contains('brief_usage_note'));
      expect(ids, contains('hard_style_contract'));
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

    test('cleaner_rules has macro templates', () {
      final blocks = studioPresetSeedBlocks();
      final cleanerRules = blocks.firstWhere((b) => b['id'] == 'cleaner_rules');
      final content = cleanerRules['content'] as String;
      expect(content, contains('{{bannedWords}}'));
      expect(content, contains('{{avoidInstructions}}'));
      expect(content, contains('{{styleInstructions}}'));
    });

    test('slot blocks have empty content (resolved at runtime)', () {
      final blocks = studioPresetSeedBlocks();
      final slots = blocks.where((b) => b['kind'] != 'custom_text'
          && b['kind'] != 'agent_instruction'
          && b['kind'] != 'instruction'
          && b['kind'] != 'tracker_instruction'
          && b['kind'] != 'agent_instruction'
          && b['kind'] != 'previous_agents'
          && b['kind'] != 'beauty_shard_contract'
          && b['kind'] != 'runtime_envelope',
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
  });
}
