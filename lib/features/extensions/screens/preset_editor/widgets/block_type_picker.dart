import 'package:flutter/material.dart';

import '../../../models/block_config.dart';
import 'section_label.dart';

class BlockTypePicker extends StatelessWidget {
  const BlockTypePicker({
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final BlockType selected;
  final ValueChanged<BlockType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SectionLabel('Тип'),
        SegmentedButton<BlockType>(
          segments: const [
            ButtonSegment(
              value: BlockType.infoblock,
              label: Text('Инфоблок'),
              icon: Icon(Icons.notes),
            ),
            ButtonSegment(
              value: BlockType.imageGen,
              label: Text('Картинка'),
              icon: Icon(Icons.image_outlined),
            ),
            ButtonSegment(
              value: BlockType.jsRunner,
              label: Text('JS'),
              icon: Icon(Icons.code),
            ),
            ButtonSegment(
              value: BlockType.interactive,
              label: Text('Панель'),
              icon: Icon(Icons.dashboard_customize_outlined),
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
