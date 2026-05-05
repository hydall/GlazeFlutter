import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/lorebook.dart';
import '../../core/state/lorebook_provider.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/glaze_scaffold.dart';
import 'widgets/entry_editor_dialog.dart';

class LorebookEditorScreen extends ConsumerStatefulWidget {
  final String lorebookId;

  const LorebookEditorScreen({super.key, required this.lorebookId});

  @override
  ConsumerState<LorebookEditorScreen> createState() => _LorebookEditorScreenState();
}

class _LorebookEditorScreenState extends ConsumerState<LorebookEditorScreen> {
  late TextEditingController _nameController;
  String _scope = 'global';
  List<LorebookEntry> _entries = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Lorebook? _findLorebook(List<Lorebook> list) {
    for (final lb in list) {
      if (lb.id == widget.lorebookId) return lb;
    }
    return null;
  }

  void _loadFrom(Lorebook lb) {
    if (_loaded) return;
    _loaded = true;
    _nameController.text = lb.name;
    _scope = lb.activationScope;
    _entries = List.from(lb.entries);
  }

  Future<void> _save() async {
    final lb = Lorebook(
      id: widget.lorebookId,
      name: _nameController.text.trim().isEmpty ? 'Untitled' : _nameController.text.trim(),
      enabled: true,
      activationScope: _scope,
      entries: _entries,
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
    await ref.read(lorebooksProvider.notifier).updateLorebook(lb);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved'), duration: Duration(seconds: 1)),
      );
    }
  }

  void _addEntry() async {
    final entry = await showDialog<LorebookEntry>(
      context: context,
      builder: (_) => const EntryEditorDialog(),
    );
    if (entry != null) {
      setState(() => _entries.add(entry));
      _save();
    }
  }

  void _editEntry(int index) async {
    final entry = await showDialog<LorebookEntry>(
      context: context,
      builder: (_) => EntryEditorDialog(entry: _entries[index]),
    );
    if (entry != null) {
      setState(() => _entries[index] = entry);
      _save();
    }
  }

  void _deleteEntry(int index) {
    setState(() => _entries.removeAt(index));
    _save();
  }

  void _toggleEntry(int index) {
    setState(() {
      _entries[index] = _entries[index].copyWith(enabled: !_entries[index].enabled);
    });
    _save();
  }

  @override
  Widget build(BuildContext context) {
    final lorebooksAsync = ref.watch(lorebooksProvider);

    return lorebooksAsync.when(
      data: (list) {
        final lb = _findLorebook(list);
        if (lb == null) {
          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(title: const Text('Not Found')),
            body: const Center(child: Text('Lorebook not found')),
          );
        }
        _loadFrom(lb);

        return Scaffold(
          backgroundColor: AppColors.background,
          floatingActionButton: FloatingActionButton(
            backgroundColor: AppColors.accent,
            child: const Icon(Icons.add, color: Colors.black),
            onPressed: _addEntry,
          ),
          body: Column(
            children: [
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: GlazeAppBar(
                    title: 'Edit Lorebook',
                    leading: BackButton(onPressed: () => Navigator.pop(context)),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(
                  children: [
                    TextField(
                      controller: _nameController,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'Name',
                        labelStyle: TextStyle(color: AppColors.textSecondary),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.05),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onSubmitted: (_) => _save(),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('Scope:', style: TextStyle(color: AppColors.textSecondary)),
                        const SizedBox(width: 8),
                        _ScopeChip(label: 'global', selected: _scope == 'global', color: Colors.green, onTap: () => setState(() => _scope = 'global')),
                        const SizedBox(width: 6),
                        _ScopeChip(label: 'character', selected: _scope == 'character', color: Colors.purple, onTap: () => setState(() => _scope = 'character')),
                        const SizedBox(width: 6),
                        _ScopeChip(label: 'chat', selected: _scope == 'chat', color: Colors.orange, onTap: () => setState(() => _scope = 'chat')),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _entries.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.article_outlined, size: 48, color: AppColors.textSecondary),
                            const SizedBox(height: 12),
                            Text('No entries yet', style: TextStyle(color: AppColors.textSecondary)),
                            const SizedBox(height: 4),
                            Text('Tap + to add one', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                        itemCount: _entries.length,
                        itemBuilder: (_, i) => _EntryTile(
                          entry: _entries[i],
                          onToggle: () => _toggleEntry(i),
                          onEdit: () => _editEntry(i),
                          onDelete: () => _deleteEntry(i),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
    );
  }
}

class _ScopeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _ScopeChip({required this.label, required this.selected, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: selected ? color : Colors.white.withValues(alpha: 0.1)),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: selected ? color : AppColors.textSecondary),
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  final LorebookEntry entry;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _EntryTile({required this.entry, required this.onToggle, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: Colors.white.withValues(alpha: 0.03),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: ListTile(
        dense: true,
        leading: Switch(
          value: entry.enabled,
          onChanged: (_) => onToggle(),
          activeColor: AppColors.accent,
        ),
        title: Text(
          entry.comment.isNotEmpty ? entry.comment : (entry.keys.isNotEmpty ? entry.keys.join(', ') : 'Entry'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: entry.enabled ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
        subtitle: Text(
          '${entry.keys.length} keys | order ${entry.order}${entry.constant ? ' | constant' : ''}',
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(icon: const Icon(Icons.edit_outlined, size: 18), onPressed: onEdit),
            IconButton(icon: const Icon(Icons.delete_outline, size: 18), onPressed: onDelete),
          ],
        ),
        onTap: onEdit,
      ),
    );
  }
}
