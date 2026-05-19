import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/state/character_provider.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/theme_font_provider.dart';
import '../../shared/theme/theme_provider.dart';

import '../../shared/widgets/glaze_bottom_sheet.dart';
import '../../shared/widgets/glaze_scaffold.dart';
import '../../shared/widgets/glaze_toast.dart';
import '../../shared/widgets/noise_overlay.dart';
import '../settings/app_settings_provider.dart';
import 'chat_actions_service.dart';
import 'chat_provider.dart';
import 'chat_state.dart';
import 'widgets/chat_header.dart';
import 'widgets/chat_input_bar.dart';
import '../image_gen/widgets/image_gen_sheet.dart';
import 'widgets/magic_drawer.dart';
import 'widgets/message_list.dart';
import 'widgets/cached_token_breakdown.dart';
import 'widgets/prompt_preview_screen.dart';
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

  Future<void> _applySessionPreference() async {
    if (_sessionApplied) return;
    _sessionApplied = true;
    final notifier = ref.read(chatProvider(widget.charId).notifier);
    if (widget.forceNewSession) {
      await notifier.createNewSession();
    } else if (widget.initialSessionIndex != null) {
      await notifier.switchSession(widget.initialSessionIndex!);
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
          if (mounted && _tempMaxHeight > 200 && _tempMaxHeight != _lastKeyboardHeight) {
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
    final isIdle = keyboardHeight == 0 && !_drawerOpen && !_switchingToDrawer && _drawerAnimController.value == 0;
    final bottomPadding = isIdle ? safeBottom : 0.0;

    // Final (post-animation) inset for layout-only consumers (MessageList).
    // Animated visual positioning of the input + drawer is driven by
    // _drawerAnim inside _ChatBody so list paddings don't churn each frame.
    final targetDrawerInset = (_drawerOpen || _switchingToDrawer) ? _activeDrawerHeight : 0.0;
    final targetBottomPanelInset = math.max(targetDrawerInset, keyboardHeight) + bottomPadding;

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
                  hintStyle: TextStyle(color: context.cs.onSurfaceVariant.withValues(alpha: 0.5)),
                  border: InputBorder.none,
                  isDense: true,
                  suffixIcon: _searchQuery.isNotEmpty 
                      ? IconButton(
                          icon: Icon(Icons.close, color: context.cs.onSurface, size: 20),
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
                      final content = chatState.messages[i].content.toLowerCase();
                      int startIndex = 0;
                      int matchIndex = 0;
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

  /// Final (post-animation) inset for layout-only consumers like
  /// [MessageList]. Doesn't churn per frame.
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

  @override
  Widget build(BuildContext context) {
    final preset = ref.watch(themeProvider).activePreset;
    final appSettings = ref.watch(appSettingsProvider).valueOrNull;
    // Reserve space below the message list for: input bar + (keyboard or
    // drawer) + the bottom safe area. We pass the FINAL inset so the list's
    // padding doesn't churn per animation frame.
    final safeBottom = MediaQuery.paddingOf(context).bottom;
            // ...
            final targetDrawerInset = widget.drawerOpen ? widget.drawerHeight : 0.0;
            final panelHeight = math.max(targetDrawerInset, widget.keyboardHeight);
            final factor = math.min(1.0, panelHeight / math.max(1.0, safeBottom));
            final effectiveBottomInset = panelHeight + (safeBottom * (1 - factor));
            final messageListBottom = _inputBarHeight + effectiveBottomInset;

            final bgBlur = preset.bgBlur > 0 ? preset.bgBlur : 0.0;
            final bgOpacity = preset.bgOpacity.clamp(0.0, 1.0);

            return Stack(
              children: [
                if (ref.watch(bgImageProvider).valueOrNull case final path?)
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: _BgImage(
                        path: path,
                        blur: bgBlur,
                        opacity: bgOpacity,
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: NotificationListener<UserScrollNotification>(
                    onNotification: (notification) {
                      if (widget.onScrollDirection != null) {
                        widget.onScrollDirection!(notification.direction);
                      }
                      return false;
                    },
                    child: RepaintBoundary(
                      child: Builder(builder: (context) {
                        final breakdown = ref.watch(cachedTokenBreakdownProvider(widget.charId));
                        return MessageList(
                        messages: widget.state.messages,
                        isGenerating: widget.state.isGenerating,
                        generationStartTime: widget.state.generationStartTime,
                        charId: widget.charId,
                        sessionId: widget.state.session?.id,
                        bottomInset: messageListBottom,
                        isDrawerOpen: widget.drawerOpen || widget.isSwitchingToDrawer,
                        searchQuery: widget.searchQuery,
                        searchMatches: widget.searchMatches,
                        searchCurrentIndex: widget.searchCurrentIndex,
                        contextCutoffIndex: breakdown?.cutoffIndex ?? -1,
                      );
                      }),
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
        // Animated bottom region: drawer slides up from below, the input
        // bar tracks the same reveal so they move as one piece.
        AnimatedBuilder(
          animation: widget.drawerAnim,
          builder: (context, _) {
            final progress = widget.drawerAnim.value;
            final bool drawerActive = widget.drawerOpen || widget.isSwitchingToDrawer;
            final double targetPanelInset = drawerActive ? widget.drawerHeight : 0.0;
            final int durationMs = widget.isSwitchingToDrawer ? 0 : 260;

            return TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: targetPanelInset, end: targetPanelInset),
              duration: Duration(milliseconds: durationMs),
              curve: Curves.easeOutCubic,
              builder: (context, animatedInset, _) {
                final panelHeight = math.max(animatedInset, widget.keyboardHeight);
                
                // Smoothly transition from safe area to panel height.
                // This prevents a 24px jump when the animation starts.
                final safeBottom = MediaQuery.paddingOf(context).bottom;
                final factor = math.min(1.0, panelHeight / math.max(1.0, safeBottom));
                final animatedBottomPanelInset = panelHeight + (safeBottom * (1 - factor));

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
                          WidgetsBinding.instance.addPostFrameCallback((_) => _checkHeight());
                          return true;
                        },
                        child: SizeChangedLayoutNotifier(
                          child: Container(
                            key: _inputBarKey,
                            child: ChatInputBar(
                              focusNode: widget.inputFocus,
                              initialDraft: widget.state.session?.draft ?? '',
                              batterySaver: appSettings?.batterySaver ?? false,
                              onDraftChanged: (text) {
                                ref.read(chatProvider(widget.charId).notifier).saveDraft(text);
                              },
                              showSearchControls: widget.showSearchControls,
                              searchQuery: widget.searchQuery,
                              searchMatchCount: widget.searchMatches.length,
                              searchCurrentIndex: widget.searchCurrentIndex,
                              onSearchNext: widget.onSearchNext,
                              onSearchPrev: widget.onSearchPrev,
                              isDrawerOpen: widget.drawerOpen || widget.isSwitchingToDrawer,
                              virtualKeyboardSend: widget.virtualKeyboardSend,
                              enterToSend: widget.enterToSend,
                              onSend: (text) {
                                if (text.trim().isEmpty) return;
                                ref
                                    .read(chatProvider(widget.charId).notifier)
                                    .sendMessage(text);
                              },
                              onSendWithGuidance: (text, guidance) {
                                if (text.trim().isEmpty) return;
                                ref
                                    .read(chatProvider(widget.charId).notifier)
                                    .sendMessage(text, guidanceText: guidance);
                              },
                              isGenerating: widget.state.isGenerating,
                              onStop: widget.state.isGenerating
                                  ? () => ref
                                        .read(chatProvider(widget.charId).notifier)
                                        .abortGeneration()
                                  : null,
                              onMagicDrawer: widget.onToggleDrawer,
                              onImageGen: () => GlazeBottomSheet.show(
                                context,
                                child: const ImageGenSheet(),
                              ),
                              onContinue: () => ref
                                  .read(chatProvider(widget.charId).notifier)
                                  .continueMessage(),
                              onImpersonate: () => ref
                                  .read(chatProvider(widget.charId).notifier)
                                  .regenerateLastAssistant(),
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
      ],
    );
  }
}



class _ChatSearchBar extends StatelessWidget {
  final String query;
  final int matchCount;
  final int currentIndex;
  final ValueChanged<String> onChanged;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onClose;

  const _ChatSearchBar({
    required this.query,
    required this.matchCount,
    required this.currentIndex,
    required this.onChanged,
    this.onPrevious,
    this.onNext,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            autofocus: true,
            style: TextStyle(color: context.cs.onSurface, fontSize: 16),
            decoration: InputDecoration(
              hintText: 'Search messages...',
              hintStyle: TextStyle(color: context.cs.onSurfaceVariant.withValues(alpha: 0.5)),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
            onChanged: onChanged,
          ),
        ),
        if (query.isNotEmpty) ...[
          Text(
            matchCount > 0 ? '${currentIndex + 1}/$matchCount' : '0/0',
            style: TextStyle(fontSize: 12, color: context.cs.onSurfaceVariant),
          ),
          IconButton(
            icon: Icon(Icons.keyboard_arrow_up, size: 24, color: context.cs.onSurface),
            onPressed: onPrevious,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          IconButton(
            icon: Icon(Icons.keyboard_arrow_down, size: 24, color: context.cs.onSurface),
            onPressed: onNext,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
        IconButton(
          icon: Icon(Icons.close, size: 24, color: context.cs.onSurface),
          onPressed: onClose,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
      ],
    );
  }
}

class _BgImage extends StatelessWidget {
  final String path;
  final double blur;
  final double opacity;

  const _BgImage({required this.path, required this.blur, required this.opacity});

  @override
  Widget build(BuildContext context) {
    if (opacity <= 0) return const SizedBox.shrink();
    final imageProvider = FileImage(File(path));
    Widget child = DecoratedBox(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: imageProvider,
          fit: BoxFit.cover,
          colorFilter: opacity < 1.0
              ? ColorFilter.mode(Color.fromRGBO(0, 0, 0, 1.0 - opacity), BlendMode.dstIn)
              : null,
        ),
      ),
    );
    if (blur > 0) {
      child = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: child,
      );
    }
    return ClipRect(child: child);
  }
}
