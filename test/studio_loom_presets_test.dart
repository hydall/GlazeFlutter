import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glaze_flutter/core/models/studio_config.dart';

void main() {
  StudioPreset load(String mode) {
    final file = File('presets/studio/loom_adapt_v1_$mode.json');
    return StudioPreset.fromJson(
      jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
    );
  }

  test('distributed Loom presets expose their controller structure', () {
    final direct = load('direct');
    final assisted = load('assisted');
    final legacy = load('legacy');

    expect(direct.executionMode, StudioExecutionMode.direct);
    expect(assisted.executionMode, StudioExecutionMode.assisted);
    expect(legacy.executionMode, StudioExecutionMode.legacy);

    Iterable<String> tasks(StudioPreset preset) => preset.blocks
        .where((block) => block.kind == 'tracker_instruction')
        .map((block) => block.id);

    expect(tasks(direct), isEmpty);
    expect(tasks(assisted), [
      'continuity_task_universal',
      'narrative_task_universal',
      'beauty_task',
    ]);
    expect(tasks(legacy), [
      'continuity_task_universal',
      'agency_task',
      'narrative_task_universal',
      'dialogue_task',
      'guard_task',
      'world_task',
      'meta_task',
      'beauty_task',
    ]);
  });

  test('Beauty is cleaner-owned in direct and handed off in other modes', () {
    for (final mode in ['direct', 'assisted', 'legacy']) {
      final preset = load(mode);
      final cleaner = preset.blocks.singleWhere(
        (block) => block.id == 'cleaner_beauty',
      );
      expect(cleaner.enabled, isTrue, reason: mode);
      expect(cleaner.content, contains('{{beautyBrief}}'), reason: mode);
      expect(
        preset.blocks.every(
          (block) => !block.content.contains('{{studio_beauty_brief}}'),
        ),
        isTrue,
        reason: mode,
      );
      expect(preset.agentEnabled['beauty'], mode != 'direct', reason: mode);
    }
  });

  test('every distributed block has an editable title and stable order', () {
    for (final mode in ['direct', 'assisted', 'legacy']) {
      final preset = load(mode);
      for (var i = 0; i < preset.blocks.length; i++) {
        expect(preset.blocks[i].title, isNotEmpty, reason: '$mode block $i');
        expect(preset.blocks[i].order, i, reason: '$mode block $i');
      }
    }
  });
}
