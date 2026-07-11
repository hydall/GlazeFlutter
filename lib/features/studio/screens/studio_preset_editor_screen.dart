import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/studio_seed_blocks.dart';
import '../../../core/models/studio_config.dart';
import '../../../core/state/db_provider.dart';
import '../widgets/studio_block_editor_dialog.dart';

/// Screen for editing a [StudioPreset] — its blocks grouped by section.
///
/// Shows all blocks in a section-tabbed view. Each block row shows title,
/// kind, role, order, enabled toggle. Tap to edit; long-press to delete.
/// Add new blocks via FAB. Changes are persisted to DB on every edit.
class StudioPresetEditorScreen extends ConsumerStatefulWidget {
  final String presetId;

  const StudioPresetEditorScreen({
    super.key,
    required this.presetId,
  });

  @override
  ConsumerState<StudioPresetEditorScreen> createState() =>
      _StudioPresetEditorScreenState();
}

class _StudioPresetEditorScreenState
    extends ConsumerState<StudioPresetEditorScreen> {
  StudioPreset? _preset;
  bool _loading = true;
  String _activeSection = 'pregen';

  static const _sections = [
    'pregen',
    'final',
    'cleaner',
    'ledger',
    'writeloop',
    'build',
    'brief_parser',
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
    return blocks
        .where((b) => b.section == _activeSection)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_preset?.name.isNotEmpty == true
            ? _preset!.name
            : 'Studio Preset Editor'),
        leading: BackButton(
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.restore),
            tooltip: 'Reset to defaults',
            onPressed: _loading ? null : _resetToDefaults,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _preset == null
              ? const Center(child: Text('Preset not found'))
              : Column(
                  children: [
                    _buildSectionTabs(),
                    Expanded(
                      child: _sectionBlocks.isEmpty
                          ? const Center(
                              child: Text('No blocks in this section'),
                            )
                          : ListView.builder(
                              itemCount: _sectionBlocks.length,
                              itemBuilder: (context, index) =>
                                  _buildBlockTile(_sectionBlocks[index]),
                            ),
                    ),
                  ],
                ),
      floatingActionButton: _loading || _preset == null
          ? null
          : FloatingActionButton(
              onPressed: _addBlock,
              child: const Icon(Icons.add),
            ),
    );
  }

  Widget _buildSectionTabs() {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: _sections.map((section) {
          final isActive = section == _activeSection;
          final count = (_preset?.blocks ?? const <StudioPresetBlock>[])
              .where((b) => b.section == section)
              .length;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: FilterChip(
              label: Text('$section ($count)'),
              selected: isActive,
              onSelected: (_) => setState(() => _activeSection = section),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBlockTile(StudioPresetBlock block) {
    return ListTile(
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
      onLongPress: () => _deleteBlock(block),
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
    final updated = _preset!.copyWith(
      blocks: [..._preset!.blocks, result],
    );
    await _save(updated);
  }

  Future<void> _editBlock(StudioPresetBlock block) async {
    final result = await showDialog<StudioPresetBlock>(
      context: context,
      builder: (_) => StudioBlockEditorDialog(block: block),
    );
    if (result == null || _preset == null) return;
    final blocks = _preset!.blocks.map((b) {
      return b.id == result.id ? result : b;
    }).toList();
    await _save(_preset!.copyWith(blocks: blocks));
  }

  Future<void> _toggleBlock(StudioPresetBlock block, bool enabled) async {
    if (_preset == null) return;
    final blocks = _preset!.blocks.map((b) {
      return b.id == block.id ? b.copyWith(enabled: enabled) : b;
    }).toList();
    await _save(_preset!.copyWith(blocks: blocks));
  }

  Future<void> _deleteBlock(StudioPresetBlock block) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Block'),
        content: Text('Delete "${block.title.isNotEmpty ? block.title : block.id}"?'),
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
    final seedData = studioPresetSeedBlocksForPreset(_preset!.id);
    final seedBlocks = seedData
        .map((m) => StudioPresetBlock(
              id: m['id'] as String? ?? '',
              title: (m['name'] as String?) ?? (m['title'] as String?) ?? '',
              kind: (m['kind'] as String?) ?? 'custom_text',
              role: (m['role'] as String?) ?? 'system',
              content: (m['content'] as String?) ?? '',
              enabled: (m['enabled'] as bool?) ?? true,
              order: (m['order'] as int?) ?? 0,
              section: (m['section'] as String?) ?? 'pregen',
            ))
        .toList();
    await _save(_preset!.copyWith(
      blocks: seedBlocks,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    ));
  }
}
