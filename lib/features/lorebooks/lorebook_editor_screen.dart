import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';

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
import '../../shared/widgets/help_tip.dart';
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
    if (mounted) {
      setState(() {
        _embeddingStatuses = statuses;
        _embeddingErrorLabels = errorLabels;
      });
    }
  }

  Future<void> _save() async {
    final existing = ref.read(lorebooksProvider).value
        ?.where((l) => l.id == widget.lorebookId).firstOrNull;
    final lb = Lorebook(
      id: widget.lorebookId,
      name: _nameController.text.trim().isEmpty
          ? 'new_lorebook'.tr()
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
      GlazeToast.show(context, 'btn_save'.tr());
    }
  }

  void _addEntry() async {
    final entry = await showDialog<LorebookEntry>(
      context: context,
      builder: (_) => EntryEditorDialog(lorebookId: widget.lorebookId, embeddingTarget: _settings?.embeddingTarget ?? 'content'),
    );
    if (entry != null) {
      setState(() => _entries.add(entry));
      unawaited(_save());
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
      unawaited(_save());
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
        'vector_error_config_endpoint'.tr(),
      );
      return;
    }

    final vectorEntries = _entries
        .where((e) => e.vectorSearch && e.enabled && !e.constant)
        .toList();
    if (vectorEntries.isEmpty) {
      GlazeToast.show(context, 'no_entries_found'.tr());
      return;
    }

    setState(() {
      _isIndexing = true;
      _indexStatus = 'index_progress'.tr(namedArgs: {'done': '0', 'total': '${vectorEntries.length}'});
    });

    try {
      final service = ref.read(lorebookEmbeddingServiceProvider);
      final result = await service.indexLorebookEntries(
        widget.lorebookId,
        _entries,
        config,
        embeddingTarget: _settings?.embeddingTarget ?? 'content',
        onProgress: (current, total, name) {
          setState(() => _indexStatus = 'index_progress'.tr(namedArgs: {'done': '$current', 'total': '$total'}));
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
        await _loadEmbeddingStatuses();
        final statusParts = [
          'index_done'.tr(namedArgs: {'count': '${result.indexed}'}),
          if (result.skipped > 0) 'index_skipped'.tr(namedArgs: {'skipped': '${result.skipped}'}),
          if (result.failed > 0) 'index_failed'.tr(namedArgs: {'failed': '${result.failed}'}),
          if (result.rateLimited) ' (${"btn_rate_limited".tr(namedArgs: {"seconds": "${result.retryAfter}"})})',
        ];
        GlazeToast.show(
          context,
          statusParts.join(),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isIndexing = false;
          _indexStatus = '';
        });
        await _loadEmbeddingStatuses();
        GlazeToast.error(context, '${'settings_err_failed'.tr()} ', e);
      }
    }
  }

  void _retryFailed() async {
    await ref.read(apiListProvider.future);
    final config = ref.read(embeddingConfigProvider);
    if (config.endpoint.isEmpty) {
      GlazeToast.show(context, 'vector_error_config_endpoint'.tr());
      return;
    }

    setState(() {
      _isIndexing = true;
      _indexStatus = 'btn_retry_failed'.tr();
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
          setState(() => _indexStatus = 'index_progress'.tr(namedArgs: {'done': '$current', 'total': '$total'}));
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
        await _loadEmbeddingStatuses();
        final statusParts = [
          'index_done'.tr(namedArgs: {'count': '${result.indexed}'}),
          if (result.skipped > 0) 'index_skipped'.tr(namedArgs: {'skipped': '${result.skipped}'}),
          if (result.failed > 0) 'index_failed'.tr(namedArgs: {'failed': '${result.failed}'}),
          if (result.rateLimited) ' (${"btn_rate_limited".tr(namedArgs: {"seconds": "${result.retryAfter}"})})',
        ];
        GlazeToast.show(context, statusParts.join());
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isIndexing = false;
          _indexStatus = '';
        });
        await _loadEmbeddingStatuses();
        GlazeToast.error(context, '${'settings_err_failed'.tr()} ', e);
      }
    }
  }

  Future<void> _clearAndReindex() async {
    final confirmed = await GlazeBottomSheet.show<bool>(
      context,
      title: 'action_delete_indexes'.tr(),
      bigInfo: BottomSheetBigInfo(
        icon: Icons.delete_sweep,
        description: 'action_delete_indexes'.tr(),
      ),
      items: [
        BottomSheetItem(
          label: 'memory_books_btn_reindex'.tr(),
          isDestructive: true,
          centered: true,
          onTap: () => Navigator.of(context, rootNavigator: true).pop(true),
        ),
        BottomSheetItem(
          label: 'btn_cancel'.tr(),
          centered: true,
          onTap: () => Navigator.of(context, rootNavigator: true).pop(false),
        ),
      ],
    );
    if (confirmed != true) return;

    await ref.read(apiListProvider.future);
    final config = ref.read(embeddingConfigProvider);
    if (config.endpoint.isEmpty) {
      GlazeToast.show(context, 'vector_error_config_endpoint'.tr());
      return;
    }

    final vectorEntries = _entries.where((e) => e.vectorSearch && e.enabled && !e.constant).toList();
    if (vectorEntries.isEmpty) {
      GlazeToast.show(context, 'no_entries_found'.tr());
      return;
    }

    setState(() {
      _isIndexing = true;
      _indexStatus = '${'action_delete_indexes'.tr()}...';
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
          setState(() => _indexStatus = 'index_progress'.tr(namedArgs: {'done': '$current', 'total': '$total'}));
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
        await _loadEmbeddingStatuses();
        final statusParts = [
          'index_done'.tr(namedArgs: {'count': '${result.indexed}'}),
          if (result.failed > 0) 'index_failed'.tr(namedArgs: {'failed': '${result.failed}'}),
          if (result.rateLimited) ' (${"btn_rate_limited".tr(namedArgs: {"seconds": "${result.retryAfter}"})})',
        ];
        GlazeToast.show(context, statusParts.join());
      }
    } catch (e) {
      if (mounted) {
        setState(() { _isIndexing = false; _indexStatus = ''; });
        await _loadEmbeddingStatuses();
        GlazeToast.error(context, '${'settings_err_failed'.tr()} ', e);
      }
    }
  }

  void _startCooldownTimer() {
    Future.doWhile(() async {
      await Future<void>.delayed(const Duration(seconds: 1));
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
      title: 'action_delete_indexes'.tr(),
      bigInfo: BottomSheetBigInfo(
        icon: Icons.delete_outline,
        description: 'action_delete_indexes'.tr(),
      ),
      items: [
        BottomSheetItem(
          label: 'btn_delete'.tr(),
          isDestructive: true,
          centered: true,
          onTap: () => Navigator.of(context, rootNavigator: true).pop(true),
        ),
        BottomSheetItem(
          label: 'btn_cancel'.tr(),
          centered: true,
          onTap: () => Navigator.of(context, rootNavigator: true).pop(false),
        ),
      ],
    );
    if (confirmed != true) return;

    await ref.read(embeddingRepoProvider).deleteBySourceId(widget.lorebookId);
    await _loadEmbeddingStatuses();
    if (mounted) GlazeToast.show(context, 'action_delete_indexes'.tr());
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
    GlazeToast.show(context, 'action_reset'.tr());
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
      alreadyAll ? 'action_disable_vector_all'.tr() : 'action_enable_vector_all'.tr(),
    );
  }

  void _showTestDialog() {
    final testCtrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: context.cs.surfaceContainerHighest,
              title: Text('btn_test_connection'.tr(), style: TextStyle(color: context.cs.onSurface)),
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
                        hintText: 'placeholder_search_lore'.tr(),
                        hintStyle: TextStyle(color: context.cs.onSurfaceVariant.withValues(alpha: 0.5)),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.05),
                      ),
                      maxLines: 3,
                      minLines: 1,
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 12),
                    Text('label_entries'.tr(), style: TextStyle(color: context.cs.onSurfaceVariant, fontSize: 12)),
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
                      Text('no_results'.tr(), style: TextStyle(color: context.cs.onSurfaceVariant, fontSize: 13)),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('btn_close'.tr(), style: TextStyle(color: context.cs.onSurfaceVariant)),
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
            appBar: AppBar(title: Text('no_results'.tr())),
            body: Center(child: Text('no_lorebooks'.tr())),
          );
        }
        _loadFrom(lb);

        return Scaffold(
          backgroundColor: context.cs.surface,
          floatingActionButton: FloatingActionButton(
            backgroundColor: context.cs.primary,
            onPressed: _addEntry,
            child: const Icon(Icons.add, color: Colors.black),
          ),
          body: Column(
            children: [
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: GlazeAppBar(
                    titleWidget: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${'header_editor'.tr()} (${'label_lorebooks'.tr()})',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: context.cs.onSurface,
                          ),
                        ),
                        const HelpTip(term: 'lorebook'),
                      ],
                    ),
                    leading: BackButton(
                      onPressed: () => Navigator.pop(context),
                    ),
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.restore, size: 20),
                        tooltip: 'action_reset'.tr(),
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
                            ? 'action_disable_vector_all'.tr()
                            : 'action_enable_vector_all'.tr(),
                        onPressed: _entries.isEmpty ? null : _enableVectorForAll,
                      ),
                      if (_isIndexing || _rateLimitCooldown > 0)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Center(
                            child: Text(
                              _rateLimitCooldown > 0
                                  ? 'btn_rate_limited'.tr(namedArgs: {'seconds': '$_rateLimitCooldown'})
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
                          tooltip: 'action_delete_indexes'.tr(),
                          onPressed: _clearAndReindex,
                        ),
                        IconButton(
                          icon: const Icon(Icons.auto_fix_high, size: 20),
                          tooltip: 'action_index_all'.tr(),
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
                        labelText: 'placeholder_name'.tr(),
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
                          tooltip: 'menu_app_settings'.tr(),
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
                              unawaited(_save());
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.link, size: 18),
                          tooltip: 'header_connections'.tr(),
                          onPressed: () {
                            GlazeBottomSheet.show<void>(
                              context,
                              child: LorebookConnectionsSheet(lorebookId: widget.lorebookId),
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.science_outlined, size: 18),
                          tooltip: 'btn_test_connection'.tr(),
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
                    hintText: 'placeholder_search_lore'.tr(),
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
                                'vector_reindex_title'.tr(),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.orange,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'vector_reindex_desc'.tr(namedArgs: {'count': '$_missingVectorCount'}),
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
                            _isIndexing ? '...' : 'btn_index_all'.tr(),
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
                          child: Text('btn_retry_failed'.tr(), style: const TextStyle(fontSize: 12)),
                        ),
                        const SizedBox(width: 6),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.3)),
                          ),
                          onPressed: _isIndexing ? null : _deleteAllIndexes,
                          child: Text('action_delete_indexes'.tr(), style: const TextStyle(fontSize: 12)),
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
                              'no_entries_found'.tr(),
                              style: TextStyle(color: context.cs.onSurfaceVariant),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'empty_lorebooks_desc'.tr(),
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
