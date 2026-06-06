import 'package:flutter/material.dart';

import '../../../models/block_config.dart';
import 'section_label.dart';

class BlockTriggerPicker extends StatelessWidget {
  const BlockTriggerPicker({
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final BlockTrigger selected;
  final ValueChanged<BlockTrigger> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SectionLabel('Триггер'),
        SegmentedButton<BlockTrigger>(
          segments: const [
            ButtonSegment(
              value: BlockTrigger.afterUser,
              label: Text('После user'),
            ),
            ButtonSegment(
              value: BlockTrigger.afterAssistant,
              label: Text('После assistant'),
            ),
            ButtonSegment(
              value: BlockTrigger.periodic,
              label: Text('Периодический'),
            ),
          ],
          selected: {selected},
          onSelectionChanged: (s) => onChanged(s.first),
          style: ButtonStyle(visualDensity: VisualDensity.compact),
        ),
      ],
    );
  }
}
