import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/memory_book.dart';
import '../../../core/state/db_provider.dart';
import '../../../shared/theme/app_colors.dart';

class MemoryBooksSheet extends ConsumerStatefulWidget {
  final String sessionId;

  const MemoryBooksSheet({super.key, required this.sessionId});

  @override
  ConsumerState<MemoryBooksSheet> createState() => _MemoryBooksSheetState();
}

class _MemoryBooksSheetState extends ConsumerState<MemoryBooksSheet> {
  MemoryBook? _book;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(memoryBookRepoProvider);
    final book = await repo.ensureForSession(widget.sessionId);
    if (mounted) setState(() { _book = book; _loading = false; });
  }

  Future<void> _save() async {
    if (_book == null) return;
    final repo = ref.read(memoryBookRepoProvider);
    await repo.put(_book!);
  }

  void _addEntry() async {
    final entry = await showDialog<MemoryEntry>(
      context: context,
      builder: (_) => _MemoryEntryDialog(sessionId: widget.sessionId),
    );
    if (entry != null && mounted) {
      setState(() {
        _book = _book!.copyWith(entries: [..._book!.entries, entry]);
      });
      await _save();
    }
  }

  void _editEntry(int index) async {
    final entry = await showDialog<MemoryEntry>(
      context: context,
      builder: (_) => _MemoryEntryDialog(
        sessionId: widget.sessionId,
        entry: _book!.entries[index],
      ),
    );
    if (entry != null && mounted) {
      final entries = [..._book!.entries];
      entries[index] = entry;
      setState(() { _book = _book!.copyWith(entries: entries); });
      await _save();
    }
  }

  void _deleteEntry(int index) async {
    final entries = [..._book!.entries]..removeAt(index);
    setState(() { _book = _book!.copyWith(entries: entries); });
    await _save();
  }

  void _toggleSettings() async {
    final settings = await showDialog<MemoryBookSettings>(
      context: context,
      builder: (_) => _MemorySettingsDialog(settings: _book!.settings),
    );
    if (settings != null && mounted) {
      setState(() { _book = _book!.copyWith(settings: settings); });
      await _save();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final settings = _book!.settings;
    final entries = _book!.entries;
    final activeEntries = entries.where((e) => e.status == 'active').toList();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                const Icon(Icons.auto_stories, color: AppColors.accent, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Memory Books', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                ),
                IconButton(
                  icon: const Icon(Icons.settings, size: 20, color: AppColors.textSecondary),
                  onPressed: _toggleSettings,
                ),
                IconButton(
                  icon: const Icon(Icons.add, size: 22, color: AppColors.accent),
                  onPressed: _addEntry,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _statusChip('Enabled', settings.enabled, Colors.green),
                const SizedBox(width: 6),
                _statusChip('${activeEntries.length} active', activeEntries.isNotEmpty, Colors.cyan),
                const SizedBox(width: 6),
                _statusChip(
                  settings.injectionTarget == 'summary_macro' ? '{{summary}}' : 'Summary Block',
                  true,
                  Colors.orange,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_stories, size: 48, color: AppColors.textSecondary.withValues(alpha: 0.3)),
                        const SizedBox(height: 12),
                        Text('No memory entries yet', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                        const SizedBox(height: 4),
                        Text('Tap + to create one', style: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.5), fontSize: 12)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: entries.length,
                    itemBuilder: (_, i) => _MemoryEntryTile(
                      entry: entries[i],
                      onEdit: () => _editEntry(i),
                      onDelete: () => _deleteEntry(i),
                      onToggle: () async {
                        final e = entries[i];
                        final newStatus = e.status == 'active' ? 'disabled' : 'active';
                        final updated = [...entries];
                        updated[i] = e.copyWith(status: newStatus);
                        setState(() { _book = _book!.copyWith(entries: updated); });
                        await _save();
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String label, bool active, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (active ? color : AppColors.textSecondary).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: active ? color : AppColors.textSecondary)),
    );
  }
}

class _MemoryEntryTile extends StatelessWidget {
  final MemoryEntry entry;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggle;

  const _MemoryEntryTile({required this.entry, required this.onEdit, required this.onDelete, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final isActive = entry.status == 'active';
    return Card(
      color: isActive ? Colors.white.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.02),
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: IconButton(
          icon: Icon(isActive ? Icons.check_circle : Icons.cancel, size: 20, color: isActive ? Colors.green : AppColors.textSecondary),
          onPressed: onToggle,
        ),
        title: Text(
          entry.title.isNotEmpty ? entry.title : 'Untitled Memory',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: isActive ? AppColors.textPrimary : AppColors.textSecondary),
        ),
        subtitle: Text(
          entry.content.length > 100 ? '${entry.content.substring(0, 100)}...' : entry.content,
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (entry.keys.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: Colors.cyan.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                child: Text('${entry.keys.length}', style: const TextStyle(fontSize: 10, color: Colors.cyan, fontWeight: FontWeight.w600)),
              ),
            IconButton(icon: const Icon(Icons.edit_outlined, size: 18), onPressed: onEdit),
            IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent), onPressed: onDelete),
          ],
        ),
      ),
    );
  }
}

class _MemoryEntryDialog extends StatefulWidget {
  final String sessionId;
  final MemoryEntry? entry;

  const _MemoryEntryDialog({required this.sessionId, this.entry});

  @override
  State<_MemoryEntryDialog> createState() => _MemoryEntryDialogState();
}

class _MemoryEntryDialogState extends State<_MemoryEntryDialog> {
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  late TextEditingController _keysController;
  bool _vectorSearch = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.entry?.title ?? '');
    _contentController = TextEditingController(text: widget.entry?.content ?? '');
    _keysController = TextEditingController(text: widget.entry?.keys.join(', ') ?? '');
    _vectorSearch = widget.entry?.vectorSearch ?? false;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _keysController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(widget.entry == null ? 'New Memory' : 'Edit Memory', style: const TextStyle(color: AppColors.textPrimary)),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field('Title', _titleController, hint: 'Optional label'),
              const SizedBox(height: 12),
              _field('Keys', _keysController, hint: 'Comma-separated trigger keys'),
              const SizedBox(height: 12),
              _field('Content', _contentController, hint: 'Memory text injected into prompt', maxLines: 6),
              const SizedBox(height: 12),
              SwitchListTile(
                title: Text('Vector Search', style: TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                subtitle: Text('Match via embeddings', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                value: _vectorSearch,
                onChanged: (v) => setState(() => _vectorSearch = v),
                dense: true,
                activeColor: AppColors.accent,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.black),
          onPressed: () {
            final keys = _keysController.text.split(',').map((k) => k.trim()).where((k) => k.isNotEmpty).toList();
            final content = _contentController.text.trim();
            if (content.isEmpty) return;
            final entry = MemoryEntry(
              id: widget.entry?.id ?? 'mem_${DateTime.now().millisecondsSinceEpoch}',
              title: _titleController.text.trim(),
              keys: keys,
              content: content,
              vectorSearch: _vectorSearch,
              status: widget.entry?.status ?? 'active',
            );
            Navigator.pop(context, entry);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _field(String label, TextEditingController controller, {String? hint, int maxLines = 1}) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        hintText: hint,
        hintStyle: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.4)),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

class _MemorySettingsDialog extends StatefulWidget {
  final MemoryBookSettings settings;

  const _MemorySettingsDialog({required this.settings});

  @override
  State<_MemorySettingsDialog> createState() => _MemorySettingsDialogState();
}

class _MemorySettingsDialogState extends State<_MemorySettingsDialog> {
  late bool _enabled;
  late bool _autoCreate;
  late int _maxInjected;
  late String _injectionTarget;
  late String _keyMatchMode;

  @override
  void initState() {
    super.initState();
    _enabled = widget.settings.enabled;
    _autoCreate = widget.settings.autoCreateEnabled;
    _maxInjected = widget.settings.maxInjectedEntries;
    _injectionTarget = widget.settings.injectionTarget;
    _keyMatchMode = widget.settings.keyMatchMode;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Memory Settings', style: TextStyle(color: AppColors.textPrimary)),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: Text('Enabled', style: TextStyle(fontSize: 14, color: AppColors.textPrimary)),
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
                activeColor: AppColors.accent,
                dense: true,
              ),
              SwitchListTile(
                title: Text('Auto-create', style: TextStyle(fontSize: 14, color: AppColors.textPrimary)),
                subtitle: Text('Auto-generate entries from chat', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                value: _autoCreate,
                onChanged: (v) => setState(() => _autoCreate = v),
                activeColor: AppColors.accent,
                dense: true,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text('Max entries in prompt', style: TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                  const Spacer(),
                  SizedBox(
                    width: 60,
                    child: DropdownButton<int>(
                      value: _maxInjected.clamp(1, 20),
                      items: List.generate(20, (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1}'))),
                      onChanged: (v) => setState(() => _maxInjected = v ?? 7),
                      underline: const SizedBox.shrink(),
                      style: TextStyle(fontSize: 14, color: AppColors.accent),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text('Inject into', style: TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                  const Spacer(),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'summary_block', label: Text('Block')),
                      ButtonSegment(value: 'summary_macro', label: Text('{{summary}}')),
                    ],
                    selected: {_injectionTarget},
                    onSelectionChanged: (s) => setState(() => _injectionTarget = s.first),
                    style: ButtonStyle(visualDensity: VisualDensity.compact),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text('Key matching', style: TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                  const Spacer(),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'plain', label: Text('Plain')),
                      ButtonSegment(value: 'glaze', label: Text('Glaze')),
                      ButtonSegment(value: 'both', label: Text('Both')),
                    ],
                    selected: {_keyMatchMode},
                    onSelectionChanged: (s) => setState(() => _keyMatchMode = s.first),
                    style: ButtonStyle(visualDensity: VisualDensity.compact),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.black),
          onPressed: () {
            final settings = widget.settings.copyWith(
              enabled: _enabled,
              autoCreateEnabled: _autoCreate,
              maxInjectedEntries: _maxInjected,
              injectionTarget: _injectionTarget,
              keyMatchMode: _keyMatchMode,
            );
            Navigator.pop(context, settings);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
