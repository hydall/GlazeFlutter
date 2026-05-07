import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/lorebook.dart';
import '../../core/llm/lorebook_vector_search.dart';
import '../../core/state/db_provider.dart';
import '../../core/state/lorebook_provider.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/glaze_bottom_sheet.dart';
import '../../shared/widgets/glaze_scaffold.dart';
import '../../shared/widgets/glaze_toast.dart';
import 'lorebook_connections_sheet.dart';
import 'lorebook_per_book_settings_screen.dart';
import 'widgets/entry_editor_dialog.dart';

class LorebookEditorScreen extends ConsumerStatefulWidget {
  final String lorebookId;

  const LorebookEditorScreen({super.key, required this.lorebookId});

  @override
  ConsumerState<LorebookEditorScreen> createState() =>
      _LorebookEditorScreenState();
}

class _LorebookEditorScreenState extends ConsumerState<LorebookEditorScreen> {
  late TextEditingController _nameController;
  late TextEditingController _searchController;
  List<LorebookEntry> _entries = [];
  LorebookSettings? _settings;
  Map<String, String> _embeddingStatuses = {};
  bool _loaded = false;
  bool _isIndexing = false;
  String _indexStatus = '';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _searchController.dispose();
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
    _entries = List.from(lb.entries);
    _settings = lb.settings;
    _loadEmbeddingStatuses();
  }

  Future<void> _loadEmbeddingStatuses() async {
    final repo = ref.read(embeddingRepoProvider);
    final statuses = <String, String>{};
    for (final entry in _entries) {
      if (!entry.vectorSearch || !entry.enabled || entry.constant) continue;
      final record = await repo.getByEntryId(entry.id);
      if (record == null) {
        statuses[entry.id] = 'none';
      } else if (record.errorJson != null) {
        statuses[entry.id] = 'error';
      } else if (record.vectorsBlob != null) {
        statuses[entry.id] = 'indexed';
      } else {
        statuses[entry.id] = 'none';
      }
    }
    if (mounted) setState(() => _embeddingStatuses = statuses);
  }

  Future<void> _save() async {
    final existing = ref.read(lorebooksProvider).value
        ?.where((l) => l.id == widget.lorebookId).firstOrNull;
    final lb = Lorebook(
      id: widget.lorebookId,
      name: _nameController.text.trim().isEmpty
          ? 'Untitled'
          : _nameController.text.trim(),
      enabled: existing?.enabled ?? true,
      activationScope: existing?.activationScope ?? 'global',
      activationTargetId: existing?.activationTargetId,
      entries: _entries,
      settings: _settings,
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
    await ref.read(lorebooksProvider.notifier).updateLorebook(lb);
    if (mounted) {
      GlazeToast.show(context, 'Saved');
    }
  }

  void _addEntry() async {
    final entry = await showDialog<LorebookEntry>(
      context: context,
      builder: (_) => EntryEditorDialog(lorebookId: widget.lorebookId),
    );
    if (entry != null) {
      setState(() => _entries.add(entry));
      _save();
    }
  }

  void _editEntry(int index) async {
    final entry = await showDialog<LorebookEntry>(
      context: context,
      builder: (_) => EntryEditorDialog(
        entry: _entries[index],
        lorebookId: widget.lorebookId,
      ),
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

  Future<void> _indexEntries() async {
    final config = ref.read(embeddingConfigProvider);
    if (config.endpoint.isEmpty) {
      GlazeToast.show(
        context,
        'Set up embedding API in Embedding Settings first',
      );
      return;
    }

    final vectorEntries = _entries
        .where((e) => e.vectorSearch && e.enabled && !e.constant)
        .toList();
    if (vectorEntries.isEmpty) {
      GlazeToast.show(context, 'No vector-enabled entries to index');
      return;
    }

    setState(() {
      _isIndexing = true;
      _indexStatus = 'Indexing 0/${vectorEntries.length}...';
    });

    try {
      final service = ref.read(lorebookEmbeddingServiceProvider);
      final result = await service.indexLorebookEntries(
        widget.lorebookId,
        _entries,
        config,
        onProgress: (current, total, name) {
          setState(() => _indexStatus = 'Indexing $current/$total...');
        },
      );

      if (mounted) {
        setState(() {
          _isIndexing = false;
          _indexStatus = '';
        });
        _loadEmbeddingStatuses();
        GlazeToast.show(
          context,
          'Indexed: ${result.indexed}, Skipped: ${result.skipped}, Failed: ${result.failed}',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isIndexing = false;
          _indexStatus = '';
        });
        _loadEmbeddingStatuses();
        GlazeToast.error(context, 'Indexing failed: ', e);
      }
    }
  }

  void _toggleEntry(int index) {
    setState(() {
      _entries[index] = _entries[index].copyWith(
        enabled: !_entries[index].enabled,
      );
    });
    _save();
  }

  void _resetEntriesToGlobal() {
    setState(() {
      for (int i = 0; i < _entries.length; i++) {
        _entries[i] = _entries[i].copyWith(
          caseSensitive: null,
          matchWholeWords: null,
        );
      }
    });
    _save();
    GlazeToast.show(context, 'Entry settings reset to global defaults');
  }

  List<LorebookEntry> get _filteredEntries {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return _entries;
    return _entries.where((e) {
      return e.keys.any((k) => k.toLowerCase().contains(q)) ||
          e.content.toLowerCase().contains(q) ||
          e.comment.toLowerCase().contains(q);
    }).toList();
  }

  bool get _needsReindex {
    return _entries.any(
      (e) =>
          e.vectorSearch &&
          e.enabled &&
          !e.constant &&
          _embeddingStatuses[e.id] != 'indexed',
    );
  }

  int get _missingVectorCount {
    return _entries
        .where(
          (e) =>
              e.vectorSearch &&
              e.enabled &&
              !e.constant &&
              _embeddingStatuses[e.id] != 'indexed',
        )
        .length;
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
                    leading: BackButton(
                      onPressed: () => Navigator.pop(context),
                    ),
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.restore, size: 20),
                        tooltip: 'Reset Entry Settings to Global',
                        onPressed: _resetEntriesToGlobal,
                      ),
                      if (_isIndexing)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Center(
                            child: Text(
                              _indexStatus,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.accent,
                              ),
                            ),
                          ),
                        )
                      else
                        IconButton(
                          icon: const Icon(Icons.auto_fix_high, size: 20),
                          tooltip: 'Index Vector Entries',
                          onPressed: _indexEntries,
                        ),
                    ],
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
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onSubmitted: (_) => _save(),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Spacer(),
                        if (_settings != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: _Badge(
                              label: 'custom',
                              color: Colors.purple,
                            ),
                          ),
                        IconButton(
                          icon: const Icon(Icons.settings_outlined, size: 18),
                          tooltip: 'Lorebook Settings',
                          onPressed: () async {
                            final result = await Navigator.push<Map<String, dynamic>>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => LorebookPerBookSettingsScreen(
                                  settings: _settings,
                                ),
                              ),
                            );
                            if (result != null) {
                              setState(() {
                                _settings = LorebookSettings.fromJson(result);
                              });
                              _save();
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.link, size: 18),
                          tooltip: 'Connections',
                          onPressed: () {
                            GlazeBottomSheet.show(
                              context,
                              child: LorebookConnectionsSheet(lorebookId: widget.lorebookId),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search keys, content...',
                    hintStyle: TextStyle(
                      color: AppColors.textSecondary.withValues(alpha: 0.5),
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(height: 8),
              if (_needsReindex)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      border: Border.all(
                        color: Colors.orange.withValues(alpha: 0.3),
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Vector entries need reindexing',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.orange,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                '$_missingVectorCount entries without embeddings',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          onPressed: _isIndexing ? null : _indexEntries,
                          child: Text(
                            _isIndexing ? '...' : 'Index All',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: _filteredEntries.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.article_outlined,
                              size: 48,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No entries yet',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Tap + to add one',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                        itemCount: _filteredEntries.length,
                        itemBuilder: (_, i) {
                          final entry = _filteredEntries[i];
                          final realIndex = _entries.indexOf(entry);
                          return _EntryTile(
                            entry: entry,
                            embeddingStatus: _embeddingStatuses[entry.id],
                            onToggle: () => _toggleEntry(realIndex),
                            onEdit: () => _editEntry(realIndex),
                            onDelete: () => _deleteEntry(realIndex),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  final LorebookEntry entry;
  final String? embeddingStatus; // 'indexed', 'error', 'none', null
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _EntryTile({
    required this.entry,
    this.embeddingStatus,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

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
          entry.comment.isNotEmpty
              ? entry.comment
              : (entry.keys.isNotEmpty ? entry.keys.join(', ') : 'Entry'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: entry.enabled
                ? AppColors.textPrimary
                : AppColors.textSecondary,
          ),
        ),
        subtitle: Text(
          '${entry.keys.length} keys | order ${entry.order}${entry.constant ? ' | constant' : ''}',
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (entry.vectorSearch) ...[
              _Badge(label: 'vec', color: Colors.cyan),
              if (embeddingStatus == 'indexed')
                _Badge(label: 'idx', color: Colors.green),
              if (embeddingStatus == 'error')
                _Badge(label: 'err', color: Colors.orange),
            ],
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18),
              onPressed: onEdit,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: onDelete,
            ),
          ],
        ),
        onTap: onEdit,
      ),
    );
  }
}
