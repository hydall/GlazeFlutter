import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/llm/prompt_isolate.dart';
import '../../../core/llm/prompt_payload_builder.dart';
import '../../../core/llm/summary_service.dart';
import '../../../core/state/active_selection_provider.dart';
import '../../../core/state/db_provider.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/glaze_bottom_sheet.dart';
import '../../image_gen/image_gen_provider.dart';
import '../../image_gen/widgets/image_gen_sheet.dart';
import '../chat_provider.dart';
import '../../presets/preset_list_screen.dart';
import 'lorebook_coverage_sheet.dart';
import 'magic_drawer_models.dart';
import 'magic_drawer_widgets.dart';
import 'memory_books_sheet.dart';
import 'prompt_preview_screen.dart';
import 'tokenizer_sheet.dart';

void showMagicDrawer(BuildContext context, String charId) {
  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    isScrollControlled: true,
    builder: (_) => MagicDrawerPanel(charId: charId),
  );
}

class MagicDrawerPanel extends ConsumerStatefulWidget {
  final String charId;

  const MagicDrawerPanel({super.key, required this.charId});

  @override
  ConsumerState<MagicDrawerPanel> createState() => _MagicDrawerPanelState();
}

class _MagicDrawerPanelState extends ConsumerState<MagicDrawerPanel> {
  static const _itemsKey = 'magic_drawer_items';
  static const _deletedItemsKey = 'magic_drawer_deleted_items';

  static const _allItems = <MagicDrawerItemDef>[
    MagicDrawerItemDef(id: 'context', label: 'Tokenizer', icon: Icons.segment),
    MagicDrawerItemDef(
      id: 'summary',
      label: 'Summary',
      icon: Icons.summarize_outlined,
    ),
    MagicDrawerItemDef(id: 'sessions', label: 'Sessions', icon: Icons.history),
    MagicDrawerItemDef(
      id: 'stats',
      label: 'Stats',
      icon: Icons.bar_chart_rounded,
    ),
    MagicDrawerItemDef(
      id: 'char-card',
      label: 'Character',
      icon: Icons.badge_outlined,
    ),
    MagicDrawerItemDef(
      id: 'lorebooks',
      label: 'Lorebooks',
      icon: Icons.menu_book_outlined,
    ),
    MagicDrawerItemDef(
      id: 'memory-books',
      label: 'Memory Books',
      icon: Icons.auto_stories_outlined,
    ),
    MagicDrawerItemDef(id: 'regex', label: 'Regex', icon: Icons.code),
    MagicDrawerItemDef(id: 'api', label: 'API', icon: Icons.api_outlined),
    MagicDrawerItemDef(id: 'presets', label: 'Presets', icon: Icons.tune),
    MagicDrawerItemDef(
      id: 'preview',
      label: 'Request Preview',
      icon: Icons.visibility_outlined,
    ),
    MagicDrawerItemDef(id: 'coverage', label: 'Coverage', icon: Icons.search),
    MagicDrawerItemDef(
      id: 'personas',
      label: 'Personas',
      icon: Icons.face_retouching_natural_outlined,
    ),
    MagicDrawerItemDef(
      id: 'image-gen',
      label: 'Image Gen',
      icon: Icons.image_outlined,
    ),
  ];

  final List<String> _itemIds = [];
  final Set<String> _deletedIds = {};
  bool _editing = false;
  bool _loading = true;
  int? _draggingIndex;
  int? _hoverIndex;
  MagicDrawerStats _stats = const MagicDrawerStats();

  @override
  void initState() {
    super.initState();
    _loadDrawer();
  }

  Future<void> _loadDrawer() async {
    await _loadLayout();
    await _loadStats();
    if (mounted) {
      setState(() => _loading = false);
    }
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
    if (!mounted) return;
    final chatState = ref.read(chatProvider(widget.charId)).value;
    final session = chatState?.session;
    final charRepo = ref.read(characterRepoProvider);
    final presetRepo = ref.read(presetRepoProvider);
    final personaRepo = ref.read(personaRepoProvider);
    final apiRepo = ref.read(apiConfigRepoProvider);
    final lorebookRepo = ref.read(lorebookRepoProvider);
    final memoryRepo = ref.read(memoryBookRepoProvider);

    final character = await charRepo.getById(widget.charId);
    if (!mounted) return;
    final presets = await presetRepo.getAll();
    if (!mounted) return;
    final personas = await personaRepo.getAll();
    if (!mounted) return;
    final apiConfigs = await apiRepo.getAll();
    if (!mounted) return;
    final lorebooks = await lorebookRepo.getAll();
    if (!mounted) return;
    final activePresetId = ref.read(activePresetIdProvider);
    final activePersonaId = ref.read(activePersonaIdProvider);
    final activePreset = activePresetId != null
        ? presets.where((p) => p.id == activePresetId).firstOrNull
        : presets.firstOrNull;
    final activePersona = activePersonaId != null
        ? personas.where((p) => p.id == activePersonaId).firstOrNull
        : personas.firstOrNull;
    final chatApi = apiConfigs
        .where((cfg) => cfg.mode != 'embedding')
        .firstOrNull;
    final regexes = await ref.read(activeRegexesProvider.future);
    if (!mounted) return;

    var summaryChars = 0;
    var memoryEntries = 0;
    var sessionCount = 0;
    var messageCount = 0;
    var promptTokens = 0;
    var contextSize = 0;
    var characterTokens = 0;
    var presetTokens = 0;
    var personaTokens = 0;
    var summaryTokens = 0;

    if (session != null) {
      final summary = await ref
          .read(summaryServiceProvider)
          .getSummary(session.id);
      if (!mounted) return;
      summaryChars = summary?.length ?? 0;
      final memoryBook = await memoryRepo.getBySessionId(session.id);
      memoryEntries = memoryBook?.entries.length ?? 0;
      sessionCount =
          (await ref.read(chatRepoProvider).getByCharacterId(widget.charId))
              .length;
      if (!mounted) return;
      messageCount = session.messages.length;

      if (character != null && chatApi != null) {
        try {
          final builder = ref.read(promptPayloadBuilderProvider);
          final payload = await builder.buildFromSession(charId: widget.charId, session: session);
          if (!mounted) return;
          final promptResult = await buildPromptInIsolate(payload);
          if (!mounted) return;
          final sourceTokens = promptResult.breakdown.sourceTokens;
          promptTokens = promptResult.breakdown.totalTokens;
          contextSize = chatApi.contextSize;
          characterTokens = sourceTokens['character'] ?? 0;
          presetTokens = sourceTokens['preset'] ?? 0;
          personaTokens = sourceTokens['persona'] ?? 0;
          summaryTokens = sourceTokens['summary'] ?? 0;
        } catch (_) {}
      }
    }

    final lorebookEntryCount = lorebooks.fold<int>(
      0,
      (sum, lorebook) => sum + lorebook.entries.length,
    );

    bool imageGenEnabled = false;
    try {
      imageGenEnabled = ref.read(imageGenSettingsProvider).value?.enabled == true;
    } catch (_) {}

    _stats = MagicDrawerStats(
      character: character,
      activePreset: activePreset,
      activePersona: activePersona,
      apiConfig: chatApi,
      session: session,
      sessionCount: sessionCount,
      messageCount: messageCount,
      lorebookEntryCount: lorebookEntryCount,
      memoryEntryCount: memoryEntries,
      regexCount: regexes.length,
      summaryChars: summaryChars,
      promptTokens: promptTokens,
      contextSize: contextSize,
      characterTokens: characterTokens,
      presetTokens: presetTokens,
      personaTokens: personaTokens,
      summaryTokens: summaryTokens,
      imageGenEnabled: imageGenEnabled,
    );
  }

  bool _isKnownItem(String id) => _allItems.any((item) => item.id == id);

  List<MagicDrawerCardItem> get _displayItems {
    final list = _itemIds
        .map((id) => _allItems.where((item) => item.id == id).firstOrNull)
        .whereType<MagicDrawerItemDef>()
        .map(
          (def) => MagicDrawerCardItem(def: def, status: _statusFor(def.id)),
        )
        .toList();
    if (_editing && _canAddMore) {
      list.add(
        const MagicDrawerCardItem(
          def: MagicDrawerItemDef(
            id: 'add-btn',
            label: 'Add',
            icon: Icons.add,
          ),
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
        _stats.promptTokens > 0 ? '${_stats.promptTokens} tokens' : null,
      'coverage' =>
        _stats.lorebookEntryCount > 0
            ? '${_stats.lorebookEntryCount} entries'
            : null,
      'personas' => _stats.activePersona?.name ?? 'Default',
      'image-gen' => _stats.imageGenEnabled ? 'On' : 'Off',
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
        Navigator.of(context).pop();
        if (mounted) context.go('/character/${widget.charId}');
        return;
      case 'lorebooks':
        Navigator.of(context).pop();
        if (mounted) context.go('/tools/lorebooks');
        return;
      case 'memory-books':
        await _showMemoryBooks();
        return;
      case 'regex':
        Navigator.of(context).pop();
        if (mounted) context.go('/tools/regex');
        return;
      case 'api':
        Navigator.of(context).pop();
        if (mounted) context.go('/tools/api');
        return;
      case 'presets':
        Navigator.of(context).pop();
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
        Navigator.of(context).pop();
        if (mounted) context.go('/tools/personas');
        return;
      case 'image-gen':
        Navigator.of(context).pop();
        GlazeBottomSheet.show(context, child: const ImageGenSheet());
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
    Navigator.of(context).pop();
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
      child: MemoryBooksSheet(sessionId: session.id),
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

    await GlazeBottomSheet.show(
      context,
      title: 'Chat Stats',
      items: [
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
      ],
    );
  }

  Future<void> _showSessionsSheet() async {
    final currentSession = ref.read(chatProvider(widget.charId)).value?.session;
    if (currentSession == null) return;
    final sessions = await ref
        .read(chatProvider(widget.charId).notifier)
        .getSessions();

    if (!mounted) return;
    await GlazeBottomSheet.show(
      context,
      title: 'Sessions',
      headerAction: currentSession.messages.isEmpty
          ? null
          : IconButton(
              icon: const Icon(Icons.add, color: AppColors.accent),
              onPressed: () async {
                Navigator.of(context).pop();
                await ref
                    .read(chatProvider(widget.charId).notifier)
                    .branchSession(currentSession.messages.length - 1);
              },
            ),
      sessionItems: sessions
          .map(
            (session) => BottomSheetSessionItem(
              title: 'Session #${session.sessionIndex}',
              count: session.messages.length,
              time: session.updatedAt == 0
                  ? ''
                  : _formatRelativeTime(session.updatedAt),
              preview:
                  session.messages.lastOrNull?.content ?? 'No messages yet',
              isActive: session.id == currentSession.id,
              onTap: () {
                Navigator.of(context).pop();
                if (session.sessionIndex != currentSession.sessionIndex) {
                  ref
                      .read(chatProvider(widget.charId).notifier)
                      .switchSession(session.sessionIndex);
                }
              },
              onDelete: () async {
                await ref.read(chatRepoProvider).delete(session.id);
                ref.invalidate(chatProvider(widget.charId));
                if (!mounted) return;
                Navigator.of(context).pop();
              },
            ),
          )
          .toList(),
    );
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
    final panelHeight = math.min(
      MediaQuery.of(context).size.height * 0.54,
      430.0,
    );
    final items = _displayItems;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: panelHeight,
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E).withValues(alpha: 0.8),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: const Border(top: BorderSide(color: AppColors.glassBorder)),
          ),
          child: Stack(
        children: [
          Positioned.fill(
            child: GridView.builder(
              padding: EdgeInsets.fromLTRB(
                12,
                60,
                12,
                16 + MediaQuery.of(context).padding.bottom,
              ),
              itemCount: items.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 6,
                mainAxisSpacing: 8,
                mainAxisExtent: 60,
              ),
              itemBuilder: (context, index) {
                final item = items[index];
                if (item.isAddButton) {
                  return AddMagicCard(onTap: _showAddItemSheet);
                }
                return DragTarget<int>(
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
                    final card = MagicCard(
                      item: item,
                      editing: _editing,
                      hovered: _hoverIndex == index && _draggingIndex != index,
                      onTap: () => _handleTap(item.def),
                      onDelete: () => _removeItem(item.def.id),
                      onLongPress: () {
                        if (!_editing) {
                          HapticFeedback.mediumImpact();
                          setState(() => _editing = true);
                        }
                      },
                    );

                    if (!_editing) {
                      return card;
                    }

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
                        width: (MediaQuery.of(context).size.width - 32) / 3,
                        child: Material(
                          color: Colors.transparent,
                          child: Opacity(opacity: 0.92, child: card),
                        ),
                      ),
                      childWhenDragging: Opacity(opacity: 0.25, child: card),
                      child: card,
                    );
                  },
                );
              },
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Container(
                height: 96,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xEB141416),
                      Color(0x88141416),
                      Color(0x00141416),
                    ],
                    stops: [0.0, 0.55, 1.0],
                  ),
                ),
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
        ),
      ),
    );
  }
}
