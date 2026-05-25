import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'editing_message_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/state/character_provider.dart';
import '../../core/state/active_selection_provider.dart';
import '../../shared/theme/app_colors.dart';
import 'widgets/message_actions.dart';
import '../../shared/theme/theme_font_provider.dart';
import '../../shared/theme/theme_provider.dart';

import '../../shared/widgets/glaze_bottom_sheet.dart';
import '../../shared/widgets/glaze_scaffold.dart';
import '../settings/app_settings_provider.dart';
import 'chat_provider.dart';
import 'chat_state.dart';
import 'widgets/chat_header.dart';
import 'widgets/chat_input_bar.dart';
import '../image_gen/widgets/image_gen_sheet.dart';
import 'widgets/magic_drawer.dart';
import 'widgets/chat_webview_widget.dart';
import '../../core/models/chat_message.dart';
import '../../core/state/db_provider.dart';
import 'widgets/session_lifecycle_tracker.dart';

class SearchMatch {
  final int messageIndex;
  final int matchIndexInMessage;
  const SearchMatch(this.messageIndex, this.matchIndexInMessage);
}

const String _kKeyboardHeightPref = 'chat_last_keyboard_height';
const double _kDefaultKeyboardHeight = 320;

class ChatScreen extends ConsumerStatefulWidget {
  final String charId;
  final int? initialSessionIndex;
  final bool forceNewSession;
  const ChatScreen({
    super.key,
    required this.charId,
    this.initialSessionIndex,
    this.forceNewSession = false,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with SingleTickerProviderStateMixin {
  bool _sessionApplied = false;
  bool _showSearch = false;
  bool _isHeaderHidden = false;
  String _searchQuery = '';
  int _searchCurrentIndex = 0;
  List<SearchMatch> _searchMatches = [];
  final TextEditingController _searchController = TextEditingController();

  // Telegram-style input panel state. The input area swaps between three
  // exclusive bottom-anchored modes: idle, keyboard, drawer.
  final FocusNode _inputFocus = FocusNode();
  bool _drawerOpen = false;
  double _lastKeyboardHeight = _kDefaultKeyboardHeight;

  /// Height frozen at the moment the drawer opens. Passed to _ChatBody so
  /// the Positioned bottom doesn't jitter while the keyboard animates.
  double _activeDrawerHeight = _kDefaultKeyboardHeight;
  late final AnimationController _drawerAnimController;
  late final Animation<double> _drawerAnim;

  /// True while switching from keyboard to drawer. Keeps the input bar up.
  bool _switchingToDrawer = false;

  @override
  void initState() {
    super.initState();
    _drawerAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _drawerAnim = CurvedAnimation(
      parent: _drawerAnimController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _inputFocus.addListener(_onFocusChanged);
    _restoreKeyboardHeight();
    if (widget.forceNewSession || widget.initialSessionIndex != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _applySessionPreference();
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _inputFocus.removeListener(_onFocusChanged);
    _inputFocus.dispose();
    _drawerAnimController.dispose();
    super.dispose();
  }

  double _tempMaxHeight = 0;
  Timer? _heightTimer;

  Future<void> _restoreKeyboardHeight() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getDouble(_kKeyboardHeightPref);
      if (saved != null && saved > 200 && mounted) {
        setState(() => _lastKeyboardHeight = saved);
      }
    } catch (_) {}
  }

  Future<void> _persistKeyboardHeight(double height) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_kKeyboardHeightPref, height);
    } catch (_) {}
  }

  void _onFocusChanged() {
    if (_inputFocus.hasFocus && _drawerOpen) {
      setState(() {
        _drawerOpen = false;
        _activeDrawerHeight = _lastKeyboardHeight;
      });
      _drawerAnimController.reverse();
    }
  }

  void _toggleDrawer() {
    if (_drawerOpen) {
      setState(() => _drawerOpen = false);
      _drawerAnimController.reverse();
    } else {
      HapticFeedback.selectionClick();
      _activeDrawerHeight = _lastKeyboardHeight;

      final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
      if (keyboardHeight > 0 || _inputFocus.hasFocus) {
        setState(() => _switchingToDrawer = true);
        _inputFocus.unfocus();
      } else {
        setState(() => _drawerOpen = true);
        _drawerAnimController.forward();
      }
    }
  }

  void _closeDrawer() {
    if (!_drawerOpen) return;
    setState(() => _drawerOpen = false);
    _drawerAnimController.reverse();
  }

  void _onScrollDirection(ScrollDirection direction) {
    if (direction == ScrollDirection.reverse && !_isHeaderHidden) {
      setState(() => _isHeaderHidden = true);
    } else if (direction == ScrollDirection.forward && _isHeaderHidden) {
      setState(() => _isHeaderHidden = false);
    }
  }

  @override
  void didUpdateWidget(ChatScreen old) {
    super.didUpdateWidget(old);
    if (widget.initialSessionIndex != old.initialSessionIndex ||
        widget.forceNewSession != old.forceNewSession ||
        widget.charId != old.charId) {
      _sessionApplied = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _applySessionPreference();
      });
    }
  }

  Future<void> _applySessionPreference() async {
    if (_sessionApplied) return;
    _sessionApplied = true;
    final notifier = ref.read(chatProvider(widget.charId).notifier);
    if (widget.forceNewSession) {
      unawaited(notifier.createNewSession());
    } else if (widget.initialSessionIndex != null) {
      unawaited(notifier.switchSession(widget.initialSessionIndex!));
    }
  }

  @override
  Widget build(BuildContext context) {
    final charId = widget.charId;
    final chatStateAsync = ref.watch(chatProvider(charId));
    final chatState = chatStateAsync.value;

    final character = ref.watch(characterByIdProvider(charId));
    final title = character?.name ?? 'Chat';
    final sessionName = chatState?.session != null
        ? 'Session #${chatState!.session!.sessionIndex + 1}'
        : 'Loading...';
    final sessionIndex = chatState?.session?.sessionIndex ?? 0;

    final appSettings = ref.watch(appSettingsProvider).valueOrNull;
    final virtualKeyboardSend = appSettings?.virtualKeyboardSend ?? false;
    final enterToSend = appSettings?.enterToSend ?? true;

    // Track the OS keyboard height — record peaks only when stable.
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
    if (keyboardHeight > 200 && _inputFocus.hasFocus) {
      if (keyboardHeight > _tempMaxHeight) {
        _tempMaxHeight = keyboardHeight;
        _heightTimer?.cancel();
        _heightTimer = Timer(const Duration(milliseconds: 300), () {
          if (mounted &&
              _tempMaxHeight > 200 &&
              _tempMaxHeight != _lastKeyboardHeight) {
            setState(() {
              _lastKeyboardHeight = _tempMaxHeight;
              _persistKeyboardHeight(_lastKeyboardHeight);
            });
          }
        });
      }
    }

    if (!_inputFocus.hasFocus && _tempMaxHeight != 0) {
      _tempMaxHeight = 0;
    }

    if (_switchingToDrawer && keyboardHeight == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _switchingToDrawer) {
          setState(() {
            _switchingToDrawer = false;
            _drawerOpen = true;
          });
          _drawerAnimController.forward();
        }
      });
    }

    if (keyboardHeight > 0 && _drawerOpen && !_switchingToDrawer) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _drawerOpen && !_switchingToDrawer) _closeDrawer();
      });
    }

    // Safe area bottom padding is only needed when no panel (keyboard/drawer)
    // is active. When active, they sit at the very bottom above the system nav bar.
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final isIdle =
        keyboardHeight == 0 &&
        !_drawerOpen &&
        !_switchingToDrawer &&
        _drawerAnimController.value == 0;
    final bottomPadding = isIdle ? safeBottom : 0.0;

    // Final (post-animation) inset for layout-only consumers.
    // Animated visual positioning of the input + drawer is driven by
    // _drawerAnim inside _ChatBody so list paddings don't churn each frame.
    final targetDrawerInset = (_drawerOpen || _switchingToDrawer)
        ? _activeDrawerHeight
        : 0.0;
    final targetBottomPanelInset =
        math.max(targetDrawerInset, keyboardHeight) + bottomPadding;

    return SessionLifecycleTracker(
      charId: charId,
      child: PopScope(
        canPop: !_drawerOpen && !_showSearch && !_inputFocus.hasFocus,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          if (_inputFocus.hasFocus) {
            _inputFocus.unfocus();
            return;
          }
          if (_drawerOpen) {
            _closeDrawer();
            return;
          }
          if (_showSearch) {
            _searchController.clear();
            setState(() {
              _showSearch = false;
              _searchQuery = '';
              _searchMatches = [];
              _searchCurrentIndex = 0;
            });
            return;
          }
        },
        child: GlazeScaffold(
          extendBodyBehindHeader: true,
          resizeToAvoidBottomInset: false,
          hideHeader: _isHeaderHidden,
          title: title,
          titleWidget: _showSearch
              ? TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: TextStyle(color: context.cs.onSurface, fontSize: 16),
                  decoration: InputDecoration(
                    hintText: 'Search messages...',
                    hintStyle: TextStyle(
                      color: context.cs.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: Icon(
                              Icons.close,
                              color: context.cs.onSurface,
                              size: 20,
                            ),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                                _searchMatches = [];
                                _searchCurrentIndex = 0;
                              });
                            },
                          )
                        : null,
                  ),
                  onChanged: (q) {
                    final matches = <SearchMatch>[];
                    if (q.isNotEmpty && chatState != null) {
                      final lower = q.toLowerCase();
                      for (int i = 0; i < chatState.messages.length; i++) {
                        var raw = chatState.messages[i].content;
                        if (raw.contains('<think')) {
                          raw = raw.replaceAll(RegExp(r'<think\b[^>]*>[\s\S]*?<\/think\b[^>]*>', caseSensitive: false), '');
                          raw = raw.replaceAll(RegExp(r'<think\b([^>]*?)(?:>|\n)([\s\S]*?)<\/think\b', caseSensitive: false), '');
                        }
                        if (raw.contains('<thinking')) {
                          raw = raw.replaceAll(RegExp(r'<thinking\b[^>]*>[\s\S]*?<\/thinking\b[^>]*>', caseSensitive: false), '');
                          raw = raw.replaceAll(RegExp(r'<thinking\b([^>]*?)(?:>|\n)([\s\S]*?)<\/thinking\b', caseSensitive: false), '');
                        }
                        raw = raw.trim();
                        final content = raw.toLowerCase();
                        
                        final reasoning = chatState.messages[i].reasoning?.toLowerCase() ?? '';
                        
                        int matchIndex = 0;
                        
                        if (reasoning.isNotEmpty) {
                          int startIndex = 0;
                          while (true) {
                            final idx = reasoning.indexOf(lower, startIndex);
                            if (idx == -1) break;
                            matches.add(SearchMatch(i, matchIndex));
                            matchIndex++;
                            startIndex = idx + lower.length;
                          }
                        }
                        
                        int startIndex = 0;
                        while (true) {
                          final idx = content.indexOf(lower, startIndex);
                          if (idx == -1) break;
                          matches.add(SearchMatch(i, matchIndex));
                          matchIndex++;
                          startIndex = idx + lower.length;
                        }
                      }
                    }

                    setState(() {
                      _searchQuery = q;
                      _searchMatches = matches;
                      _searchCurrentIndex = 0;
                    });
                  },
                )
              : (character != null
                    ? ChatHeader(
                        character: character,
                        sessionName: sessionName,
                        currentSessionIndex: sessionIndex,
                      )
                    : null),
          onBack: () {
            if (_showSearch) {
              _searchController.clear();
              setState(() {
                _showSearch = false;
                _searchQuery = '';
                _searchMatches = [];
                _searchCurrentIndex = 0;
              });
            } else {
              context.go('/');
            }
          },
          actions: _showSearch
              ? const []
              : [
                  IconButton(
                    icon: const Icon(Icons.search),
                    color: context.cs.primary,
                    onPressed: () {
                      setState(() {
                        _showSearch = true;
                        _searchQuery = '';
                        _searchMatches = [];
                        _searchCurrentIndex = 0;
                        _searchController.clear();
                      });
                    },
                  ),
                ],
          body: chatStateAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (state) => _ChatBody(
              charId: charId,
              state: state,
              inputFocus: _inputFocus,
              drawerOpen: _drawerOpen,
              isSwitchingToDrawer: _switchingToDrawer,
              drawerHeight: _activeDrawerHeight,
              keyboardHeight: keyboardHeight,
              targetBottomPanelInset: targetBottomPanelInset,
              drawerAnim: _drawerAnim,
              showSearchControls: _showSearch,
              searchQuery: _searchQuery,
              searchMatches: _searchMatches,
              searchCurrentIndex: _searchCurrentIndex,
              onSearchPrev: _searchCurrentIndex > 0
                  ? () => setState(() => _searchCurrentIndex--)
                  : null,
              onSearchNext: _searchCurrentIndex < _searchMatches.length - 1
                  ? () => setState(() => _searchCurrentIndex++)
                  : null,
              onCloseDrawer: _closeDrawer,
              onToggleDrawer: _toggleDrawer,
              onScrollDirection: _onScrollDirection,
              virtualKeyboardSend: virtualKeyboardSend,
              enterToSend: enterToSend,
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatBody extends ConsumerStatefulWidget {
  final String charId;
  final ChatState state;
  final FocusNode inputFocus;
  final bool drawerOpen;
  final bool isSwitchingToDrawer;
  final double drawerHeight;
  final double keyboardHeight;

  /// Final (post-animation) inset for layout-only consumers.
  /// Doesn't churn per frame.
  final double targetBottomPanelInset;

  /// 0..1 progress of the drawer reveal — drives the visual slide and the
  /// input-bar lift each frame.
  final Animation<double> drawerAnim;

  final bool showSearchControls;
  final String searchQuery;
  final List<SearchMatch> searchMatches;
  final int searchCurrentIndex;
  final VoidCallback? onSearchPrev;
  final VoidCallback? onSearchNext;
  final VoidCallback onCloseDrawer;
  final VoidCallback onToggleDrawer;
  final ValueChanged<ScrollDirection>? onScrollDirection;
  final bool virtualKeyboardSend;
  final bool enterToSend;

  const _ChatBody({
    required this.charId,
    required this.state,
    required this.inputFocus,
    required this.drawerOpen,
    required this.isSwitchingToDrawer,
    required this.drawerHeight,
    required this.keyboardHeight,
    required this.targetBottomPanelInset,
    required this.drawerAnim,
    required this.showSearchControls,
    required this.searchQuery,
    required this.searchMatches,
    required this.searchCurrentIndex,
    this.onSearchPrev,
    this.onSearchNext,
    required this.onCloseDrawer,
    required this.onToggleDrawer,
    this.onScrollDirection,
    this.virtualKeyboardSend = false,
    this.enterToSend = true,
  });

  @override
  ConsumerState<_ChatBody> createState() => _ChatBodyState();
}

class _ChatBodyState extends ConsumerState<_ChatBody> {
  double _inputBarHeight = 130.0;
  final GlobalKey _inputBarKey = GlobalKey();

  bool _isSelectionMode = false;
  bool _showScrollToBottom = false;
  Set<String> _selectedMessageIds = {};
  final GlobalKey<ChatWebViewWidgetState> _webViewStateKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkHeight());
  }

  void _checkHeight() {
    if (!mounted) return;
    final ctx = _inputBarKey.currentContext;
    if (ctx != null) {
      final size = ctx.size;
      if (size != null && size.height != _inputBarHeight && size.height > 0) {
        setState(() {
          _inputBarHeight = size.height;
        });
      }
    }
  }

  Future<void> _scrollToBottom() async {
    final webViewState = _webViewStateKey.currentState;
    if (webViewState != null) {
      await webViewState.scrollToBottom();
    }
    if (!mounted) return;
    setState(() => _showScrollToBottom = false);
  }

  void _showImageViewer(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Center(
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Image.file(
                    File(
                      imageUrl
                          .replaceFirst('file:///', '')
                          .replaceFirst('file://', ''),
                    ),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.broken_image,
                      size: 64,
                      color: Colors.white54,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTriggeredItemsSheet(
    BuildContext context,
    List<TriggeredEntry> entries,
    String title,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.cs.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: context.cs.outlineVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: context.cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: entries
                      .map(
                        (e) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  e.name,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: context.cs.onSurface,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (e.lorebookName.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Text(
                                  e.lorebookName,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: context.cs.onSurfaceVariant
                                        .withValues(alpha: 0.6),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: e.source == 'vector'
                                      ? Colors.purple.withValues(alpha: 0.15)
                                      : e.source == 'memory'
                                      ? Colors.teal.withValues(alpha: 0.15)
                                      : context.cs.primaryContainer,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  e.source == 'vector'
                                      ? 'vector'
                                      : e.source == 'memory'
                                      ? 'memory'
                                      : 'keyword',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                    color: e.source == 'vector'
                                        ? Colors.purple
                                        : e.source == 'memory'
                                        ? Colors.teal
                                        : context.cs.onPrimaryContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final preset = ref.watch(themeProvider).activePreset;
    final appSettings = ref.watch(appSettingsProvider).valueOrNull;
    // Reserve space below the message list for: input bar + (keyboard or
    // drawer) + the bottom safe area. We pass the FINAL inset so the list's
    // padding doesn't churn per animation frame.
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    // Top inset for the chat list: safe area + GlazeScaffold wrap padding (10)
    // + GlazeAppBar height (56). Matches the floating header above the webview.
    final messageListTop = MediaQuery.paddingOf(context).top + 10 + 56;
    // ...
    final targetDrawerInset = widget.drawerOpen ? widget.drawerHeight : 0.0;
    final panelHeight = math.max(targetDrawerInset, widget.keyboardHeight);
    final factor = math.min(1.0, panelHeight / math.max(1.0, safeBottom));
    final effectiveBottomInset = panelHeight + (safeBottom * (1 - factor));
    final messageListBottom = _inputBarHeight + effectiveBottomInset;

    final bgBlur = preset.bgBlur > 0 ? preset.bgBlur : 0.0;
    final bgOpacity = preset.bgOpacity.clamp(0.0, 1.0);
    final bgPath = preset.bgImage;
    final fontStyle = ref.watch(chatFontStyleProvider);
    final fontDataUrl = ref.watch(chatFontDataProvider).valueOrNull;

    return Stack(
      children: [
        Positioned.fill(
          child: NotificationListener<UserScrollNotification>(
            onNotification: (notification) {
              if (widget.onScrollDirection != null) {
                widget.onScrollDirection!(notification.direction);
              }
              return false;
            },
            child: RepaintBoundary(
              child: Builder(
                builder: (context) {
                  final character = ref.watch(
                    characterByIdProvider(widget.charId),
                  );
                  final effectivePersona = ref.watch(
                    effectivePersonaForChatProvider(widget.charId),
                  );
                  final memBook = ref.watch(
                    memoryBookProvider(widget.state.session?.id ?? ''),
                  );
                  final greetingTotal = character == null
                      ? 0
                      : ((character.firstMes?.isNotEmpty == true ? 1 : 0) +
                            character.alternateGreetings
                                .where((g) => g.isNotEmpty)
                                .length);
                  return ChatWebViewWidget(
                    key: _webViewStateKey,
                    messages: widget.state.visibleMessages,
                    charId: widget.charId,
                    isGenerating: widget.state.isGenerating,
                    isGeneratingImage: widget.state.isGeneratingImage,
                    regenTargetId: widget.state.regenTargetId,
                    bottomInset: messageListBottom,
                    topInset: messageListTop,
                    charName: character?.name,
                    charColor: character?.color,
                    personaName: effectivePersona?.name,
                    greetingTotal: greetingTotal,
                    chatLayout: appSettings?.chatLayout ?? 'default',
                    charAvatarPath: character?.avatarPath,
                    personaAvatarPath: effectivePersona?.avatarPath,
                    bgImagePath: bgPath,
                    bgBlur: bgBlur,
                    bgOpacity: bgOpacity,
                    bgNoiseOpacity: preset.bgNoiseOpacity,
                    bgNoiseIntensity: preset.bgNoiseIntensity,
                    chatFontName: fontStyle.fontFamily,
                    chatFontDataUrl: fontDataUrl,
                    chatFontSize: fontStyle.fontSize,
                    chatLetterSpacing: fontStyle.letterSpacing,
                    memoryEntries: memBook.valueOrNull?.entries ?? [],
                    memoryDrafts: memBook.valueOrNull?.pendingDrafts ?? [],
                    sessionId: widget.state.session?.id,
                    visibleStartIndex: widget.state.visibleStartIndex,
                    onMessageContext:
                        (index, messageId, isUser, isSystem, content) {
                          showMessageContextMenu(
                            context: context,
                            ref: ref,
                            charId: widget.charId,
                            content: content,
                            messageIndex: index,
                            messageId: messageId,
                            isUser: isUser,
                            isTyping:
                                widget.state.isGenerating &&
                                index == widget.state.messages.length - 1,
                            isError: false,
                            isLast: index == widget.state.messages.length - 1,
                            isGenerating: widget.state.isGenerating,
                            isHidden: widget.state.messages[index].isHidden,
                          );
                        },
                    onSelectionChange: (ids) {
                      if (mounted) {
                        setState(() {
                          _selectedMessageIds = ids.toSet();
                          _isSelectionMode = _selectedMessageIds.isNotEmpty;
                        });
                      }
                    },
                    isSelectionMode: _isSelectionMode,
                    onSwipe: (id, direction) {
                      final idx = widget.state.messages.indexWhere(
                        (m) => m.id == id,
                      );
                      if (idx < 0) return;
                      final dir = direction == 'right' ? 1 : -1;
                      ref
                          .read(chatProvider(widget.charId).notifier)
                          .changeSwipe(idx, dir, fromSwipe: true);
                    },
                    onHeaderScroll: (hidden) {
                      if (widget.onScrollDirection == null) return;
                      // Reuse the existing scroll-direction wiring on the parent
                      // (reverse = down/hide, forward = up/show).
                      widget.onScrollDirection!(
                        hidden
                            ? ScrollDirection.reverse
                            : ScrollDirection.forward,
                      );
                    },
                    onScrollToBottomVisibility: (visible) {
                      if (!mounted || _showScrollToBottom == visible) return;
                      setState(() => _showScrollToBottom = visible);
                    },
                    onChangeGreeting: (id, dir) {
                      final idx = widget.state.messages.indexWhere(
                        (m) => m.id == id,
                      );
                      if (idx < 0) return;
                      ref
                          .read(chatProvider(widget.charId).notifier)
                          .setGreeting(idx, dir);
                    },
                    onRegenerate: (id) {
                      ref
                          .read(chatProvider(widget.charId).notifier)
                          .regenerateLastAssistant();
                    },
                    onStop: () {
                      final notifier = ref.read(
                        chatProvider(widget.charId).notifier,
                      );
                      if (widget.state.isGeneratingImage &&
                          !widget.state.isGenerating) {
                        notifier.abortImageGeneration();
                      } else {
                        notifier.abortGeneration();
                      }
                    },
                    onImgRetry: (instruction, messageId) {
                      final allMsgs = widget.state.messages;
                      final idx = allMsgs.indexWhere((m) => m.id == messageId);
                      if (idx >= 0) {
                        ref
                            .read(chatProvider(widget.charId).notifier)
                            .retryImageGenerationForMessage(idx);
                      }
                    },
                    onImgFind: (instruction, messageId) {
                      ref
                          .read(chatProvider(widget.charId).notifier)
                          .findImageOnDisk(messageId, instruction);
                    },
                    onImgRegen: (instruction, messageId) {
                      final allMsgs = widget.state.messages;
                      final idx = allMsgs.indexWhere((m) => m.id == messageId);
                      if (idx >= 0) {
                        ref
                            .read(chatProvider(widget.charId).notifier)
                            .retryImageGenerationForMessage(idx);
                      }
                    },
                    onImgCancel: () {
                      ref
                          .read(chatProvider(widget.charId).notifier)
                          .cancelImageGeneration();
                    },
                    onSelectionAction: (action, text) {
                      if (action == 'copy') {
                        Clipboard.setData(ClipboardData(text: text));
                      }
                    },
                    onEditSave: (id, text) {
                      final idx = widget.state.messages.indexWhere(
                        (m) => m.id == id,
                      );
                      if (idx >= 0 && text.isNotEmpty) {
                        ref
                            .read(chatProvider(widget.charId).notifier)
                            .editMessage(idx, text);
                      }
                      ref
                              .read(
                                editingMessageIdProvider(
                                  widget.charId,
                                ).notifier,
                              )
                              .state =
                          null;
                    },
                    onEditCancel: (id) {
                      ref
                              .read(
                                editingMessageIdProvider(
                                  widget.charId,
                                ).notifier,
                              )
                              .state =
                          null;
                    },
                    onImageClick: (imageUrl) {
                      _showImageViewer(context, imageUrl);
                    },
                    onGuidedSwipe: (id, guidanceText) {
                      final idx = widget.state.messages.indexWhere(
                        (m) => m.id == id,
                      );
                      if (idx < 0) return;
                      final msg = widget.state.messages[idx];
                      final isLastAssistant =
                          msg.role == 'assistant' &&
                          idx == widget.state.messages.length - 1;
                      if (isLastAssistant) {
                        ref
                            .read(chatProvider(widget.charId).notifier)
                            .regenerateLastAssistant(
                              guidanceText: guidanceText,
                            );
                      }
                    },
                    onToggleHidden: (id) {
                      final idx = widget.state.messages.indexWhere(
                        (m) => m.id == id,
                      );
                      if (idx >= 0) {
                        ref
                            .read(chatProvider(widget.charId).notifier)
                            .toggleMessageHidden(idx);
                      }
                    },
                    onMemoryClick: (id) {
                      final idx = widget.state.messages.indexWhere(
                        (m) => m.id == id,
                      );
                      if (idx < 0) return;
                      final msg = widget.state.messages[idx];
                      if (msg.triggeredMemories.isNotEmpty) {
                        _showTriggeredItemsSheet(
                          context,
                          msg.triggeredMemories,
                          'Memories',
                        );
                      }
                    },
                    searchQuery: widget.searchQuery,
                    searchCurrentIndex: widget.searchCurrentIndex,
                    onInjectClick: (id) {
                      final idx = widget.state.messages.indexWhere(
                        (m) => m.id == id,
                      );
                      if (idx < 0) return;
                      final msg = widget.state.messages[idx];
                      final all = [
                        ...msg.triggeredLorebooks,
                        ...msg.triggeredMemories,
                      ];
                      if (all.isNotEmpty) {
                        _showTriggeredItemsSheet(
                          context,
                          all,
                          'Triggered Entries',
                        );
                      }
                    },
                  );
                },
              ),
            ),
          ),
        ),
        // Top gradient for fade effect under the header
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: MediaQuery.paddingOf(context).top + 20,
          child: IgnorePointer(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black54, Colors.transparent],
                ),
              ),
            ),
          ),
        ),
        // Bottom gradient for fade effect under the input area
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: messageListBottom + 40,
          child: IgnorePointer(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black54, Colors.transparent],
                  stops: [0.0, 1.0],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: 16,
          bottom: messageListBottom + 16,
          child: IgnorePointer(
            ignoring: !_showScrollToBottom,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              opacity: _showScrollToBottom ? 1 : 0,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                offset: _showScrollToBottom
                    ? Offset.zero
                    : const Offset(0, 0.2),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _scrollToBottom,
                    borderRadius: BorderRadius.circular(24),
                    child: Ink(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: context.cs.surface.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.22),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: context.cs.primary,
                        size: 26,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // Animated bottom region: drawer slides up from below, the input
        // bar tracks the same reveal so they move as one piece.
        Positioned.fill(
          child: AnimatedBuilder(
            animation: widget.drawerAnim,
            builder: (context, _) {
              final progress = widget.drawerAnim.value;
              final bool drawerActive =
                  widget.drawerOpen || widget.isSwitchingToDrawer;
              final double targetPanelInset = drawerActive
                  ? widget.drawerHeight
                  : 0.0;
              final int durationMs = widget.isSwitchingToDrawer ? 0 : 260;

              return TweenAnimationBuilder<double>(
                tween: Tween<double>(
                  begin: targetPanelInset,
                  end: targetPanelInset,
                ),
                duration: Duration(milliseconds: durationMs),
                curve: Curves.easeOutCubic,
                builder: (context, animatedInset, _) {
                  final panelHeight = math.max(
                    animatedInset,
                    widget.keyboardHeight,
                  );

                  // Smoothly transition from safe area to panel height.
                  // This prevents a 24px jump when the animation starts.
                  final safeBottom = MediaQuery.paddingOf(context).bottom;
                  final factor = math.min(
                    1.0,
                    panelHeight / math.max(1.0, safeBottom),
                  );
                  final animatedBottomPanelInset =
                      panelHeight + (safeBottom * (1 - factor));

                  // Keep the panel mounted while the close animation runs out.
                  final renderDrawer = widget.drawerOpen || progress > 0.001;

                  return Stack(
                    children: [
                      if (renderDrawer)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: -widget.drawerHeight * (1 - progress),
                          height: widget.drawerHeight,
                          child: MagicDrawerPanel(
                            charId: widget.charId,
                            onClose: widget.onCloseDrawer,
                          ),
                        ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: animatedBottomPanelInset,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            NotificationListener<SizeChangedLayoutNotification>(
                              onNotification: (n) {
                                WidgetsBinding.instance.addPostFrameCallback(
                                  (_) => _checkHeight(),
                                );
                                return true;
                              },
                              child: SizeChangedLayoutNotifier(
                                child: Container(
                                  key: _inputBarKey,
                                  child: Builder(
                                    builder: (context) {
                                      final allSelectedHidden =
                                          _selectedMessageIds.isNotEmpty &&
                                          _selectedMessageIds.every((id) {
                                            final idx = widget.state.messages
                                                .indexWhere((m) => m.id == id);
                                            return idx >= 0 &&
                                                widget
                                                    .state
                                                    .messages[idx]
                                                    .isHidden;
                                          });
                                      return ChatInputBar(
                                        focusNode: widget.inputFocus,
                                        initialDraft:
                                            widget.state.session?.draft ?? '',
                                        batterySaver:
                                            appSettings?.batterySaver ?? false,
                                        onDraftChanged: (text) {
                                          ref
                                              .read(
                                                chatProvider(
                                                  widget.charId,
                                                ).notifier,
                                              )
                                              .saveDraft(text);
                                        },
                                        showSearchControls:
                                            widget.showSearchControls,
                                        searchQuery: widget.searchQuery,
                                        searchMatchCount:
                                            widget.searchMatches.length,
                                        searchCurrentIndex:
                                            widget.searchCurrentIndex,
                                        onSearchNext: widget.onSearchNext,
                                        onSearchPrev: widget.onSearchPrev,
                                        isSelectionMode: _isSelectionMode,
                                        selectedCount:
                                            _selectedMessageIds.length,
                                        allSelectedHidden: allSelectedHidden,
                                        onCancelSelection: () {
                                          setState(() {
                                            _isSelectionMode = false;
                                            _selectedMessageIds.clear();
                                          });
                                        },
                                        onHideSelected: () {
                                          final notifier = ref.read(
                                            chatProvider(
                                              widget.charId,
                                            ).notifier,
                                          );
                                          for (final id
                                              in _selectedMessageIds) {
                                            final idx = widget.state.messages
                                                .indexWhere((m) => m.id == id);
                                            if (idx >= 0) {
                                              notifier.toggleMessageHidden(idx);
                                            }
                                          }
                                          setState(() {
                                            _isSelectionMode = false;
                                            _selectedMessageIds.clear();
                                          });
                                        },
                                        onDeleteSelected: () {
                                          final notifier = ref.read(
                                            chatProvider(
                                              widget.charId,
                                            ).notifier,
                                          );
                                          // Sort indices in descending order so deleting doesn't shift remaining indices
                                          final indices =
                                              _selectedMessageIds
                                                  .map(
                                                    (id) => widget
                                                        .state
                                                        .messages
                                                        .indexWhere(
                                                          (m) => m.id == id,
                                                        ),
                                                  )
                                                  .where((idx) => idx >= 0)
                                                  .toList()
                                                ..sort(
                                                  (a, b) => b.compareTo(a),
                                                );
                                          for (final idx in indices) {
                                            notifier.deleteMessage(idx);
                                          }
                                          setState(() {
                                            _isSelectionMode = false;
                                            _selectedMessageIds.clear();
                                          });
                                        },
                                        isDrawerOpen:
                                            widget.drawerOpen ||
                                            widget.isSwitchingToDrawer,
                                        virtualKeyboardSend:
                                            widget.virtualKeyboardSend,
                                        enterToSend: widget.enterToSend,
                                        onSend: (text) {
                                          if (text.trim().isEmpty) return;
                                          ref
                                              .read(
                                                chatProvider(
                                                  widget.charId,
                                                ).notifier,
                                              )
                                              .sendMessage(text);
                                        },
                                        onSendWithGuidance: (text, guidance) {
                                          if (text.trim().isEmpty) return;
                                          ref
                                              .read(
                                                chatProvider(
                                                  widget.charId,
                                                ).notifier,
                                              )
                                              .sendMessage(
                                                text,
                                                guidanceText: guidance,
                                              );
                                        },
                                        isGenerating: widget.state.isGenerating,
                                        isGeneratingImage:
                                            widget.state.isGeneratingImage,
                                        onStop:
                                            (widget.state.isGenerating ||
                                                widget.state.isGeneratingImage)
                                            ? () {
                                                final notifier = ref.read(
                                                  chatProvider(
                                                    widget.charId,
                                                  ).notifier,
                                                );
                                                if (widget
                                                        .state
                                                        .isGeneratingImage &&
                                                    !widget
                                                        .state
                                                        .isGenerating) {
                                                  notifier
                                                      .abortImageGeneration();
                                                } else {
                                                  notifier.abortGeneration();
                                                }
                                              }
                                            : null,
                                        onMagicDrawer: widget.onToggleDrawer,
                                        onAttach: () => showModalBottomSheet(
                                          context: context,
                                          useRootNavigator: true,
                                          isScrollControlled: true,
                                          backgroundColor: Colors.transparent,
                                          builder: (_) => const ImageGenSheet(),
                                        ),
                                        onFullScreen:
                                            () {}, // Add your full screen logic here
                                        onContinue: () => ref
                                            .read(
                                              chatProvider(
                                                widget.charId,
                                              ).notifier,
                                            )
                                            .continueMessage(),
                                        onImpersonate: () => ref
                                            .read(
                                              chatProvider(
                                                widget.charId,
                                              ).notifier,
                                            )
                                            .regenerateLastAssistant(),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
