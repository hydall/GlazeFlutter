import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/chat_import_export.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/state/lorebook_provider.dart';
import '../../../features/settings/app_settings_provider.dart';
import '../../../core/state/active_selection_provider.dart';
import '../../../core/state/chat_session_ops_provider.dart';
import '../../../core/llm/summary_service.dart';
import '../../../features/chat_history/chat_history_provider.dart';
import '../../../shared/utils/time_formatter.dart';
import '../../../shared/theme/app_colors.dart';

import '../../../shared/widgets/glaze_bottom_sheet.dart';
import '../../../shared/widgets/glaze_error_dialog.dart';
import '../../../shared/widgets/glaze_toast.dart';
import '../../image_gen/widgets/image_gen_sheet.dart';
import '../chat_actions_service.dart';
import '../chat_provider.dart';
import '../../character_list/character_detail_screen.dart';
import '../../personas/persona_list_screen.dart';
import '../../presets/preset_list_screen.dart';
import '../../regex/regex_sheet.dart';
import '../../settings/api_settings_screen.dart';
import 'authors_note_sheet.dart';
import 'chat_stats_sheet.dart';
import 'drawer_panel_scaffold.dart';
import 'lorebook_coverage_sheet.dart';
import 'lorebook_quick_sheet.dart';
import 'magic_drawer_models.dart';
import '../services/magic_drawer_layout_service.dart';
import '../services/magic_drawer_stats_service.dart';
import 'magic_drawer_widgets.dart';
import 'memory_books_sheet.dart';
import 'prompt_preview_screen.dart';
import 'summary_sheet.dart';
import '../state/token_breakdown_cache.dart';
import 'tokenizer_sheet.dart';
import '../../glossary/glossary_sheet.dart';
import '../../extensions/models/extension_preset.dart';
import '../../extensions/models/extensions_settings.dart';
import '../../extensions/providers/extension_presets_provider.dart';
import '../../extensions/providers/extensions_settings_provider.dart';
import '../../extensions/widgets/ext_blocks_settings_sheet.dart';

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
  static final _allItems = <MagicDrawerItemDef>[
    MagicDrawerItemDef(id: 'context', label: 'label_tokenizer'.tr(), icon: Icons.segment),
    MagicDrawerItemDef(id: 'summary', label: 'summary_title'.tr(), icon: Icons.subject),
    MagicDrawerItemDef(id: 'sessions', label: 'history_title'.tr(), icon: Icons.history),
    MagicDrawerItemDef(id: 'stats', label: 'Stats', icon: Icons.insert_chart),
    MagicDrawerItemDef(
      id: 'char-card',
      label: 'menu_characters'.tr(),
      icon: Icons.account_box,
    ),
    MagicDrawerItemDef(
      id: 'lorebooks',
      label: 'label_lorebooks'.tr(),
      icon: Icons.library_books,
    ),
    MagicDrawerItemDef(
      id: 'memory-books',
      label: 'magic_memory_books'.tr(),
      icon: Icons.add_box,
    ),
    MagicDrawerItemDef(id: 'regex', label: 'menu_regex'.tr(), icon: Icons.code),
    MagicDrawerItemDef(id: 'api', label: 'tab_api'.tr(), icon: Icons.cloud),
    MagicDrawerItemDef(
      id: 'presets',
      label: 'tab_presets'.tr(),
      icon: Icons.description,
    ),
    MagicDrawerItemDef(
      id: 'preview',
      label: 'magic_request_preview'.tr(),
      icon: Icons.visibility,
    ),
    MagicDrawerItemDef(id: 'coverage', label: 'Coverage', icon: Icons.search),
    MagicDrawerItemDef(
      id: 'personas',
      label: 'menu_personas'.tr(),
      icon: Icons.manage_accounts,
    ),
    MagicDrawerItemDef(id: 'image-gen', label: 'imggen_title'.tr(), icon: Icons.image),
    MagicDrawerItemDef(
      id: 'authors-note',
      label: 'magic_authors_notes'.tr(),
      icon: Icons.edit_note,
    ),
    MagicDrawerItemDef(
      id: 'glossary',
      label: 'menu_glossary'.tr(),
      icon: Icons.menu_book,
    ),
    MagicDrawerItemDef(
      id: 'ext-blocks',
      label: 'Ext Blocks',
      icon: Icons.extension_outlined,
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
    final layout = await MagicDrawerLayoutService(ref).loadLayout(_allItems);
    _deletedIds
      ..clear()
      ..addAll(layout.deletedIds);
    _itemIds
      ..clear()
      ..addAll(layout.itemIds);
  }

  Future<void> _saveLayout() async {
    await MagicDrawerLayoutService(ref).saveLayout(_itemIds, _deletedIds);
  }

  Future<void> _loadStats() async {
    _stats = await MagicDrawerStatsService(ref).computeStats(widget.charId);
  }

  void _scheduleTokenStats() {
    _debounceTimer?.cancel();
    final delay = ref.read(appSettingsProvider).value?.batterySaver == true
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

  List<MagicDrawerCardItem> _displayItems(
    ExtensionsSettings extSettings,
    List<ExtensionPreset> extPresets,
  ) {
    final list = _itemIds
        .map((id) => _allItems.where((item) => item.id == id).firstOrNull)
        .whereType<MagicDrawerItemDef>()
        .map(
          (def) => MagicDrawerCardItem(
            def: def,
            status: _statusFor(def.id, extSettings, extPresets),
          ),
        )
        .toList();
    if (_editing && _canAddMore) {
      list.add(
        MagicDrawerCardItem(
          def: MagicDrawerItemDef(id: 'add-btn', label: 'btn_add'.tr(), icon: Icons.add),
          isAddButton: true,
        ),
      );
    }
    return list;
  }

  bool get _canAddMore => _allItems.any((item) => !_itemIds.contains(item.id));

  String? _statusFor(
    String id,
    ExtensionsSettings extSettings,
    List<ExtensionPreset> extPresets,
  ) {
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
            ? 'label_default'.tr()
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
      'personas' => _stats.activePersona?.name ?? 'label_default'.tr(),
      'image-gen' => _stats.imageGenEnabled ? 'on'.tr() : 'off'.tr(),
      'authors-note' =>
        _stats.session?.authorsNote != null &&
                _stats.session!.authorsNote!.content.isNotEmpty
            ? '${_stats.session!.authorsNote!.content.length} chars'
            : 'placeholder_empty'.tr(),
      'ext-blocks' =>
        !extSettings.enabled
            ? 'off'.tr()
            : extSettings.activePresetId == null
            ? 'No preset'
            : extPresets
                      .where((p) => p.id == extSettings.activePresetId)
                      .firstOrNull
                      ?.name ??
                  'No preset',
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
        await showSummarySheet(context, widget.charId);
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
          await showModalBottomSheet<void>(
            context: context,
            useRootNavigator: true,
            backgroundColor: Colors.transparent,
            barrierColor: Colors.black54,
            isScrollControlled: true,
            builder: (_) => const RegexSheet(),
          );
        }
        return;
      case 'api':
        widget.onClose?.call();
        if (mounted) {
          await showModalBottomSheet<void>(
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
          await showModalBottomSheet<void>(
            context: context,
            useRootNavigator: true,
            backgroundColor: Colors.transparent,
            barrierColor: Colors.black54,
            isScrollControlled: true,
            builder: (_) => PresetListScreen(charId: widget.charId),
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
          await showModalBottomSheet<void>(
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
          await showModalBottomSheet<void>(
            context: context,
            useRootNavigator: true,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => const ImageGenSheet(),
          );
        }
        return;
      case 'authors-note':
        await showAuthorsNoteSheet(context, widget.charId);
        return;
      case 'glossary':
        widget.onClose?.call();
        if (mounted) await GlossarySheet.show(context);
        return;
      case 'ext-blocks':
        widget.onClose?.call();
        if (mounted) await _showExtBlocksSheet();
        return;
    }
  }

  Future<void> _showExtBlocksSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: context.cs.surfaceContainerHigh,
      isScrollControlled: true,
      builder: (_) => const ExtBlocksSettingsSheet(),
    );
  }

  Future<void> _showMemoryBooks() async {
    final session = ref.read(chatProvider(widget.charId)).value?.session;
    if (session == null) return;
    await GlazeBottomSheet.show<void>(
      context,
      child: MemoryBooksSheet(sessionId: session.id, charId: widget.charId),
    );
  }

  Future<void> _showStatsSheet() async {
    widget.onClose?.call();
    if (!mounted) return;
    await showModalBottomSheet<void>(
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
    await GlazeBottomSheet.show<void>(
      context,
      title: 'history_title'.tr(),
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
      title: 'action_new_session'.tr(),
      items: [
        BottomSheetItem(
          icon: Icons.add_circle_outline,
          label: 'action_new_session'.tr(),
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
          label: 'action_export_chat'.tr(),
          onTap: () => Navigator.of(context).pop('export'),
        ),
        BottomSheetItem(
          icon: Icons.drive_file_rename_outline,
          label: 'action_rename'.tr(),
          onTap: () => Navigator.of(context).pop('rename'),
        ),
        BottomSheetItem(
          icon: Icons.delete_outline,
          label: 'action_delete'.tr(),
          isDestructive: true,
          onTap: () => Navigator.of(context).pop('delete'),
        ),
      ],
    ).then((result) async {
      if (!mounted) return;
      switch (result) {
        case 'export':
          await ref
              .read(chatActionsServiceProvider)
              .exportSessionUI(
                context,
                charId: widget.charId,
                sessionId: sessionId,
              );
        case 'rename':
          await _showRenameDialog(sessionId);
        case 'delete':
          await ref.read(chatHistoryProvider.notifier).deleteSession(sessionId);
          ref.invalidate(chatProvider(widget.charId));
      }
    });
  }

  Future<void> _showRenameDialog(String sessionId) async {
    final session = await ref
        .read(chatSessionOpsProvider.notifier)
        .getSession(sessionId);
    if (!mounted || session == null) return;
    final currentName = session.sessionVars['sessionName']?.isNotEmpty == true
        ? session.sessionVars['sessionName']!
        : 'Session #${session.sessionIndex + 1}';
    await GlazeBottomSheet.show<void>(
      context,
      title: 'Rename Session',
      input: BottomSheetInput(
        placeholder: 'Session name',
        value: currentName,
        confirmLabel: 'action_rename'.tr(),
        onConfirm: (val) async {
          Navigator.of(context, rootNavigator: true).pop();
          if (val.trim().isNotEmpty) {
            await ref
                .read(chatHistoryProvider.notifier)
                .renameSession(sessionId, val.trim());
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
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final filePath = file.path;
    try {
      ChatImportSaveResult saveResult;
      if (file.bytes != null) {
        final importResult = importChatFromJsonlString(
          utf8.decode(file.bytes!),
        );
        saveResult = await ref
            .read(chatActionsServiceProvider)
            .importChatFromResult(widget.charId, importResult);
      } else if (filePath != null) {
        saveResult = await ref
            .read(chatActionsServiceProvider)
            .importChat(widget.charId, filePath);
      } else {
        return;
      }
      if (!mounted) return;
      final count = saveResult.count;
      final sessionIndex = saveResult.sessionIndex;
      if (count > 0 && sessionIndex != null) {
        // Pop the sessions sheet if import succeeds
        Navigator.of(context).pop();
        context.go('/chat/${widget.charId}?session=$sessionIndex');
      }
      GlazeToast.show(
        context,
        count == 0 ? 'No messages found in file' : 'Imported $count messages',
      );
    } catch (e) {
      if (mounted) GlazeErrorDialog.show(context, e, prefix: 'Import failed: ');
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
    // Summary is written straight to its repo (not through chatProvider), so
    // refresh the card when it changes.
    ref.listen(summaryRevisionProvider, (prev, next) {
      if (prev != next) _scheduleRefresh();
    });
    ref.listen(activePersonaIdProvider, (prev, next) {
      if (prev != next) _scheduleRefresh();
    });
    ref.listen(lorebookActivationsProvider, (prev, next) {
      if (prev != next) _scheduleRefresh();
    });
    ref.listen(extensionsSettingsProvider, (prev, next) {
      if (prev == null) {
        _scheduleRefresh();
        return;
      }
      if (prev.enabled != next.enabled ||
          prev.activePresetId != next.activePresetId) {
        _scheduleRefresh();
      }
    });
    ref.listen(extensionPresetsProvider, (prev, next) {
      // Active preset name may have changed (renamed/edited).
      final pl = prev ?? const [];
      if (pl.length != next.length) {
        _scheduleRefresh();
      } else {
        for (int i = 0; i < pl.length; i++) {
          if (pl[i].name != next[i].name) {
            _scheduleRefresh();
            break;
          }
        }
      }
    });

    final extSettings = ref.watch(extensionsSettingsProvider);
    final extPresets = ref.watch(extensionPresetsProvider);
    final items = _displayItems(extSettings, extPresets);
    final batterySaver =
        ref.watch(appSettingsProvider).value?.batterySaver ?? false;

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

    return DrawerPanelScaffold(
      disableEffects: batterySaver || widget.disableEffects,
      loading: _loading,
      header: MagicDrawerHeader(
        editing: _editing,
        onToggleEditing: _toggleEditing,
      ),
      content: scrollable,
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
    return formatRelativeTimeFromSeconds(updatedAtSeconds);
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
                  : 'session_name'.tr(namedArgs: {'id': (session.sessionIndex + 1).toString()}),
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
