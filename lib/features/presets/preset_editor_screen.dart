import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/preset.dart';
import '../../../core/services/preset_defaults.dart';
import '../../../core/state/db_provider.dart';
import '../../../shared/widgets/glaze_scaffold.dart';
import 'preset_list_provider.dart';
import 'preset_list_screen.dart';
import 'widgets/widgets.dart';

class PresetEditorScreen extends ConsumerStatefulWidget {
  final Preset? preset;
  const PresetEditorScreen({super.key, this.preset});

  @override
  ConsumerState<PresetEditorScreen> createState() => _PresetEditorScreenState();
}

class _PresetEditorScreenState extends ConsumerState<PresetEditorScreen>
    with SingleTickerProviderStateMixin {
  late final _nameCtrl = TextEditingController(text: widget.preset?.name ?? '');
  late List<PresetBlock> _blocks;
  late List<PresetRegex> _regexes;
  late bool _reasoningEnabled;
  late final _reasoningStartCtrl = TextEditingController(
    text: widget.preset?.reasoningStart ?? '',
  );
  late final _reasoningEndCtrl = TextEditingController(
    text: widget.preset?.reasoningEnd ?? '',
  );

  late final _tabController = TabController(length: 2, vsync: this);

  @override
  void initState() {
    super.initState();
    _blocks = List.from(widget.preset?.blocks ?? defaultPresetBlocks());
    _regexes = List.from(widget.preset?.regexes ?? []);
    _reasoningEnabled = widget.preset?.reasoningEnabled ?? false;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _reasoningStartCtrl.dispose();
    _reasoningEndCtrl.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GlazeScaffold(
      title: widget.preset != null ? 'Edit Preset' : 'New Preset',
      onBack: () => Navigator.of(context).pop(),
      actions: [
        TextButton(
          onPressed: _save,
          child: const Text('Save', style: TextStyle(color: Colors.white)),
        ),
      ],
      body: Column(
        children: [
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Blocks'),
              Tab(text: 'Regex'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildBlocksTab(), _buildRegexTab()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlocksTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: 'Preset Name'),
          ),
        ),
        SwitchListTile(
          title: const Text('Reasoning Support'),
          subtitle: const Text('Parse reasoning tags from model output'),
          value: _reasoningEnabled,
          onChanged: (v) => setState(() => _reasoningEnabled = v),
        ),
        if (_reasoningEnabled) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _reasoningStartCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Reasoning Start Tag',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _reasoningEndCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Reasoning End Tag',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        const Divider(),
        Expanded(
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            itemCount: _blocks.length,
            onReorder: (old, neu) {
              setState(() {
                final item = _blocks.removeAt(old);
                _blocks.insert(neu > old ? neu - 1 : neu, item);
              });
            },
            itemBuilder: (_, i) => Dismissible(
              key: ValueKey(_blocks[i].id),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                color: Colors.red,
                child: const Icon(Icons.delete, color: Colors.white),
              ),
              onDismissed: (_) => setState(() => _blocks.removeAt(i)),
              child: ReorderableDragStartListener(
                index: i,
                child: BlockTile(
                  block: _blocks[i],
                  onChanged: (b) => setState(() => _blocks[i] = b),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: OutlinedButton.icon(
            onPressed: _addBlock,
            icon: const Icon(Icons.add),
            label: const Text('Add Block'),
          ),
        ),
      ],
    );
  }

  Widget _buildRegexTab() {
    return Column(
      children: [
        Expanded(
          child: _regexes.isEmpty
              ? Center(
                  child: Text(
                    'No regex scripts',
                    style: TextStyle(color: Theme.of(context).hintColor),
                  ),
                )
              : ListView.builder(
                  itemCount: _regexes.length,
                  itemBuilder: (_, i) => Dismissible(
                    key: ValueKey(_regexes[i].id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      color: Colors.red,
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    onDismissed: (_) => setState(() => _regexes.removeAt(i)),
                    child: RegexTile(
                      regex: _regexes[i],
                      onChanged: (r) => setState(() => _regexes[i] = r),
                    ),
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: OutlinedButton.icon(
            onPressed: _addRegex,
            icon: const Icon(Icons.add),
            label: const Text('Add Regex'),
          ),
        ),
      ],
    );
  }

  void _addBlock() {
    setState(() {
      _blocks.add(
        PresetBlock(
          id: DateTime.now().millisecondsSinceEpoch.toRadixString(36),
          name: 'Block ${_blocks.length + 1}',
          role: 'system',
          content: '',
        ),
      );
    });
  }

  void _addRegex() {
    setState(() {
      _regexes.add(
        PresetRegex(
          id: DateTime.now().millisecondsSinceEpoch.toRadixString(36),
          name: 'Regex ${_regexes.length + 1}',
          regex: '',
        ),
      );
    });
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    final preset = Preset(
      id:
          widget.preset?.id ??
          DateTime.now().millisecondsSinceEpoch.toRadixString(36),
      name: name,
      author: widget.preset?.author,
      blocks: _blocks,
      regexes: _regexes,
      reasoningEnabled: _reasoningEnabled,
      reasoningStart: _reasoningEnabled ? _reasoningStartCtrl.text : null,
      reasoningEnd: _reasoningEnabled ? _reasoningEndCtrl.text : null,
      createdAt:
          widget.preset?.createdAt ??
          DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );

    await ref.read(presetRepoProvider).put(preset);
    ref.invalidate(presetListProvider);
    if (mounted) Navigator.of(context).pop();
  }
}
