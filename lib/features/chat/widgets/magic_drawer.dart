import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/llm/memory_injection_service.dart';
import '../../../core/llm/prompt_builder.dart';
import '../../../core/llm/prompt_isolate.dart';
import '../../../core/llm/summary_service.dart';
import '../../../core/models/api_config.dart';
import '../../../core/models/character.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/preset.dart';
import '../../../core/models/persona.dart';
import '../../../core/state/active_selection_provider.dart';
import '../../../core/state/db_provider.dart';
import '../../../core/state/lorebook_provider.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/glaze_bottom_sheet.dart';
import '../../image_gen/image_gen_provider.dart';
import '../../image_gen/widgets/image_gen_sheet.dart';
import '../chat_provider.dart';
import 'lorebook_coverage_sheet.dart';
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

  static const _allItems = <_MagicDrawerItemDef>[
    _MagicDrawerItemDef(id: 'context', label: 'Tokenizer', icon: Icons.segment),
    _MagicDrawerItemDef(
      id: 'summary',
      label: 'Summary',
      icon: Icons.summarize_outlined,
    ),
    _MagicDrawerItemDef(id: 'sessions', label: 'Sessions', icon: Icons.history),
    _MagicDrawerItemDef(
      id: 'stats',
      label: 'Stats',
      icon: Icons.bar_chart_rounded,
    ),
    _MagicDrawerItemDef(
      id: 'char-card',
      label: 'Character',
      icon: Icons.badge_outlined,
    ),
    _MagicDrawerItemDef(
      id: 'lorebooks',
      label: 'Lorebooks',
      icon: Icons.menu_book_outlined,
    ),
    _MagicDrawerItemDef(
      id: 'memory-books',
      label: 'Memory Books',
      icon: Icons.auto_stories_outlined,
    ),
    _MagicDrawerItemDef(id: 'regex', label: 'Regex', icon: Icons.code),
    _MagicDrawerItemDef(id: 'api', label: 'API', icon: Icons.api_outlined),
    _MagicDrawerItemDef(id: 'presets', label: 'Presets', icon: Icons.tune),
    _MagicDrawerItemDef(
      id: 'preview',
      label: 'Request Preview',
      icon: Icons.visibility_outlined,
    ),
    _MagicDrawerItemDef(id: 'coverage', label: 'Coverage', icon: Icons.search),
    _MagicDrawerItemDef(
      id: 'personas',
      label: 'Personas',
      icon: Icons.face_retouching_natural_outlined,
    ),
    _MagicDrawerItemDef(
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
  _MagicDrawerStats _stats = const _MagicDrawerStats();

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
    final chatState = ref.read(chatProvider(widget.charId)).value;
    final session = chatState?.session;
    final charRepo = ref.read(characterRepoProvider);
    final presetRepo = ref.read(presetRepoProvider);
    final personaRepo = ref.read(personaRepoProvider);
    final apiRepo = ref.read(apiConfigRepoProvider);
    final lorebookRepo = ref.read(lorebookRepoProvider);
    final memoryRepo = ref.read(memoryBookRepoProvider);

    final character = await charRepo.getById(widget.charId);
    final presets = await presetRepo.getAll();
    final personas = await personaRepo.getAll();
    final apiConfigs = await apiRepo.getAll();
    final lorebooks = await lorebookRepo.getAll();
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
      summaryChars = summary?.length ?? 0;
      final memoryBook = await memoryRepo.getBySessionId(session.id);
      memoryEntries = memoryBook?.entries.length ?? 0;
      sessionCount =
          (await ref.read(chatRepoProvider).getByCharacterId(widget.charId))
              .length;
      messageCount = session.messages.length;

      if (character != null && chatApi != null) {
        final memoryResult = await _buildMemoryInjection(session);
        final promptResult = await buildPromptInIsolate(
          PromptPayload(
            character: character,
            persona: activePersona,
            preset: activePreset,
            history: session.messages,
            apiConfig: chatApi,
            sessionVars: session.sessionVars,
            globalVars: ref.read(globalVarsProvider),
            lorebooks: lorebooks,
            lorebookSettings: ref.read(lorebookSettingsProvider),
            lorebookActivations: ref.read(lorebookActivationsProvider),
            summaryContent: summary,
            memoryContent: memoryResult.content.isNotEmpty
                ? memoryResult.content
                : null,
            memoryInjectionTarget: memoryResult.injectionTarget,
          ),
        );
        final sourceTokens = promptResult.breakdown.sourceTokens;
        promptTokens = promptResult.breakdown.totalTokens;
        contextSize = chatApi.contextSize;
        characterTokens = sourceTokens['character'] ?? 0;
        presetTokens = sourceTokens['preset'] ?? 0;
        personaTokens = sourceTokens['persona'] ?? 0;
        summaryTokens = sourceTokens['summary'] ?? 0;
      }
    }

    final lorebookEntryCount = lorebooks.fold<int>(
      0,
      (sum, lorebook) => sum + lorebook.entries.length,
    );

    _stats = _MagicDrawerStats(
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
      imageGenEnabled:
          ref.read(imageGenSettingsProvider).value?.enabled == true,
    );
  }

  Future<MemoryInjectionResult> _buildMemoryInjection(ChatSession session) {
    final historyText = session.messages
        .where((m) => m.role == 'user' || m.role == 'assistant')
        .map((m) => m.content)
        .join('\n');
    return ref
        .read(memoryInjectionServiceProvider)
        .buildInjection(
          sessionId: session.id,
          historyText: historyText,
          messageCount: session.messages.length,
        );
  }

  bool _isKnownItem(String id) => _allItems.any((item) => item.id == id);

  List<_MagicDrawerCardItem> get _displayItems {
    final list = _itemIds
        .map((id) => _allItems.where((item) => item.id == id).firstOrNull)
        .whereType<_MagicDrawerItemDef>()
        .map(
          (def) => _MagicDrawerCardItem(def: def, status: _statusFor(def.id)),
        )
        .toList();
    if (_editing && _canAddMore) {
      list.add(
        const _MagicDrawerCardItem(
          def: _MagicDrawerItemDef(
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

  Future<void> _handleTap(_MagicDrawerItemDef item) async {
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
        if (mounted) context.go('/tools/presets');
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
                  return _AddMagicCard(onTap: _showAddItemSheet);
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
                    final card = _MagicCard(
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
            child: _DrawerHeader(
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

class _DrawerHeader extends StatelessWidget {
  final bool editing;
  final VoidCallback onToggleEditing;

  const _DrawerHeader({required this.editing, required this.onToggleEditing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            'Quick Access',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -0.2,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onToggleEditing,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: editing
                    ? AppColors.accent.withValues(alpha: 0.22)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(17),
                border: Border.all(
                  color: editing
                      ? AppColors.accent.withValues(alpha: 0.38)
                      : Colors.white.withValues(alpha: 0.18),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    editing ? Icons.check : Icons.edit,
                    size: 16,
                    color: editing ? AppColors.accent : AppColors.textPrimary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    editing ? 'Done' : 'Edit',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color:
                          editing ? AppColors.accent : AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MagicCard extends StatefulWidget {
  final _MagicDrawerCardItem item;
  final bool editing;
  final bool hovered;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onLongPress;

  const _MagicCard({
    required this.item,
    required this.editing,
    required this.hovered,
    required this.onTap,
    required this.onDelete,
    required this.onLongPress,
  });

  @override
  State<_MagicCard> createState() => _MagicCardState();
}

class _MagicCardState extends State<_MagicCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final editing = widget.editing;
    final hovered = widget.hovered;

    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : (hovered ? 1.02 : 1.0),
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Container(
          // Outer container carries the glow shadow so it isn't clipped
          decoration: hovered
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.35),
                      blurRadius: 14,
                    ),
                  ],
                )
              : null,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                constraints: const BoxConstraints.expand(),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(
                    alpha: _pressed || hovered ? 0.08 : 0.04,
                  ),
                  border: Border.all(
                    color: editing
                        ? AppColors.accent.withValues(alpha: 0.55)
                        : Colors.white.withValues(alpha: 0.06),
                  ),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            item.def.icon,
                            size: 16,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                item.def.label,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                  height: 1,
                                ),
                              ),
                              if (item.status != null) ...[
                                const SizedBox(height: 1),
                                Text(
                                  item.status!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: AppColors.textSecondary.withValues(
                                      alpha: 0.95,
                                    ),
                                    height: 1,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (editing)
                      Positioned(
                        top: -8,
                        right: -8,
                        child: GestureDetector(
                          onTap: widget.onDelete,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: const BoxDecoration(
                              color: Color(0xFFFF3B30),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Color(0x4DFF3B30),
                                  blurRadius: 8,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.close,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AddMagicCard extends StatelessWidget {
  final VoidCallback onTap;

  const _AddMagicCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            constraints: const BoxConstraints.expand(),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.add,
                    size: 16,
                    color: AppColors.textPrimary.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Add',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      height: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MagicDrawerItemDef {
  final String id;
  final String label;
  final IconData icon;

  const _MagicDrawerItemDef({
    required this.id,
    required this.label,
    required this.icon,
  });
}

class _MagicDrawerCardItem {
  final _MagicDrawerItemDef def;
  final String? status;
  final bool isAddButton;

  const _MagicDrawerCardItem({
    required this.def,
    this.status,
    this.isAddButton = false,
  });
}

class _MagicDrawerStats {
  final Character? character;
  final Preset? activePreset;
  final Persona? activePersona;
  final ApiConfig? apiConfig;
  final ChatSession? session;
  final int sessionCount;
  final int messageCount;
  final int lorebookEntryCount;
  final int memoryEntryCount;
  final int regexCount;
  final int summaryChars;
  final int promptTokens;
  final int contextSize;
  final int characterTokens;
  final int presetTokens;
  final int personaTokens;
  final int summaryTokens;
  final bool imageGenEnabled;

  const _MagicDrawerStats({
    this.character,
    this.activePreset,
    this.activePersona,
    this.apiConfig,
    this.session,
    this.sessionCount = 0,
    this.messageCount = 0,
    this.lorebookEntryCount = 0,
    this.memoryEntryCount = 0,
    this.regexCount = 0,
    this.summaryChars = 0,
    this.promptTokens = 0,
    this.contextSize = 0,
    this.characterTokens = 0,
    this.presetTokens = 0,
    this.personaTokens = 0,
    this.summaryTokens = 0,
    this.imageGenEnabled = false,
  });
}
