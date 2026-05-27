import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:soft_edge_blur/soft_edge_blur.dart';

import 'package:go_router/go_router.dart';

import '../../../core/services/chat_import_export.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/state/shared_prefs_provider.dart';
import '../../../features/settings/app_settings_provider.dart';
import '../../../core/state/lorebook_provider.dart';
import '../../../core/state/active_selection_provider.dart';
import '../../../core/state/chat_session_ops_provider.dart';
import '../../../features/chat_history/chat_history_provider.dart';
import '../../../shared/theme/app_colors.dart';

import '../../../shared/widgets/glaze_bottom_sheet.dart';
import '../../../shared/widgets/glaze_toast.dart';
import '../../image_gen/widgets/image_gen_sheet.dart';
import '../chat_actions_service.dart';
import '../chat_provider.dart';
import '../../character_list/character_detail_screen.dart';
import '../../personas/persona_list_screen.dart';
import '../../presets/preset_list_screen.dart';
import '../../regex/regex_list_screen.dart';
import '../../settings/api_settings_screen.dart';
import 'authors_note_sheet.dart';
import 'chat_stats_sheet.dart';
import 'lorebook_coverage_sheet.dart';
import 'lorebook_quick_sheet.dart';
import 'magic_drawer_models.dart';
import 'magic_drawer_stats_service.dart';
import 'magic_drawer_widgets.dart';
import 'memory_books_sheet.dart';
import 'prompt_preview_screen.dart';
import 'summary_sheet.dart';
import '../state/token_breakdown_cache.dart';
import 'tokenizer_sheet.dart';

class MagicDrawerPanel extends ConsumerStatefulWidget {
  final String charId;
  final bool disableEffects;

  /// Called when the drawer wants to dismiss itself (e.g. after the user picks
  /// an item that opens another screen). The host owns visibility, so we ask
  /// it to hide us instead of popping a route.
  final VoidCallback? onClose;

  const MagicDrawerPanel({
    super.key,
    required this.charId,
    this.onClose,
    this.disableEffects = false,
  });

  @override
  ConsumerState<MagicDrawerPanel> createState() => _MagicDrawerPanelState();
}

class _MagicDrawerPanelState extends ConsumerState<MagicDrawerPanel> {
  static const _itemsKey = 'magic_drawer_items';
  static const _deletedItemsKey = 'magic_drawer_deleted_items';

  static const _allItems = <MagicDrawerItemDef>[
    MagicDrawerItemDef(id: 'context', label: 'Tokenizer', icon: Icons.segment),
    MagicDrawerItemDef(id: 'summary', label: 'Summary', icon: Icons.subject),
    MagicDrawerItemDef(id: 'sessions', label: 'Sessions', icon: Icons.history),
    MagicDrawerItemDef(id: 'stats', label: 'Stats', icon: Icons.insert_chart),
    MagicDrawerItemDef(
      id: 'char-card',
      label: 'Character',
      icon: Icons.account_box,
    ),
    MagicDrawerItemDef(
      id: 'lorebooks',
      label: 'Lorebooks',
      icon: Icons.library_books,
    ),
    MagicDrawerItemDef(
      id: 'memory-books',
      label: 'Memory Books',
      icon: Icons.add_box,
    ),
    MagicDrawerItemDef(id: 'regex', label: 'Regex', icon: Icons.code),
    MagicDrawerItemDef(id: 'api', label: 'API', icon: Icons.cloud),
    MagicDrawerItemDef(
      id: 'presets',
      label: 'Presets',
      icon: Icons.description,
    ),
    MagicDrawerItemDef(
      id: 'preview',
      label: 'Request Preview',
      icon: Icons.visibility,
    ),
    MagicDrawerItemDef(id: 'coverage', label: 'Coverage', icon: Icons.search),
    MagicDrawerItemDef(
      id: 'personas',
      label: 'Personas',
      icon: Icons.manage_accounts,
    ),
    MagicDrawerItemDef(id: 'image-gen', label: 'Image Gen', icon: Icons.image),
    MagicDrawerItemDef(
      id: 'authors-note',
      label: "Author's Note",
      icon: Icons.edit_note,
    ),
  ];

  final List<String> _itemIds = [];
  final Set<String> _deletedIds = {};
  bool _editing = false;
  bool _loading = true;
  bool _loadingTokens = false;
  int? _draggingIndex;
  int? _hoverIndex;
  MagicDrawerStats _stats = const MagicDrawerStats();
  Timer? _debounceTimer;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadDrawer();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadDrawer() async {
    try {
      await _loadLayout();
      await _loadStats();
    } catch (e) {
      debugPrint('[MagicDrawer] _loadDrawer error: $e');
    }
    if (mounted) {
      setState(() => _loading = false);
    }
    // Defer token stats calculation until after UI render completes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scheduleTokenStats();
    });
  }

  Future<void> _loadLayout() async {
    final prefs = await ref.read(sharedPreferencesProvider.future);
    final savedOrder = prefs.getStringList(_itemsKey);
    final savedDeleted = prefs.getStringList(_deletedItemsKey) ?? const [];
    _deletedIds
      ..clear()
      ..addAll(savedDeleted.where(_isKnownItem));

    final defaultIds = _allItems.map((item) => item.id).toList();
    if (savedOrder == null || savedOrder.isEmpty) {
      _itemIds
        ..clear()
        ..addAll(defaultIds);
      return;
    }

    final filteredSaved = savedOrder.where(_isKnownItem).toList();
    final missing = defaultIds
        .where((id) => !filteredSaved.contains(id) && !_deletedIds.contains(id))
        .toList();

    _itemIds
      ..clear()
      ..addAll(filteredSaved)
      ..addAll(missing);
  }

  Future<void> _saveLayout() async {
    final prefs = await ref.read(sharedPreferencesProvider.future);
    await prefs.setStringList(_itemsKey, List<String>.from(_itemIds));
    await prefs.setStringList(_deletedItemsKey, _deletedIds.toList());
  }

  Future<void> _loadStats() async {
    _stats = await MagicDrawerStatsService(ref).computeStats(widget.charId);
  }

  void _scheduleTokenStats() {
    _debounceTimer?.cancel();
    final delay = ref.read(appSettingsProvider).valueOrNull?.batterySaver == true
        ? const Duration(milliseconds: 700)
        : const Duration(milliseconds: 300);
    _debounceTimer = Timer(delay, _loadTokenStats);
  }

  Future<void> _loadTokenStats() async {
    if (!mounted) return;
    setState(() => _loadingTokens = true);
    final updated = await MagicDrawerStatsService(
      ref,
    ).computeTokenStats(widget.charId, _stats);
    if (!mounted) return;
    setState(() {
      _stats = updated;
      _loadingTokens = false;
    });
  }

  /// Lightweight refresh: only stats, no layout re-read from disk.
  /// Called by the debounce timer when messages change.
  Future<void> _refreshStats() async {
    TokenBreakdownCache.invalidate();
    try {
      await _loadStats();
    } catch (e) {
      debugPrint('[MagicDrawer] _refreshStats error: $e');
    }
    if (mounted) setState(() {});
    _scheduleTokenStats();
  }

  void _scheduleRefresh() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), _refreshStats);
  }

  bool _isKnownItem(String id) => _allItems.any((item) => item.id == id);

  List<MagicDrawerCardItem> get _displayItems {
    final list = _itemIds
        .map((id) => _allItems.where((item) => item.id == id).firstOrNull)
        .whereType<MagicDrawerItemDef>()
        .map((def) => MagicDrawerCardItem(def: def, status: _statusFor(def.id)))
        .toList();
    if (_editing && _canAddMore) {
      list.add(
        const MagicDrawerCardItem(
          def: MagicDrawerItemDef(id: 'add-btn', label: 'Add', icon: Icons.add),
          isAddButton: true,
        ),
      );
    }
    return list;
  }

  bool get _canAddMore => _allItems.any((item) => !_itemIds.contains(item.id));

  String? _statusFor(String id) {
    return switch (id) {
      'context' =>
        _stats.promptTokens > 0 && _stats.contextSize > 0
            ? '${_stats.promptTokens}/${_stats.contextSize} tokens'
            : _loadingTokens && _stats.approximateHistoryTokens > 0
            ? '~${_stats.approximateHistoryTokens}/${_stats.contextSize} tokens'
            : _loadingTokens
            ? 'Calculating...'
            : null,
      'summary' =>
        _stats.summaryChars > 0
            ? '${_stats.summaryChars} chars'
            : 'Not generated',
      'sessions' => '${_stats.sessionCount} sessions',
      'stats' => '${_stats.messageCount} messages',
      'char-card' =>
        _stats.characterTokens > 0
            ? '${_stats.characterTokens} tokens'
            : _stats.character?.name,
      'lorebooks' => '${_stats.lorebookEntryCount} entries',
      'memory-books' => '${_stats.memoryEntryCount} entries',
      'regex' => '${_stats.regexCount} scripts',
      'api' =>
        _stats.apiConfig?.name.isNotEmpty == true
            ? _stats.apiConfig!.name
            : _stats.apiConfig?.model,
      'presets' =>
        _stats.activePreset == null
            ? 'Default'
            : _stats.presetTokens > 0
            ? '${_stats.activePreset!.name} • ${_stats.presetTokens} tokens'
            : _stats.activePreset!.name,
      'preview' =>
        _stats.promptTokens > 0
            ? '${_stats.promptTokens} tokens'
            : _loadingTokens && _stats.approximateHistoryTokens > 0
            ? '~${_stats.approximateHistoryTokens} tokens'
            : _loadingTokens
            ? 'Calculating...'
            : null,
      'coverage' =>
        _stats.lorebookEntryCount > 0
            ? '${_stats.lorebookEntryCount} entries'
            : null,
      'personas' => _stats.activePersona?.name ?? 'Default',
      'image-gen' => _stats.imageGenEnabled ? 'On' : 'Off',
      'authors-note' =>
        _stats.session?.authorsNote != null &&
                _stats.session!.authorsNote!.content.isNotEmpty
            ? '${_stats.session!.authorsNote!.content.length} chars'
            : 'Empty',
      _ => null,
    };
  }

  void _toggleEditing() {
    setState(() => _editing = !_editing);
  }

  Future<void> _removeItem(String id) async {
    setState(() {
      _itemIds.remove(id);
      _deletedIds.add(id);
    });
    await _saveLayout();
  }

  Future<void> _moveItem(int from, int to) async {
    if (from == to ||
        from < 0 ||
        to < 0 ||
        from >= _itemIds.length ||
        to >= _itemIds.length) {
      return;
    }
    setState(() {
      final item = _itemIds.removeAt(from);
      _itemIds.insert(to, item);
      _hoverIndex = null;
    });
    await _saveLayout();
  }

  Future<void> _showAddItemSheet() async {
    final available = _allItems
        .where((item) => !_itemIds.contains(item.id))
        .toList();
    if (available.isEmpty) return;

    await GlazeBottomSheet.show<MagicDrawerItemDef>(
      context,
      title: 'Add Action',
      items: available
          .map(
            (item) => BottomSheetItem(
              icon: item.icon,
              label: item.label,
              onTap: () => Navigator.of(context).pop(item),
            ),
          )
          .toList(),
    ).then((selected) async {
      if (selected == null || !mounted) return;
      setState(() {
        _itemIds.add(selected.id);
        _deletedIds.remove(selected.id);
      });
      await _saveLayout();
    });
  }

  Future<void> _handleTap(MagicDrawerItemDef item) async {
    if (_editing) return;

    switch (item.id) {
      case 'context':
        showTokenizerSheet(context, widget.charId);
        return;
      case 'summary':
        showSummarySheet(context, widget.charId);
        return;
      case 'sessions':
        await _showSessionsSheet();
        return;
      case 'stats':
        await _showStatsSheet();
        return;
      case 'char-card':
        widget.onClose?.call();
        if (mounted) {
          final result = await showModalBottomSheet<String>(
            context: context,
            isScrollControlled: true,
            useRootNavigator: true,
            backgroundColor: Colors.transparent,
            builder: (_) => CharacterDetailScreen(charId: widget.charId),
          );
          if (result != null && result.isNotEmpty && mounted) {
            context.go(result);
          }
        }
        return;
      case 'lorebooks':
        if (mounted) showLorebookQuickSheet(context, ref, widget.charId);
        return;
      case 'memory-books':
        await _showMemoryBooks();
        return;
      case 'regex':
        widget.onClose?.call();
        if (mounted) {
          showModalBottomSheet(
            context: context,
            useRootNavigator: true,
            backgroundColor: Colors.transparent,
            barrierColor: Colors.black54,
            isScrollControlled: true,
            builder: (_) => const RegexListScreen(),
          );
        }
        return;
      case 'api':
        widget.onClose?.call();
        if (mounted) {
          showModalBottomSheet(
            context: context,
            useRootNavigator: true,
            backgroundColor: Colors.transparent,
            barrierColor: Colors.black54,
            isScrollControlled: true,
            builder: (_) => const ApiSettingsScreen(),
          );
        }
        return;
      case 'presets':
        widget.onClose?.call();
        if (mounted) {
          showModalBottomSheet(
            context: context,
            useRootNavigator: true,
            backgroundColor: Colors.transparent,
            barrierColor: Colors.black54,
            isScrollControlled: true,
            builder: (_) => const PresetListScreen(),
          );
        }
        return;
      case 'preview':
        showPromptPreviewScreen(context, widget.charId);
        return;
      case 'coverage':
        showLorebookCoverageSheet(context, ref, widget.charId);
        return;
      case 'personas':
        widget.onClose?.call();
        if (mounted) {
          showModalBottomSheet(
            context: context,
            useRootNavigator: true,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => const PersonaListScreen(),
          );
        }
        return;
      case 'image-gen':
        widget.onClose?.call();
        if (mounted) {
          showModalBottomSheet(
            context: context,
            useRootNavigator: true,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => const ImageGenSheet(),
          );
        }
        return;
      case 'authors-note':
        showAuthorsNoteSheet(context, widget.charId);
        return;
    }
  }

  Future<void> _showMemoryBooks() async {
    final session = ref.read(chatProvider(widget.charId)).value?.session;
    if (session == null) return;
    GlazeBottomSheet.show(
      context,
      child: MemoryBooksSheet(sessionId: session.id, charId: widget.charId),
    );
  }

  Future<void> _showStatsSheet() async {
    widget.onClose?.call();
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChatStatsSheet(initialCharId: widget.charId),
    );
  }

  Future<void> _showSessionsSheet() async {
    final currentSession = ref.read(chatProvider(widget.charId)).value?.session;
    if (currentSession == null) return;

    if (!mounted) return;
    await GlazeBottomSheet.show(
      context,
      title: 'Sessions',
      headerAction: IconButton(
        icon: Icon(Icons.add, color: context.cs.primary),
        onPressed: _showSessionAddMenu,
      ),
      child: _SessionsSheetContent(
        charId: widget.charId,
        onSessionActions: _showSessionActions,
      ),
    );
  }

  void _showSessionAddMenu() {
    GlazeBottomSheet.show<String>(
      context,
      title: 'Add Session',
      items: [
        BottomSheetItem(
          icon: Icons.add_circle_outline,
          label: 'New Session',
          onTap: () => Navigator.of(context).pop('new'),
        ),
        BottomSheetItem(
          icon: Icons.file_download,
          label: 'Import Chat',
          onTap: () => Navigator.of(context).pop('import'),
        ),
      ],
    ).then((result) async {
      if (!mounted) return;
      if (result == 'new') {
        Navigator.of(context).pop(); // Pops Sessions Sheet
        await ref.read(chatProvider(widget.charId).notifier).newSession();
      } else if (result == 'import') {
        await _importChat();
      }
    });
  }

  void _showSessionActions(String sessionId) {
    GlazeBottomSheet.show<String>(
      context,
      title: 'Session',
      items: [
        BottomSheetItem(
          icon: Icons.upload_file,
          label: 'Export (JSONL)',
          onTap: () => Navigator.of(context).pop('export'),
        ),
        BottomSheetItem(
          icon: Icons.drive_file_rename_outline,
          label: 'Rename',
          onTap: () => Navigator.of(context).pop('rename'),
        ),
        BottomSheetItem(
          icon: Icons.delete_outline,
          label: 'Delete',
          isDestructive: true,
          onTap: () => Navigator.of(context).pop('delete'),
        ),
      ],
    ).then((result) async {
      if (!mounted) return;
      switch (result) {
        case 'export':
          await ref.read(chatActionsServiceProvider).exportSessionUI(
            context,
            charId: widget.charId,
            sessionId: sessionId,
          );
        case 'rename':
          _showRenameDialog(sessionId);
        case 'delete':
          await ref.read(chatHistoryProvider.notifier).deleteSession(sessionId);
          ref.invalidate(chatProvider(widget.charId));
      }
    });
  }

  void _showRenameDialog(String sessionId) async {
    final session = await ref.read(chatSessionOpsProvider.notifier).getSession(sessionId);
    if (!mounted || session == null) return;
    final currentName = session.sessionVars['sessionName']?.isNotEmpty == true
        ? session.sessionVars['sessionName']!
        : 'Session #${session.sessionIndex + 1}';
    GlazeBottomSheet.show(
      context,
      title: 'Rename Session',
      input: BottomSheetInput(
        placeholder: 'Session name',
        value: currentName,
        confirmLabel: 'Rename',
        onConfirm: (val) async {
          Navigator.of(context, rootNavigator: true).pop();
          if (val.trim().isNotEmpty) {
            final updatedVars = Map<String, String>.from(session.sessionVars);
            updatedVars['sessionName'] = val.trim();
            await ref.read(chatSessionOpsProvider.notifier).saveSession(session.copyWith(sessionVars: updatedVars));
            ref.invalidate(chatProvider(widget.charId));
          }
        },
      ),
    );
  }

  Future<void> _importChat() async {
    final result = await FilePicker.pickFiles(
      type: Platform.isIOS ? FileType.any : FileType.custom,
      allowedExtensions: Platform.isIOS ? null : ['jsonl', 'json'],
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final filePath = file.path;
    try {
      int count;
      if (file.bytes != null) {
        final importResult = importChatFromJsonlString(
          utf8.decode(file.bytes!),
        );
        count = await ref.read(chatActionsServiceProvider)
            .importChatFromResult(widget.charId, importResult);
      } else if (filePath != null) {
        count = await ref.read(chatActionsServiceProvider)
            .importChat(widget.charId, filePath);
      } else {
        return;
      }
      if (!mounted) return;
      if (count > 0) {
        // Pop the sessions sheet if import succeeds
        Navigator.of(context).pop();
      }
      GlazeToast.show(
        context,
        count == 0 ? 'No messages found in file' : 'Imported $count messages',
      );
    } catch (e) {
      if (mounted) GlazeToast.error(context, 'Import failed: ', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(chatProvider(widget.charId), (prev, next) {
      final prevSession = prev?.value?.session;
      final nextSession = next.value?.session;
      if (prevSession?.id != nextSession?.id ||
          prevSession?.messages.length != nextSession?.messages.length ||
          prevSession?.messages.lastOrNull?.content !=
              nextSession?.messages.lastOrNull?.content) {
        _scheduleRefresh();
      }
    });
    ref.listen(activePresetIdProvider, (prev, next) {
      if (prev != next) _scheduleRefresh();
    });
    ref.listen(activePersonaIdProvider, (prev, next) {
      if (prev != next) _scheduleRefresh();
    });
    ref.listen(lorebookActivationsProvider, (prev, next) {
      if (prev != next) _scheduleRefresh();
    });

    final items = _displayItems;
    final batterySaver =
        ref.watch(appSettingsProvider).valueOrNull?.batterySaver ?? false;

    final scrollable = RawScrollbar(
      controller: _scrollController,
      padding: const EdgeInsets.only(top: 60),
      thickness: 3,
      radius: const Radius.circular(3),
      thumbColor: Colors.white24,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final itemWidth = (constraints.maxWidth - 24 - 12) / 3;
            return SingleChildScrollView(
              controller: _scrollController,
              padding: EdgeInsets.fromLTRB(
                12,
                60,
                12,
                16 + MediaQuery.of(context).padding.bottom,
              ),
              child: Wrap(
                spacing: 6,
                runSpacing: 8,
                children: List.generate(items.length, (index) {
                  final item = items[index];
                  if (item.isAddButton) {
                    return SizedBox(
                      width: itemWidth,
                      child: AddMagicCard(onTap: _showAddItemSheet),
                    );
                  }
                  final card = MagicCard(
                    item: item,
                    editing: _editing,
                    hovered: _hoverIndex == index && _draggingIndex != index,
                    onTap: () => _handleTap(item.def),
                    onDelete: () => _removeItem(item.def.id),
                  );

                  return SizedBox(
                    width: itemWidth,
                    child: DragTarget<int>(
                      onWillAcceptWithDetails: (details) {
                        setState(() => _hoverIndex = index);
                        return details.data != index;
                      },
                      onLeave: (_) {
                        if (_hoverIndex == index) {
                          setState(() => _hoverIndex = null);
                        }
                      },
                      onAcceptWithDetails: (details) {
                        _moveItem(details.data, index);
                      },
                      builder: (context, _, _) {
                        return LongPressDraggable<int>(
                          data: index,
                          delay: const Duration(milliseconds: 300),
                          onDragStarted: () {
                            HapticFeedback.mediumImpact();
                            setState(() {
                              if (!_editing) _editing = true;
                              _draggingIndex = index;
                            });
                          },
                          onDragEnd: (_) {
                            setState(() {
                              _draggingIndex = null;
                              _hoverIndex = null;
                            });
                          },
                          feedback: SizedBox(
                            width: itemWidth,
                            child: Material(
                              color: Colors.transparent,
                              child: Opacity(opacity: 0.92, child: card),
                            ),
                          ),
                          childWhenDragging: Opacity(
                            opacity: 0.25,
                            child: card,
                          ),
                          child: card,
                        );
                      },
                    ),
                  );
                }),
              ),
            );
          },
        ),
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: context.colors.charBubble,
        border: Border(top: BorderSide(color: context.cs.outlineVariant)),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: batterySaver
                || widget.disableEffects
                ? scrollable
                : SoftEdgeBlur(
                    edges: [
                      EdgeBlur(
                        type: EdgeType.topEdge,
                        size: 68,
                        sigma: 24,
                        tintColor: context.cs.surface.withValues(alpha: 0.4),
                        controlPoints: [
                          ControlPoint(
                            position: 0.5,
                            type: ControlPointType.visible,
                          ),
                          ControlPoint(
                            position: 1.0,
                            type: ControlPointType.transparent,
                          ),
                        ],
                      ),
                    ],
                    child: scrollable,
                  ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Center(
                  child: Container(
                    width: 32,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[600],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: MagicDrawerHeader(
              editing: _editing,
              onToggleEditing: _toggleEditing,
            ),
          ),
          if (_loading)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x22000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}

class _SessionsSheetContent extends ConsumerStatefulWidget {
  final String charId;
  final void Function(String) onSessionActions;

  const _SessionsSheetContent({
    required this.charId,
    required this.onSessionActions,
  });

  @override
  ConsumerState<_SessionsSheetContent> createState() =>
      _SessionsSheetContentState();
}

class _SessionsSheetContentState extends ConsumerState<_SessionsSheetContent> {
  List<ChatSession> _sessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sessions = await ref
        .read(chatProvider(widget.charId).notifier)
        .getSessions();
    if (mounted) {
      setState(() {
        _sessions = sessions;
        _loading = false;
      });
    }
  }

  String _formatRelativeTime(int updatedAtSeconds) {
    final updated = DateTime.fromMillisecondsSinceEpoch(
      updatedAtSeconds * 1000,
    );
    final diff = DateTime.now().difference(updated);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(chatProvider(widget.charId), (prev, next) {
      _load();
    });

    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    final currentSession = ref
        .watch(chatProvider(widget.charId))
        .value
        ?.session;
    final currentSessionId = currentSession?.id;

    return GlazeSessionList(
      items: _sessions
          .map(
            (session) => BottomSheetSessionItem(
              title: session.sessionVars['sessionName']?.isNotEmpty == true
                  ? session.sessionVars['sessionName']!
                  : 'Session #${session.sessionIndex + 1}',
              count: session.messages.length,
              time: session.updatedAt == 0
                  ? ''
                  : _formatRelativeTime(session.updatedAt),
              preview:
                  session.messages.lastOrNull?.content ?? 'No messages yet',
              isActive: session.id == currentSessionId,
              onTap: () {
                Navigator.of(context).pop();
                if (session.sessionIndex != currentSession?.sessionIndex) {
                  ref
                      .read(chatProvider(widget.charId).notifier)
                      .switchSession(session.sessionIndex);
                }
              },
              onMore: () {
                widget.onSessionActions(session.id);
              },
            ),
          )
          .toList(),
    );
  }
}
