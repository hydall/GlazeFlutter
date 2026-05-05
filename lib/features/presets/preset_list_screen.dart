import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/preset.dart';
import '../../core/state/db_provider.dart';
import '../../shared/theme/app_colors.dart';

final presetListProvider =
    AsyncNotifierProvider<PresetListNotifier, List<Preset>>(
        PresetListNotifier.new);

class PresetListNotifier extends AsyncNotifier<List<Preset>> {
  @override
  Future<List<Preset>> build() async {
    return ref.watch(presetRepoProvider).getAll();
  }

  Future<void> add(Preset preset) async {
    await ref.read(presetRepoProvider).put(preset);
    ref.invalidateSelf();
  }

  Future<void> remove(String id) async {
    await ref.read(presetRepoProvider).delete(id);
    ref.invalidateSelf();
  }
}

class PresetListScreen extends ConsumerWidget {
  const PresetListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presets = ref.watch(presetListProvider);

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go('/tools')),
        title: const Text('Presets'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const PresetEditorScreen(),
              ),
            ),
          ),
        ],
      ),
      body: presets.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) => list.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.tune, size: 64, color: AppColors.textSecondary),
                    const SizedBox(height: 16),
                    const Text('No presets yet'),
                    const SizedBox(height: 8),
                    FilledButton.tonal(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const PresetEditorScreen(),
                        ),
                      ),
                      child: const Text('Create Preset'),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                itemCount: list.length,
                itemBuilder: (_, i) => _PresetTile(preset: list[i]),
              ),
      ),
    );
  }
}

class _PresetTile extends ConsumerWidget {
  final Preset preset;
  const _PresetTile({required this.preset});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: const Icon(Icons.tune),
      title: Text(preset.name),
      subtitle: Text(
        '${preset.blocks.length} blocks · ${preset.regexes.length} regex',
        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'edit') {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PresetEditorScreen(preset: preset),
              ),
            );
          } else if (value == 'duplicate') {
            final dup = preset.copyWith(
              id: DateTime.now().millisecondsSinceEpoch.toRadixString(36),
              name: '${preset.name} (copy)',
            );
            ref.read(presetListProvider.notifier).add(dup);
          } else if (value == 'delete') {
            ref.read(presetListProvider.notifier).remove(preset.id);
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'edit', child: Text('Edit')),
          const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PresetEditorScreen(preset: preset),
        ),
      ),
    );
  }
}

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
      text: widget.preset?.reasoningStart ?? '');
  late final _reasoningEndCtrl = TextEditingController(
      text: widget.preset?.reasoningEnd ?? '');

  late final _tabController = TabController(length: 2, vsync: this);

  @override
  void initState() {
    super.initState();
    _blocks = List.from(widget.preset?.blocks ?? []);
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
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
        title: Text(widget.preset != null ? 'Edit Preset' : 'New Preset'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Save'),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: 'Blocks'), Tab(text: 'Regex')],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildBlocksTab(),
          _buildRegexTab(),
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
                        labelText: 'Reasoning Start Tag'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _reasoningEndCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Reasoning End Tag'),
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
                child: _BlockTile(
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
                  child: Text('No regex scripts',
                      style: TextStyle(color: AppColors.textSecondary)))
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
                    child: _RegexTile(
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
      _blocks.add(PresetBlock(
        id: DateTime.now().millisecondsSinceEpoch.toRadixString(36),
        name: 'Block ${_blocks.length + 1}',
        role: 'system',
        content: '',
      ));
    });
  }

  void _addRegex() {
    setState(() {
      _regexes.add(PresetRegex(
        id: DateTime.now().millisecondsSinceEpoch.toRadixString(36),
        name: 'Regex ${_regexes.length + 1}',
        regex: '',
      ));
    });
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    final preset = Preset(
      id: widget.preset?.id ??
          DateTime.now().millisecondsSinceEpoch.toRadixString(36),
      name: name,
      author: widget.preset?.author,
      blocks: _blocks,
      regexes: _regexes,
      reasoningEnabled: _reasoningEnabled,
      reasoningStart: _reasoningEnabled ? _reasoningStartCtrl.text : null,
      reasoningEnd: _reasoningEnabled ? _reasoningEndCtrl.text : null,
      createdAt: widget.preset?.createdAt ??
          DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );

    await ref.read(presetRepoProvider).put(preset);
    ref.invalidate(presetListProvider);
    if (mounted) Navigator.of(context).pop();
  }
}

class _BlockTile extends StatelessWidget {
  final PresetBlock block;
  final ValueChanged<PresetBlock> onChanged;

  const _BlockTile({required this.block, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Row(
        children: [
          Switch(
            value: block.enabled,
            onChanged: (v) => onChanged(block.copyWith(enabled: v)),
          ),
          Expanded(
            child: Text(block.name,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          _roleChip(),
        ],
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: block.role,
                      decoration: const InputDecoration(labelText: 'Role'),
                      items: const [
                        DropdownMenuItem(value: 'system', child: Text('System')),
                        DropdownMenuItem(value: 'user', child: Text('User')),
                        DropdownMenuItem(
                            value: 'assistant', child: Text('Assistant')),
                      ],
                      onChanged: (v) {
                        if (v != null) onChanged(block.copyWith(role: v));
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 100,
                    child: TextFormField(
                      initialValue: block.depth?.toString() ?? '',
                      decoration: const InputDecoration(labelText: 'Depth'),
                      keyboardType: TextInputType.number,
                      onChanged: (v) {
                        final d = int.tryParse(v);
                        onChanged(block.copyWith(depth: d));
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                initialValue: block.name,
                decoration: const InputDecoration(labelText: 'Block Name'),
                onChanged: (v) => onChanged(block.copyWith(name: v)),
              ),
              const SizedBox(height: 8),
              TextFormField(
                initialValue: block.content,
                decoration: const InputDecoration(labelText: 'Content'),
                maxLines: 4,
                minLines: 2,
                onChanged: (v) => onChanged(block.copyWith(content: v)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _roleChip() {
    final color = switch (block.role) {
      'system' => Colors.blue,
      'user' => Colors.green,
      'assistant' => Colors.orange,
      _ => Colors.grey,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(block.role,
          style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _RegexTile extends StatelessWidget {
  final PresetRegex regex;
  final ValueChanged<PresetRegex> onChanged;

  const _RegexTile({required this.regex, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Row(
        children: [
          Switch(
            value: !regex.disabled,
            onChanged: (v) => onChanged(regex.copyWith(disabled: !v)),
          ),
          Expanded(
            child: Text(regex.name,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            children: [
              TextFormField(
                initialValue: regex.name,
                decoration: const InputDecoration(labelText: 'Name'),
                onChanged: (v) => onChanged(regex.copyWith(name: v)),
              ),
              const SizedBox(height: 8),
              TextFormField(
                initialValue: regex.regex,
                decoration: const InputDecoration(labelText: 'Find (regex)'),
                onChanged: (v) => onChanged(regex.copyWith(regex: v)),
              ),
              const SizedBox(height: 8),
              TextFormField(
                initialValue: regex.replacement,
                decoration:
                    const InputDecoration(labelText: 'Replace with'),
                onChanged: (v) => onChanged(regex.copyWith(replacement: v)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
