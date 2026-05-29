import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/lorebook.dart';
import '../../core/llm/embedding_error_labels.dart';
import '../../core/llm/lorebook_providers.dart';
import '../../core/state/db_provider.dart';
import '../../features/settings/api_list_provider.dart';
import '../../core/state/lorebook_provider.dart';
import '../../core/utils/time_helpers.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/glaze_bottom_sheet.dart';
import '../../shared/widgets/glaze_scaffold.dart';
import '../../shared/widgets/glaze_toast.dart';
import 'lorebook_connections_sheet.dart';
import 'lorebook_per_book_settings_screen.dart';
import 'widgets/entry_editor_dialog.dart';
import 'widgets/lorebook_entry_tile.dart';

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
  Map<String, String> _embeddingErrorLabels = {};
  bool _loaded = false;
  bool _isIndexing = false;
  String _indexStatus = '';
  int _rateLimitCooldown = 0;

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
    final errorLabels = <String, String>{};
    for (final entry in _entries) {
      if (!entry.vectorSearch || !entry.enabled || entry.constant) continue;
      final record = await repo.getByEntryId('${widget.lorebookId}_${entry.id}');
      if (record == null) {
        statuses[entry.id] = 'none';
      } else if (record.errorJson != null) {
        statuses[entry.id] = 'error';
        final error = repo.decodeError(record);
        errorLabels[entry.id] = EmbeddingErrorLabel.classify(error).label;
      } else if (repo.hasUsableVectors(record)) {
        statuses[entry.id] = 'indexed';
      } else {
        statuses[entry.id] = 'none';
      }
    }
    if (mounted) setState(() {
      _embeddingStatuses = statuses;
      _embeddingErrorLabels = errorLabels;
    });
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
      updatedAt: currentTimestampSeconds(),
    );
    await ref.read(lorebooksProvider.notifier).updateLorebook(lb);
    if (mounted) {
      GlazeToast.show(context, 'Saved');
    }
  }

  void _addEntry() async {
    final entry = await showDialog<LorebookEntry>(
      context: context,
      builder: (_) => EntryEditorDialog(lorebookId: widget.lorebookId, embeddingTarget: _settings?.embeddingTarget ?? 'content'),
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
        embeddingTarget: _settings?.embeddingTarget ?? 'content',
      ),
    );
    if (entry != null) {
      setState(() => _entries[index] = entry);
      _save();
    }
  }

  void _deleteEntry(int index) {
    final entryId = _entries[index].id;
    setState(() => _entries.removeAt(index));
    _save();
    ref.read(embeddingRepoProvider).deleteByEntryId(entryId);
  }

  Future<void> _indexEntries() async {
    await ref.read(apiListProvider.future);
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
        embeddingTarget: _settings?.embeddingTarget ?? 'content',
        onProgress: (current, total, name) {
          setState(() => _indexStatus = 'Indexing $current/$total...');
        },
      );

      if (mounted) {
        setState(() {
          _isIndexing = false;
          _indexStatus = '';
          if (result.rateLimited && result.retryAfter > 0) {
            _rateLimitCooldown = result.retryAfter;
            _startCooldownTimer();
          }
        });
        _loadEmbeddingStatuses();
        GlazeToast.show(
          context,
          'Indexed: ${result.indexed}, Skipped: ${result.skipped}, Failed: ${result.failed}${result.rateLimited ? ' (Rate limited)' : ''}',
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

  void _retryFailed() async {
    await ref.read(apiListProvider.future);
    final config = ref.read(embeddingConfigProvider);
    if (config.endpoint.isEmpty) {
      GlazeToast.show(context, 'Set up embedding API in Embedding Settings first');
      return;
    }

    setState(() {
      _isIndexing = true;
      _indexStatus = 'Retrying failed...';
    });

    try {
      final service = ref.read(lorebookEmbeddingServiceProvider);
      final result = await service.indexLorebookEntries(
        widget.lorebookId,
        _entries,
        config,
        retryFailedOnly: true,
        embeddingTarget: _settings?.embeddingTarget ?? 'content',
        onProgress: (current, total, name) {
          setState(() => _indexStatus = 'Indexing $current/$total...');
        },
      );

      if (mounted) {
        setState(() {
          _isIndexing = false;
          _indexStatus = '';
          if (result.rateLimited && result.retryAfter > 0) {
            _rateLimitCooldown = result.retryAfter;
            _startCooldownTimer();
          }
        });
        _loadEmbeddingStatuses();
        GlazeToast.show(context, 'Retried: ${result.indexed}, Skipped: ${result.skipped}, Failed: ${result.failed}${result.rateLimited ? ' (Rate limited)' : ''}');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isIndexing = false;
          _indexStatus = '';
        });
        _loadEmbeddingStatuses();
        GlazeToast.error(context, 'Retry failed: ', e);
      }
    }
  }

  Future<void> _clearAndReindex() async {
    final confirmed = await GlazeBottomSheet.show<bool>(
      context,
      title: 'Clear & Reindex',
      bigInfo: const BottomSheetBigInfo(
        icon: Icons.delete_sweep,
        description: 'Delete all existing embeddings for this lorebook and reindex from scratch?',
      ),
      items: [
        BottomSheetItem(
          label: 'Reindex',
          isDestructive: true,
          centered: true,
          onTap: () => Navigator.of(context, rootNavigator: true).pop(true),
        ),
        BottomSheetItem(
          label: 'Cancel',
          centered: true,
          onTap: () => Navigator.of(context, rootNavigator: true).pop(false),
        ),
      ],
    );
    if (confirmed != true) return;

    await ref.read(apiListProvider.future);
    final config = ref.read(embeddingConfigProvider);
    if (config.endpoint.isEmpty) {
      GlazeToast.show(context, 'Set up embedding API in Embedding Settings first');
      return;
    }

    final vectorEntries = _entries.where((e) => e.vectorSearch && e.enabled && !e.constant).toList();
    if (vectorEntries.isEmpty) {
      GlazeToast.show(context, 'No vector-enabled entries to index');
      return;
    }

    setState(() {
      _isIndexing = true;
      _indexStatus = 'Clearing embeddings...';
    });

    try {
      final service = ref.read(lorebookEmbeddingServiceProvider);
      await service.clearLorebookEmbeddings(widget.lorebookId);

      final result = await service.indexLorebookEntries(
        widget.lorebookId,
        _entries,
        config,
        forceReindex: true,
        embeddingTarget: _settings?.embeddingTarget ?? 'content',
        onProgress: (current, total, name) {
          setState(() => _indexStatus = 'Indexing $current/$total...');
        },
      );

      if (mounted) {
        setState(() {
          _isIndexing = false;
          _indexStatus = '';
          if (result.rateLimited && result.retryAfter > 0) {
            _rateLimitCooldown = result.retryAfter;
            _startCooldownTimer();
          }
        });
        _loadEmbeddingStatuses();
        GlazeToast.show(context, 'Reindexed: ${result.indexed}, Failed: ${result.failed}${result.rateLimited ? ' (Rate limited)' : ''}');
      }
    } catch (e) {
      if (mounted) {
        setState(() { _isIndexing = false; _indexStatus = ''; });
        _loadEmbeddingStatuses();
        GlazeToast.error(context, 'Reindex failed: ', e);
      }
    }
  }

  void _startCooldownTimer() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() {
        _rateLimitCooldown--;
        if (_rateLimitCooldown <= 0) _rateLimitCooldown = 0;
      });
      return _rateLimitCooldown > 0;
    });
  }

  void _deleteAllIndexes() async {
    final confirmed = await GlazeBottomSheet.show<bool>(
      context,
      title: 'Delete All Indexes',
      bigInfo: const BottomSheetBigInfo(
        icon: Icons.delete_outline,
        description: 'This will remove all stored embeddings for this lorebook. You will need to re-index entries after.',
      ),
      items: [
        BottomSheetItem(
          label: 'Delete All',
          isDestructive: true,
          centered: true,
          onTap: () => Navigator.of(context, rootNavigator: true).pop(true),
        ),
        BottomSheetItem(
          label: 'Cancel',
          centered: true,
          onTap: () => Navigator.of(context, rootNavigator: true).pop(false),
        ),
      ],
    );
    if (confirmed != true) return;

    await ref.read(embeddingRepoProvider).deleteBySourceId(widget.lorebookId);
    _loadEmbeddingStatuses();
    if (mounted) GlazeToast.show(context, 'All indexes deleted');
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
          position: 'matchGlobal',
        );
      }
    });
    _save();
    GlazeToast.show(context, 'Entry settings reset to global defaults');
  }

  void _enableVectorForAll() {
    final alreadyAll = _entries.every((e) => e.vectorSearch || e.constant);
    setState(() {
      for (int i = 0; i < _entries.length; i++) {
        if (!_entries[i].constant) {
          _entries[i] = _entries[i].copyWith(vectorSearch: !alreadyAll);
        }
      }
    });
    _save();
    _loadEmbeddingStatuses();
    GlazeToast.show(
      context,
      alreadyAll ? 'Vector search disabled for all entries' : 'Vector search enabled for all entries',
    );
  }

  void _showTestDialog() {
    final testCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: context.cs.surfaceContainerHighest,
              title: Text('Test Key Matching', style: TextStyle(color: context.cs.onSurface)),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: testCtrl,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      style: TextStyle(color: context.cs.onSurface),
                      decoration: InputDecoration(
                        hintText: 'Type test text...',
                        hintStyle: TextStyle(color: context.cs.onSurfaceVariant.withValues(alpha: 0.5)),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.05),
                      ),
                      maxLines: 3,
                      minLines: 1,
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 12),
                    Text('Matched entries:', style: TextStyle(color: context.cs.onSurfaceVariant, fontSize: 12)),
                    const SizedBox(height: 4),
                    ..._matchEntries(testCtrl.text).map((e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle, size: 14, color: Colors.green),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              e.comment.isNotEmpty ? e.comment : e.keys.join(', '),
                              style: TextStyle(color: context.cs.onSurface, fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    )),
                    if (testCtrl.text.isNotEmpty && _matchEntries(testCtrl.text).isEmpty)
                      Text('No matches', style: TextStyle(color: context.cs.onSurfaceVariant, fontSize: 13)),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Close', style: TextStyle(color: context.cs.onSurfaceVariant)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  List<LorebookEntry> _matchEntries(String text) {
    if (text.trim().isEmpty) return [];
    final lower = text.toLowerCase();
    return _entries.where((e) {
      if (!e.enabled) return false;
      for (final key in e.keys) {
        if (key.isEmpty) continue;
        final caseSensitive = e.caseSensitive ?? _settings?.caseSensitive ?? false;
        if (caseSensitive) {
          if (text.contains(key)) return true;
        } else {
          if (lower.contains(key.toLowerCase())) return true;
        }
      }
      for (final secKey in e.secondaryKeys) {
        if (secKey.isEmpty) continue;
        final caseSensitive = e.caseSensitive ?? _settings?.caseSensitive ?? false;
        if (caseSensitive) {
          if (text.contains(secKey)) return true;
        } else {
          if (lower.contains(secKey.toLowerCase())) return true;
        }
      }
      return false;
    }).toList();
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
            backgroundColor: context.cs.surface,
            appBar: AppBar(title: const Text('Not Found')),
            body: const Center(child: Text('Lorebook not found')),
          );
        }
        _loadFrom(lb);

        return Scaffold(
          backgroundColor: context.cs.surface,
          floatingActionButton: FloatingActionButton(
            backgroundColor: context.cs.primary,
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
                      IconButton(
                        icon: Icon(
                          _entries.every((e) => e.vectorSearch || e.constant)
                              ? Icons.hub
                              : Icons.hub_outlined,
                          size: 20,
                        ),
                        tooltip: _entries.every((e) => e.vectorSearch || e.constant)
                            ? 'Disable Vector Search for All'
                            : 'Enable Vector Search for All',
                        onPressed: _entries.isEmpty ? null : _enableVectorForAll,
                      ),
                      if (_isIndexing || _rateLimitCooldown > 0)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Center(
                            child: Text(
                              _rateLimitCooldown > 0
                                  ? 'Rate limited ($_rateLimitCooldown s)'
                                  : _indexStatus,
                              style: TextStyle(
                                fontSize: 12,
                                color: _rateLimitCooldown > 0 ? Colors.orangeAccent : context.cs.primary,
                              ),
                            ),
                          ),
                        )
                       else ...[
                        IconButton(
                          icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                          tooltip: 'Clear & Reindex (force)',
                          onPressed: _clearAndReindex,
                        ),
                        IconButton(
                          icon: const Icon(Icons.auto_fix_high, size: 20),
                          tooltip: 'Index Vector Entries',
                          onPressed: _indexEntries,
                        ),
                       ],
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
                      style: TextStyle(color: context.cs.onSurface),
                      decoration: InputDecoration(
                        labelText: 'Name',
                        labelStyle: TextStyle(color: context.cs.onSurfaceVariant),
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
                            child: LorebookEntryBadge(
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
                                  globalSettings: ref.read(lorebookSettingsProvider),
                                ),
                              ),
                            );
                            if (result != null) {
                              setState(() {
                                if (result['reset'] == true) {
                                  _settings = null;
                                } else if (result['settings'] != null) {
                                  _settings = LorebookSettings.fromJson(
                                      result['settings'] as Map<String, dynamic>);
                                }
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
                        IconButton(
                          icon: const Icon(Icons.science_outlined, size: 18),
                          tooltip: 'Test Keys',
                          onPressed: _showTestDialog,
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
                  style: TextStyle(
                    color: context.cs.onSurface,
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search keys, content...',
                    hintStyle: TextStyle(
                      color: context.cs.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      size: 18,
                      color: context.cs.onSurfaceVariant,
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
                                  color: context.cs.onSurfaceVariant,
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
                        const SizedBox(width: 6),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: context.cs.onSurfaceVariant,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                          ),
                          onPressed: _isIndexing ? null : _retryFailed,
                          child: const Text('Retry Failed', style: TextStyle(fontSize: 12)),
                        ),
                        const SizedBox(width: 6),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.3)),
                          ),
                          onPressed: _isIndexing ? null : _deleteAllIndexes,
                          child: const Text('Delete Indexes', style: TextStyle(fontSize: 12)),
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
                              color: context.cs.onSurfaceVariant,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No entries yet',
                              style: TextStyle(color: context.cs.onSurfaceVariant),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Tap + to add one',
                              style: TextStyle(
                                fontSize: 12,
                                color: context.cs.onSurfaceVariant,
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
                          return LorebookEntryTile(
                            entry: entry,
                            embeddingStatus: _embeddingStatuses[entry.id],
                            embeddingError: _embeddingErrorLabels[entry.id],
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
