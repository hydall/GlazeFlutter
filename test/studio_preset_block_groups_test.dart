import 'package:flutter_test/flutter_test.dart';
import 'package:glaze_flutter/core/models/studio_config.dart';
import 'package:glaze_flutter/core/models/studio_preset_block_groups.dart';

void main() {
  const blocks = [
    StudioPresetBlock(id: 'intro', title: 'Core Directive', order: 1),
    StudioPresetBlock(id: 'pov_header', title: '━🧍 Point-of-View', order: 2),
    StudioPresetBlock(
      id: 'third_person',
      title: 'Third Person Narrator',
      enabled: true,
      order: 3,
    ),
    StudioPresetBlock(
      id: 'second_person',
      title: 'Second Person',
      enabled: false,
      order: 4,
    ),
    StudioPresetBlock(
      id: 'past_tense',
      title: 'Past-Tense Modifier',
      enabled: true,
      order: 5,
    ),
    StudioPresetBlock(
      id: 'present_tense',
      title: 'Present-Tense Modifier',
      enabled: false,
      order: 6,
    ),
    StudioPresetBlock(
      id: 'style_header',
      title: '━✏️ Narrative Styles',
      order: 7,
    ),
    StudioPresetBlock(
      id: 'roleplay',
      title: 'Roleplay',
      enabled: false,
      order: 8,
    ),
    StudioPresetBlock(
      id: 'ao3',
      title: 'AO3-Style Fan Fiction',
      enabled: true,
      order: 9,
    ),
  ];

  test('groups blocks under authored Loom headers in logical order', () {
    final normalized = normalizeStudioGroupBoundaries([
      ...blocks.take(1),
      blocks[1].copyWith(content: '<loompov>\nPOV'),
      ...blocks.skip(2).take(4),
      blocks[6].copyWith(content: '</loompov>\n<loomstyle>\nStyles'),
      ...blocks.skip(7),
      const StudioPresetBlock(
        id: 'style_close',
        title: 'End Narrative Styles',
        content: '</loomstyle>',
        order: 10,
      ),
    ]);
    final items = groupStudioPresetBlocks(normalized);

    expect(items, hasLength(4));
    expect(items[0].standalone?.id, 'intro');
    expect(items[1].header?.id, 'pov_header');
    expect(items[1].openingBoundary?.content, '<loompov>');
    expect(items[1].closingBoundary?.content, '</loompov>');
    expect(items[1].children.map((b) => b.id), [
      'third_person',
      'second_person',
    ]);
    expect(items[1].exclusive, isTrue);
    expect(items[2].header?.title, 'Tense');
    expect(items[2].openingBoundary, isNull);
    expect(items[2].closingBoundary, isNull);
    expect(items[2].children.map((b) => b.id), ['past_tense', 'present_tense']);
    expect(items[2].exclusive, isTrue);
    expect(items[3].header?.id, 'style_header');
    expect(items[3].openingBoundary?.content, '<loomstyle>');
    expect(items[3].closingBoundary?.content, '</loomstyle>');
    expect(items[3].exclusive, isTrue);
  });

  test('selecting an exclusive option disables its siblings', () {
    final updated = selectExclusiveStudioBlock(
      blocks,
      groupStudioPresetBlocks(blocks)[1],
      'second_person',
    );

    expect(updated.firstWhere((b) => b.id == 'third_person').enabled, isFalse);
    expect(updated.firstWhere((b) => b.id == 'second_person').enabled, isTrue);
    expect(updated.firstWhere((b) => b.id == 'ao3').enabled, isTrue);
  });

  test('editing an enabled exclusive option disables its siblings', () {
    final updated = updateStudioPresetBlockRespectingGroups(
      blocks,
      blocks
          .firstWhere((block) => block.id == 'second_person')
          .copyWith(enabled: true, content: 'Edited'),
    );

    expect(updated.firstWhere((b) => b.id == 'third_person').enabled, isFalse);
    expect(updated.firstWhere((b) => b.id == 'second_person').enabled, isTrue);
    expect(
      updated.firstWhere((b) => b.id == 'second_person').content,
      'Edited',
    );
  });

  test('repairs a mismatched legacy close from the owned opening tag', () {
    const legacy = [
      StudioPresetBlock(
        id: 'plot_header',
        title: '━🚧 Plot Progression',
        content: '<loomplot>\nPlot instructions',
        order: 1,
      ),
      StudioPresetBlock(id: 'plot_variant', title: 'Progress', order: 2),
      StudioPresetBlock(
        id: 'length_header',
        title: '━📐 Response Length Controls',
        content: '</loomplotprog>\n<loomlength>\nLength instructions',
        order: 3,
      ),
      StudioPresetBlock(id: 'length_close', content: '</loomlength>', order: 4),
    ];

    final normalized = normalizeStudioGroupBoundaries(legacy);

    expect(
      normalized.firstWhere((b) => b.id == 'plot_header_group_close').content,
      '</loomplot>',
    );
  });

  test('replaces a mismatched final standalone close', () {
    const legacy = [
      StudioPresetBlock(
        id: 'lore_header',
        title: '━ Lore',
        content: '<loomlore>\nLore instructions',
        order: 0,
      ),
      StudioPresetBlock(id: 'lore_option', content: 'Option', order: 1),
      StudioPresetBlock(
        id: 'legacy_close',
        role: 'system',
        content: '</loomwrong>',
        order: 2,
      ),
    ];

    final normalized = normalizeStudioGroupBoundaries(legacy);

    expect(normalized.any((block) => block.content == '</loomwrong>'), isFalse);
    expect(
      normalized.where((block) => block.content == '</loomlore>'),
      hasLength(1),
    );
    expect(normalized.last.id, 'lore_header_group_close');
  });

  test('normalizes legacy cross-group tags into owned boundary blocks', () {
    const legacy = [
      StudioPresetBlock(
        id: 'pov_header',
        title: '━🧍 Point-of-View',
        content: '</lumiapers>\n\n<loompov>\nPOV instructions',
        order: 1,
      ),
      StudioPresetBlock(id: 'third_person', title: 'Third Person', order: 2),
      StudioPresetBlock(
        id: 'human_header',
        title: '━🧑 User Instructions',
        content: '</loompov>\n\n<loomhuman>\nHuman instructions',
        order: 3,
      ),
      StudioPresetBlock(
        id: 'human_close',
        title: 'End User Instructions',
        content: '</loomhuman>',
        order: 4,
      ),
    ];

    final normalized = normalizeStudioGroupBoundaries(legacy);

    expect(normalized.map((block) => block.id), [
      'pov_header_prefix_close',
      'pov_header_group_open',
      'pov_header',
      'third_person',
      'pov_header_group_close',
      'human_header_group_open',
      'human_header',
      'human_header_group_close',
    ]);
    expect(normalized[0].kind, 'group_close');
    expect(normalized[0].content, '</lumiapers>');
    expect(normalized[1].kind, 'group_open');
    expect(normalized[1].content, '<loompov>');
    expect(normalized[2].content, 'POV instructions');
    expect(normalized[4].kind, 'group_close');
    expect(normalized[4].content, '</loompov>');
    expect(normalized[5].content, '<loomhuman>');
    expect(normalized[6].content, 'Human instructions');
    expect(normalized.last.kind, 'group_close');
  });
}
