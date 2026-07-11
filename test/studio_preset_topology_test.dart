import 'package:flutter_test/flutter_test.dart';
import 'package:glaze_flutter/core/models/studio_config.dart';
import 'package:glaze_flutter/core/models/studio_preset_topology.dart';

void main() {
  const source = StudioPreset(
    id: 'source',
    name: 'Source',
    blocks: [
      StudioPresetBlock(
        id: 'continuity_task_universal',
        kind: 'tracker_instruction',
      ),
      StudioPresetBlock(id: 'agency_task', kind: 'tracker_instruction'),
      StudioPresetBlock(
        id: 'narrative_task_universal',
        kind: 'tracker_instruction',
      ),
      StudioPresetBlock(id: 'beauty_task', kind: 'tracker_instruction'),
      StudioPresetBlock(id: 'beauty_extractor', section: 'build'),
      StudioPresetBlock(id: 'cleaner_beauty', section: 'cleaner'),
      StudioPresetBlock(id: 'final_response_shape_contract', section: 'final'),
    ],
  );

  test('direct preset has no pregen tasks and keeps cleaner beauty', () {
    final preset = prepareStudioPresetForMode(
      source,
      id: 'direct',
      name: 'Direct',
      mode: StudioExecutionMode.direct,
      updatedAt: 1,
    );

    expect(
      preset.blocks.where((b) => b.kind == 'tracker_instruction'),
      isEmpty,
    );
    expect(
      preset.blocks.firstWhere((b) => b.id == 'beauty_extractor').enabled,
      isFalse,
    );
    expect(
      preset.blocks.firstWhere((b) => b.id == 'cleaner_beauty').enabled,
      isTrue,
    );
    expect(
      preset.blocks
          .firstWhere((b) => b.id == 'final_response_shape_contract')
          .content,
      contains('<loom_direct_contract>'),
    );
    expect(preset.agentEnabled['final'], isTrue);
    expect(preset.agentEnabled['continuity'], isFalse);
    expect(preset.agentEnabled['beauty'], isFalse);
  });

  test('assisted preset has only continuity and narrative tasks', () {
    final preset = prepareStudioPresetForMode(
      source,
      id: 'assisted',
      name: 'Assisted',
      mode: StudioExecutionMode.assisted,
      updatedAt: 1,
    );

    expect(
      preset.blocks
          .where((b) => b.kind == 'tracker_instruction')
          .map((b) => b.id),
      ['continuity_task_universal', 'narrative_task_universal'],
    );
    expect(preset.agentEnabled['continuity'], isTrue);
    expect(preset.agentEnabled['narrative'], isTrue);
    expect(preset.agentEnabled['meta'], isFalse);
    expect(preset.agentEnabled['beauty'], isFalse);
    expect(
      preset.blocks
          .firstWhere((b) => b.id == 'continuity_task_universal')
          .content,
      contains('<continuity_context>'),
    );
    expect(
      preset.blocks
          .firstWhere((b) => b.id == 'narrative_task_universal')
          .content,
      contains('<scene_direction>'),
    );
  });
}
