import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gradient_blur/gradient_blur.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/llm/summary_service.dart';
import '../../../core/models/lorebook.dart';
import '../../../core/services/chat_import_export.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/state/db_provider.dart';
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
import 'lorebook_coverage_sheet.dart';
import 'magic_drawer_models.dart';
import 'magic_drawer_stats_service.dart';
import 'magic_drawer_widgets.dart';
import 'memory_books_sheet.dart';
import 'prompt_preview_screen.dart';
import 'tokenizer_sheet.dart';

class MagicDrawerPanel extends ConsumerStatefulWidget {
  final String charId;

  /// Called when the drawer wants to dismiss itself (e.g. after the user picks
  /// an item that opens another screen). The host owns visibility, so we ask
  /// it to hide us instead of popping a route.
  final VoidCallback? onClose;

  const MagicDrawerPanel({
    super.key,
    required this.charId,
    this.onClose,
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

  @override
  void initState() {
    super.initState();
    _loadDrawer();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDrawer() async {
    await _loadLayout();
    await _loadStats();
    if (mounted) {
      setState(() => _loading = false);
    }
    _loadTokenStats();
  }

  Future<void> _loadLayout() async {
    final prefs = await SharedPreferences.getInstance();
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_itemsKey, List<String>.from(_itemIds));
    await prefs.setStringList(_deletedItemsKey, _deletedIds.toList());
  }

  Future<void> _loadStats() async {
    _stats = await MagicDrawerStatsService(ref).computeStats(widget.charId);
  }

  Future<void> _loadTokenStats() async {
    if (!mounted) return;
    setState(() => _loadingTokens = true);
    final updated = await MagicDrawerStatsService(ref).computeTokenStats(widget.charId, _stats);
    if (!mounted) return;
    setState(() {
      _stats = updated;
      _loadingTokens = false;
    });
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
            : _loadingTokens ? 'Calculating...' : null,
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
        _stats.promptTokens > 0 ? '${_stats.promptTokens} tokens' : _loadingTokens ? 'Calculating...' : null,
      'coverage' =>
        _stats.lorebookEntryCount > 0
            ? '${_stats.lorebookEntryCount} entries'
            : null,
      'personas' => _stats.activePersona?.name ?? 'Default',
      'image-gen' => _stats.imageGenEnabled ? 'On' : 'Off',
      'authors-note' =>
        _stats.session?.authorsNote != null && _stats.session!.authorsNote!.content.isNotEmpty
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
      if (from < to) to -= 1;
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

    await GlazeBottomSheet.show(
      context,
      title: 'Add Action',
      items: available
          .map(
            (item) => BottomSheetItem(
              icon: item.icon,
              label: item.label,
              onTap: () async {
                Navigator.of(context).pop();
                setState(() {
                  _itemIds.add(item.id);
                  _deletedIds.remove(item.id);
                });
                await _saveLayout();
              },
            ),
          )
          .toList(),
    );
  }

  Future<void> _handleTap(MagicDrawerItemDef item) async {
    if (_editing) return;

    switch (item.id) {
      case 'context':
        showTokenizerSheet(context, widget.charId);
        return;
      case 'summary':
        await _generateSummary();
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
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            backgroundColor: Colors.transparent,
            builder: (_) => CharacterDetailScreen(charId: widget.charId),
          );
        }
        return;
      case 'lorebooks':
        await _showLorebooksSheet();
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
        GlazeBottomSheet.show(context, child: const ImageGenSheet());
        return;
      case 'authors-note':
        showAuthorsNoteSheet(context, widget.charId);
        return;
    }
  }

  Future<void> _generateSummary() async {
    final chatState = ref.read(chatProvider(widget.charId)).value;
    final session = chatState?.session;
    if (session == null) return;
    final apiConfigs = await ref.read(apiConfigRepoProvider).getAll();
    final chatApi = apiConfigs
        .where((cfg) => cfg.mode != 'embedding')
        .firstOrNull;
    if (chatApi == null) {
      if (mounted) {
        GlazeBottomSheet.show(
          context,
          title: 'Summary',
          bigInfo: const BottomSheetBigInfo(
            icon: Icons.api_outlined,
            description:
                'No chat API config found. Add one in API Settings first.',
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    widget.onClose?.call();
    try {
      final summary = await ref
          .read(summaryServiceProvider)
          .generateSummary(
            sessionId: session.id,
            history: session.messages,
            apiConfig: chatApi,
          );
      if (!mounted) return;
      await GlazeBottomSheet.show(
        context,
        title: 'Summary',
        bigInfo: BottomSheetBigInfo(
          icon: Icons.summarize_outlined,
          description: 'Generated summary (${summary.length} chars).',
          buttonText: 'OK',
          onButtonTap: () => Navigator.of(context).pop(),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      await GlazeBottomSheet.show(
        context,
        title: 'Summary Failed',
        bigInfo: BottomSheetBigInfo(
          icon: Icons.error_outline,
          description: e.toString(),
          buttonText: 'Close',
          onButtonTap: () => Navigator.of(context).pop(),
        ),
      );
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

  Future<void> _showLorebooksSheet() async {
    final lorebooks = await ref.read(lorebookRepoProvider).getAll();
    if (!mounted) return;
    if (lorebooks.isEmpty) {
      GlazeBottomSheet.show(
        context,
        title: 'Lorebooks',
        bigInfo: const BottomSheetBigInfo(
          icon: Icons.menu_book_outlined,
          description:
              'No lorebooks yet. Import a backup or create one in Tools.',
        ),
      );
      return;
    }
    GlazeBottomSheet.show(
      context,
      title: 'Lorebooks',
      items: lorebooks
          .map(
            (lb) => BottomSheetItem(
              icon: lb.enabled ? Icons.menu_book : Icons.menu_book_outlined,
              label: lb.name,
              hint: '${lb.entries.length} entries · ${lb.activationScope}',
              onTap: () {
                Navigator.of(context, rootNavigator: true).pop();
                _showLorebookEntries(lb);
              },
            ),
          )
          .toList(),
    );
  }

  void _showLorebookEntries(Lorebook lb) {
    final entries = lb.entries;
    if (entries.isEmpty) {
      GlazeBottomSheet.show(
        context,
        title: lb.name,
        bigInfo: BottomSheetBigInfo(
          icon: Icons.menu_book_outlined,
          description: 'No entries in ${lb.name}',
          buttonText: 'Open Editor',
          onButtonTap: () {
            Navigator.of(context).pop();
            widget.onClose?.call();
            context.go('/tools/lorebooks');
          },
        ),
      );
      return;
    }
    GlazeBottomSheet.show(
      context,
      title: lb.name,
      items: entries
          .take(20)
          .map(
            (e) => BottomSheetItem(
              icon: e.enabled ? Icons.description : Icons.description_outlined,
              label: e.comment.isNotEmpty ? e.comment : e.keys.join(', '),
              hint: e.constant
                  ? 'constant'
                  : (e.keys.isNotEmpty ? e.keys.first : ''),
              onTap: () {},
            ),
          )
          .toList(),
    );
  }

  Future<void> _showStatsSheet() async {
    final session = ref.read(chatProvider(widget.charId)).value?.session;
    if (session == null) return;

    final visibleMessages = session.messages.where((m) => !m.isHidden).length;
    final hiddenMessages = session.messages.where((m) => m.isHidden).length;
    final userMessages = session.messages.where((m) => m.role == 'user').length;
    final assistantMessages = session.messages
        .where((m) => m.role == 'assistant')
        .length;

    String timeSpent = '';
    try {
      final prefs = await SharedPreferences.getInstance();
      final seconds = prefs.getInt('chat_time_${widget.charId}') ?? 0;
      if (seconds >= 3600) {
        timeSpent = '${seconds ~/ 3600}h ${(seconds % 3600) ~/ 60}m';
      } else if (seconds >= 60) {
        timeSpent = '${seconds ~/ 60}m ${seconds % 60}s';
      } else if (seconds > 0) {
        timeSpent = '$seconds s';
      }
    } catch (_) {}

    final items = <BottomSheetItem>[
      BottomSheetItem(
        icon: Icons.chat_bubble_outline,
        label: 'Messages',
        hint: '${session.messages.length} total',
        onTap: () {},
      ),
      BottomSheetItem(
        icon: Icons.visibility_outlined,
        label: 'Visible / Hidden',
        hint: '$visibleMessages visible • $hiddenMessages hidden',
        onTap: () {},
      ),
      BottomSheetItem(
        icon: Icons.swap_vert,
        label: 'User / Assistant',
        hint: '$userMessages user • $assistantMessages assistant',
        onTap: () {},
      ),
      BottomSheetItem(
        icon: Icons.token,
        label: 'Prompt Estimate',
        hint: _stats.promptTokens > 0
            ? '${_stats.promptTokens} tokens'
            : 'Not calculated yet',
        onTap: () {},
      ),
    ];

    if (timeSpent.isNotEmpty) {
      items.add(
        BottomSheetItem(
          icon: Icons.timer_outlined,
          label: 'Time Spent',
          hint: timeSpent,
          onTap: () {},
        ),
      );
    }

    if (!mounted) return;
    await GlazeBottomSheet.show(context, title: 'Chat Stats', items: items);
  }

  Future<void> _showSessionsSheet() async {
    final currentSession = ref.read(chatProvider(widget.charId)).value?.session;
    if (currentSession == null) return;

    if (!mounted) return;
    await GlazeBottomSheet.show(
      context,
      title: 'Sessions',
      headerAction: IconButton(
        icon: const Icon(Icons.add, color: AppColors.accent),
        onPressed: _showSessionAddMenu,
      ),
      child: _SessionsSheetContent(
        charId: widget.charId,
        onSessionActions: _showSessionActions,
      ),
    );
  }

  void _showSessionAddMenu() {
    GlazeBottomSheet.show(
      context,
      title: 'Add Session',
      items: [
        BottomSheetItem(
          icon: Icons.add_circle_outline,
          label: 'New Session',
          onTap: () async {
            Navigator.of(context).pop(); // Pops Add Menu
            Navigator.of(context).pop(); // Pops Sessions Sheet
            await ref.read(chatProvider(widget.charId).notifier).newSession();
          },
        ),
        BottomSheetItem(
          icon: Icons.file_download,
          label: 'Import Chat',
          onTap: () async {
            Navigator.of(context).pop(); // Pops Add Menu
            await _importChat();
          },
        ),
      ],
    );
  }

  void _showSessionActions(String sessionId) {
    GlazeBottomSheet.show(
      context,
      title: 'Session',
      items: [
        BottomSheetItem(
          icon: Icons.upload_file,
          label: 'Export (JSONL)',
          onTap: () async {
            Navigator.of(context).pop(); // Pops Actions Sheet
            await ChatActionsService(ref).exportSessionUI(
              context,
              charId: widget.charId,
              sessionId: sessionId,
            );
          },
        ),
        BottomSheetItem(
          icon: Icons.delete_outline,
          label: 'Delete',
          isDestructive: true,
          onTap: () async {
            Navigator.of(context).pop(); // Pops Actions Sheet
            await ref.read(chatRepoProvider).delete(sessionId);
            ref.invalidate(chatProvider(widget.charId));
          },
        ),
      ],
    );
  }

  Future<void> _importChat() async {
    final result = await FilePicker.pickFiles(
      type: Platform.isIOS ? FileType.any : FileType.custom,
      allowedExtensions: Platform.isIOS ? null : ['jsonl', 'json'],
      allowMultiple: false,
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
        count = await ChatActionsService(ref)
            .importChatFromResult(widget.charId, importResult);
      } else if (filePath != null) {
        count = await ChatActionsService(ref)
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
      final prevSession = prev?.value?.session;
      final nextSession = next.value?.session;
      if (prevSession?.id != nextSession?.id ||
          prevSession?.messages.length != nextSession?.messages.length) {
        _debounceTimer?.cancel();
        _debounceTimer = Timer(const Duration(milliseconds: 300), _loadDrawer);
      }
    });

    final items = _displayItems;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        border: Border(top: BorderSide(color: AppColors.glassBorder)),
      ),
      child: Stack(
          children: [
            Positioned.fill(
              child: RawScrollbar(
                padding: const EdgeInsets.only(top: 60),
                  thickness: 3,
                  radius: const Radius.circular(3),
                  thumbColor: Colors.white24,
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(
                      context,
                    ).copyWith(scrollbars: false),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final itemWidth = (constraints.maxWidth - 24 - 12) / 3;
                        return SingleChildScrollView(
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
                                hovered:
                                    _hoverIndex == index &&
                                    _draggingIndex != index,
                                onTap: () => _handleTap(item.def),
                                onDelete: () => _removeItem(item.def.id),
                                onLongPress: () {
                                  if (!_editing) {
                                    HapticFeedback.mediumImpact();
                                    setState(() => _editing = true);
                                  }
                                },
                              );
                              return SizedBox(
                                width: itemWidth,
                                child: DragTarget<int>(
                                  onWillAcceptWithDetails: (details) {
                                    setState(() => _hoverIndex = index);
                                    return _editing && details.data != index;
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
                                    if (!_editing) return card;
                                    return LongPressDraggable<int>(
                                      data: index,
                                      onDragStarted: () {
                                        HapticFeedback.mediumImpact();
                                        setState(() => _draggingIndex = index);
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
                                          child: Opacity(
                                            opacity: 0.92,
                                            child: card,
                                          ),
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
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: GradientBlur(
                    maxBlur: 8,
                    curve: Curves.easeIn,
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xEB141416),
                        Color(0x88141416),
                        Color(0x00141416),
                      ],
                      stops: [0.0, 0.55, 1.0],
                    ),
                    child: const SizedBox(height: 68),
                  ),
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
  ConsumerState<_SessionsSheetContent> createState() => _SessionsSheetContentState();
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
    final sessions = await ref.read(chatProvider(widget.charId).notifier).getSessions();
    if (mounted) {
      setState(() {
        _sessions = sessions;
        _loading = false;
      });
    }
  }

  String _formatRelativeTime(int updatedAtSeconds) {
    final updated = DateTime.fromMillisecondsSinceEpoch(updatedAtSeconds * 1000);
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

    final currentSession = ref.watch(chatProvider(widget.charId)).value?.session;
    final currentSessionId = currentSession?.id;

    return GlazeSessionList(
      items: _sessions
          .map(
            (session) => BottomSheetSessionItem(
              title: 'Session #${session.sessionIndex}',
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

