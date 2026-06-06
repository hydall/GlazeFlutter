import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../shared/theme/app_colors.dart';
import '../../../../../shared/widgets/menu_group.dart';
import '../../../models/block_config.dart';
import '../../../models/extension_preset.dart';
import '../../../providers/extension_presets_provider.dart';
import '../block_edit_dialog.dart';

class BlocksSection extends ConsumerWidget {
  const BlocksSection({required this.preset, super.key});

  final ExtensionPreset preset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MenuGroup(
          header: 'Блоки',
          items: [
            if (preset.blocks.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text(
                  'Пока нет блоков',
                  style: TextStyle(
                    fontSize: 13,
                    color: context.cs.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorderItem: (oldIdx, newIdx) =>
                  _reorderBlock(ref, preset, oldIdx, newIdx),
              children: [
                for (int i = 0; i < preset.blocks.length; i++)
                  _BlockTile(
                    key: ValueKey(preset.blocks[i].id),
                    preset: preset,
                    block: preset.blocks[i],
                    index: i,
                  ),
              ],
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: OutlinedButton.icon(
            onPressed: () => _addBlock(context, ref, preset),
            icon: const Icon(Icons.add),
            label: const Text('Добавить блок'),
          ),
        ),
      ],
    );
  }

  void _reorderBlock(
    WidgetRef ref,
    ExtensionPreset preset,
    int oldIdx,
    int newIdx,
  ) {
    final blocks = List<BlockConfig>.from(preset.blocks);
    final item = blocks.removeAt(oldIdx);
    blocks.insert(newIdx, item);
    final reordered = [
      for (int i = 0; i < blocks.length; i++) blocks[i].copyWith(order: i),
    ];
    ref
        .read(extensionPresetsProvider.notifier)
        .update(preset.copyWith(blocks: reordered));
  }

  Future<void> _addBlock(
    BuildContext context,
    WidgetRef ref,
    ExtensionPreset preset,
  ) async {
    final id = 'block_${DateTime.now().millisecondsSinceEpoch}';
    final block = BlockConfig(
      id: id,
      name: 'Новый блок',
      type: BlockType.infoblock,
      enabled: true,
    );
    final updated = preset.copyWith(blocks: [...preset.blocks, block]);
    await ref.read(extensionPresetsProvider.notifier).update(updated);
    if (context.mounted) _editBlock(context, ref, updated, block);
  }
}

class _BlockTile extends ConsumerWidget {
  const _BlockTile({
    required this.preset,
    required this.block,
    required this.index,
    super.key,
  });

  final ExtensionPreset preset;
  final BlockConfig block;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Stack(
      children: [
        MenuScriptItem(
          name: block.name.isEmpty ? 'Без имени' : block.name,
          subtitle: blockSubtitle(block),
          enabled: block.enabled,
          onToggle: (v) => _toggleBlock(ref, preset, block, v),
          onTap: () => _editBlock(context, ref, preset, block),
          onMore: () => _showBlockActions(context, ref, preset, block),
        ),
        Positioned(
          right: 110,
          top: 0,
          bottom: 0,
          child: ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.drag_handle, size: 20, color: Colors.white24),
            ),
          ),
        ),
      ],
    );
  }

  void _toggleBlock(
    WidgetRef ref,
    ExtensionPreset preset,
    BlockConfig block,
    bool enabled,
  ) {
    final updated = preset.copyWith(
      blocks: [
        for (final b in preset.blocks)
          if (b.id == block.id) b.copyWith(enabled: enabled) else b,
      ],
    );
    ref.read(extensionPresetsProvider.notifier).update(updated);
  }

  void _showBlockActions(
    BuildContext context,
    WidgetRef ref,
    ExtensionPreset preset,
    BlockConfig block,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.cs.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Удалить блок'),
              onTap: () {
                Navigator.pop(ctx);
                _deleteBlock(ref, preset, block);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _deleteBlock(WidgetRef ref, ExtensionPreset preset, BlockConfig block) {
    final updated = preset.copyWith(
      blocks: preset.blocks.where((b) => b.id != block.id).toList(),
    );
    ref.read(extensionPresetsProvider.notifier).update(updated);
  }
}

String blockSubtitle(BlockConfig block) {
  final type = switch (block.type) {
    BlockType.infoblock => 'Инфоблок',
    BlockType.imageGen => 'Картинка',
    BlockType.jsRunner => 'JS',
    BlockType.interactive => 'Интерактивная панель',
  };
  final trigger = switch (block.trigger) {
    BlockTrigger.afterUser => 'После user',
    BlockTrigger.afterAssistant => 'После assistant',
    BlockTrigger.periodic => 'Периодический',
  };
  return '$type • $trigger';
}

void _editBlock(
  BuildContext context,
  WidgetRef ref,
  ExtensionPreset preset,
  BlockConfig block,
) {
  showDialog<void>(
    context: context,
    builder: (ctx) => BlockEditDialog(
      block: block,
      onSave: (updated) {
        final newPreset = preset.copyWith(
          blocks: [
            for (final b in preset.blocks)
              if (b.id == updated.id) updated else b,
          ],
        );
        ref.read(extensionPresetsProvider.notifier).update(newPreset);
      },
    ),
  );
}
