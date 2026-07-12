import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/studio_seed_blocks.dart';
import '../../../core/models/studio_config.dart';
import '../../../core/models/studio_preset_block_groups.dart';
import '../../../core/state/db_provider.dart';
import '../../studio/widgets/studio_block_editor_dialog.dart';
import '../../studio/widgets/studio_preset_group_tile.dart';

/// Studio Preset Editor as a bottom sheet — replaces the full-screen
/// [StudioPresetEditorScreen]. Shows preset blocks grouped by section.
///
/// Only the 4 user-facing sections are shown: pregen (Trackers), final
/// (Final Agent), cleaner (Post-Processing), ledger (Canon Ledger).
/// Technical sections (build, brief_parser) are hidden.
class StudioPresetEditorSheet extends ConsumerStatefulWidget {
  final String presetId;

  const StudioPresetEditorSheet({super.key, required this.presetId});

  @override
  ConsumerState<StudioPresetEditorSheet> createState() =>
      _StudioPresetEditorSheetState();
}

class _StudioPresetEditorSheetState
    extends ConsumerState<StudioPresetEditorSheet> {
  StudioPreset? _preset;
  bool _loading = true;
  String _activeSection = 'pregen';

  static const _userSections = [
    ('pregen', 'Trackers'),
    ('final', 'Final Agent'),
    ('cleaner', 'Post-Processing'),
    ('ledger', 'Canon Ledger'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(studioPresetRepoProvider);
    final preset = await repo.getById(widget.presetId);
    if (!mounted) return;
    setState(() {
      _preset = preset;
      _loading = false;
    });
  }

  Future<void> _save(StudioPreset preset) async {
    final repo = ref.read(studioPresetRepoProvider);
    await repo.upsert(preset);
    setState(() => _preset = preset);
  }

  List<StudioPresetBlock> get _sectionBlocks {
    final blocks = _preset?.blocks ?? const <StudioPresetBlock>[];
    return blocks.where((b) => b.section == _activeSection).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
  }

  List<StudioPresetBlockGroup> get _sectionItems =>
      groupStudioPresetBlocks(_sectionBlocks);

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_preset == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('Preset not found')),
      );
    }
    final sheetHeight = MediaQuery.sizeOf(context).height * 0.72;
    return SizedBox(
      height: sheetHeight,
      child: Column(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionTabs(),
          const Divider(),
          Expanded(
            child: _sectionBlocks.isEmpty
                ? const Center(child: Text('No blocks in this section'))
                : ListView.builder(
                    primary: false,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: _sectionItems.length,
                    itemBuilder: (context, index) {
                      final item = _sectionItems[index];
                      if (item.header != null) {
                        return StudioPresetGroupTile(
                          group: item,
                          onSelectExclusive: (id) =>
                              _selectExclusiveBlock(item, id),
                          onToggle: _toggleBlock,
                          onEdit: _editBlock,
                          onDelete: _deleteBlock,
                        );
                      }
                      final block = item.standalone!;
                      return Dismissible(
                        key: ValueKey(block.id),
                        direction: DismissDirection.horizontal,
                        background: Container(
                          color: Theme.of(context).colorScheme.errorContainer,
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.only(left: 16),
                          child: Icon(
                            Icons.delete,
                            color: Theme.of(context).colorScheme.onError,
                          ),
                        ),
                        secondaryBackground: Container(
                          color: Theme.of(context).colorScheme.errorContainer,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 16),
                          child: Icon(
                            Icons.delete,
                            color: Theme.of(context).colorScheme.onError,
                          ),
                        ),
                        confirmDismiss: (_) async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('Delete Block'),
                              content: Text(
                                'Delete "${block.title.isNotEmpty ? block.title : block.id}"?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(false),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(true),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                          );
                          return ok == true;
                        },
                        onDismissed: (_) => _deleteBlock(block),
                        child: _buildBlockTile(block),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _addBlock,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Block'),
                ),
                TextButton.icon(
                  onPressed: _resetToDefaults,
                  icon: const Icon(Icons.restore, size: 18),
                  label: const Text('Reset'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSectionTabs() {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: _userSections.map((section) {
          final isActive = section.$1 == _activeSection;
          final count = (_preset?.blocks ?? const <StudioPresetBlock>[])
              .where((b) => b.section == section.$1)
              .length;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: FilterChip(
              label: Text('${section.$2} ($count)'),
              selected: isActive,
              onSelected: (_) => setState(() => _activeSection = section.$1),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBlockTile(StudioPresetBlock block) {
    return ListTile(
      key: ValueKey('tile_${block.id}'),
      title: Text(
        block.title.isNotEmpty ? block.title : block.id,
        style: block.enabled
            ? null
            : const TextStyle(decoration: TextDecoration.lineThrough),
      ),
      subtitle: Text(
        '${block.kind} · ${block.role} · order=${block.order}',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Switch(
        value: block.enabled,
        onChanged: (v) => _toggleBlock(block, v),
      ),
      onTap: () => _editBlock(block),
    );
  }

  Future<void> _addBlock() async {
    final newBlock = StudioPresetBlock(
      id: 'block_${DateTime.now().millisecondsSinceEpoch}',
      title: 'New Block',
      section: _activeSection,
      order: _sectionBlocks.length,
    );
    final result = await showDialog<StudioPresetBlock>(
      context: context,
      builder: (_) => StudioBlockEditorDialog(block: newBlock, isNew: true),
    );
    if (result == null || _preset == null) return;
    final updated = _preset!.copyWith(blocks: [..._preset!.blocks, result]);
    await _save(updated);
  }

  Future<void> _editBlock(StudioPresetBlock block) async {
    final result = await showDialog<StudioPresetBlock>(
      context: context,
      builder: (_) => StudioBlockEditorDialog(block: block),
    );
    if (result == null || _preset == null) return;
    final blocks = updateStudioPresetBlockRespectingGroups(
      _preset!.blocks,
      result,
    );
    await _save(_preset!.copyWith(blocks: blocks));
  }

  Future<void> _toggleBlock(StudioPresetBlock block, bool enabled) async {
    if (_preset == null) return;
    final blocks = updateStudioPresetBlockRespectingGroups(
      _preset!.blocks,
      block.copyWith(enabled: enabled),
    );
    await _save(_preset!.copyWith(blocks: blocks));
  }

  Future<void> _selectExclusiveBlock(
    StudioPresetBlockGroup group,
    String selectedId,
  ) async {
    if (_preset == null) return;
    await _save(
      _preset!.copyWith(
        blocks: selectExclusiveStudioBlock(_preset!.blocks, group, selectedId),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> _deleteBlock(StudioPresetBlock block) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Block'),
        content: Text(
          'Delete "${block.title.isNotEmpty ? block.title : block.id}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || _preset == null) return;
    final blocks = _preset!.blocks.where((b) => b.id != block.id).toList();
    await _save(_preset!.copyWith(blocks: blocks));
  }

  Future<void> _resetToDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reset to Defaults'),
        content: const Text(
          'This will replace ALL blocks with the default seed data. '
          'Your customizations will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true || _preset == null) return;
    final seedData = studioPresetSeedBlocks();
    final seedBlocks = seedData
        .map(
          (m) => StudioPresetBlock(
            id: m['id'] as String? ?? '',
            title: (m['name'] as String?) ?? (m['title'] as String?) ?? '',
            kind: (m['kind'] as String?) ?? 'custom_text',
            role: (m['role'] as String?) ?? 'system',
            content: (m['content'] as String?) ?? '',
            enabled: (m['enabled'] as bool?) ?? true,
            order: (m['order'] as int?) ?? 0,
            section: (m['section'] as String?) ?? 'pregen',
          ),
        )
        .toList();
    await _save(
      _preset!.copyWith(
        blocks: seedBlocks,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}
