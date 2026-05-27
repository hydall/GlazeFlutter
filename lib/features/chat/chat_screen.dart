import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'editing_message_provider.dart';

import '../../core/state/character_provider.dart';
import '../../core/state/active_selection_provider.dart';
import '../../core/state/shared_prefs_provider.dart';
import '../../shared/theme/app_colors.dart';
import 'widgets/message_actions.dart';
import '../../shared/theme/theme_font_provider.dart';
import '../../shared/theme/theme_provider.dart';

import '../../shared/widgets/glaze_scaffold.dart';
import '../../shared/widgets/image_viewer.dart';
import '../settings/app_settings_provider.dart';
import 'chat_drawer_controller.dart';
import 'chat_provider.dart';
import 'chat_search_delegate.dart';
import 'chat_state.dart';
import 'widgets/chat_header.dart';
import 'widgets/chat_input_bar.dart';
import '../image_gen/widgets/image_gen_sheet.dart';
import 'widgets/magic_drawer.dart';
import 'widgets/chat_webview_widget.dart';
import 'widgets/webview_callbacks.dart';
import '../../core/models/chat_message.dart';
import '../../core/state/db_provider.dart';
import 'widgets/session_lifecycle_tracker.dart';

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
  bool _isHeaderHidden = false;
  late final ChatDrawerController _drawerCtrl;
  late final ChatSearchDelegate _search;

  @override
  void initState() {
    super.initState();
    _drawerCtrl = ChatDrawerController(
      vsync: this,
      readKeyboardHeight: () async {
        final prefs = await ref.read(sharedPreferencesProvider.future);
        return prefs.getDouble(kKeyboardHeightPref) ?? 0;
      },
      persistKeyboardHeight: (h) async {
        final prefs = await ref.read(sharedPreferencesProvider.future);
        await prefs.setDouble(kKeyboardHeightPref, h);
      },
    );
    _search = ChatSearchDelegate();
    if (widget.forceNewSession || widget.initialSessionIndex != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _applySessionPreference();
      });
    }
  }

  @override
  void dispose() {
    _drawerCtrl.dispose();
    _search.dispose();
    super.dispose();
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

  void _onScrollDirection(ScrollDirection direction) {
    if (direction == ScrollDirection.reverse && !_isHeaderHidden) {
      setState(() => _isHeaderHidden = true);
    } else if (direction == ScrollDirection.forward && _isHeaderHidden) {
      setState(() => _isHeaderHidden = false);
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
    final batterySaver = appSettings?.batterySaver ?? false;
    _drawerCtrl.setBatterySaverMode(batterySaver);

    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
    _drawerCtrl.handleKeyboardFrame(keyboardHeight);

    if (_drawerCtrl.switchingToDrawer && keyboardHeight == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _drawerCtrl.checkSwitchingTransition(keyboardHeight);
      });
    }

    if (keyboardHeight > 0 && _drawerCtrl.drawerOpen && !_drawerCtrl.switchingToDrawer) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _drawerCtrl.checkDrawerCollision(keyboardHeight);
      });
    }

    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final targetBottomPanelInset =
        _drawerCtrl.computeTargetBottomPanelInset(keyboardHeight, safeBottom);

    return SessionLifecycleTracker(
      charId: charId,
child: PopScope(
        canPop: _drawerCtrl.canPop() && !_search.showSearch,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          if (_drawerCtrl.inputFocus.hasFocus) {
            _drawerCtrl.inputFocus.unfocus();
            return;
          }
          if (_drawerCtrl.drawerOpen) {
            _drawerCtrl.closeDrawer();
            return;
          }
          if (_search.showSearch) {
            _search.closeSearch();
            return;
          }
        },
        child: GlazeScaffold(
          extendBodyBehindHeader: true,
          resizeToAvoidBottomInset: false,
          hideHeader: _isHeaderHidden,
          title: title,
          titleWidget: _search.showSearch
              ? TextField(
                  controller: _search.searchController,
                  autofocus: true,
                  style: TextStyle(color: context.cs.onSurface, fontSize: 16),
                  decoration: InputDecoration(
                    hintText: 'Search messages...',
                    hintStyle: TextStyle(
                      color: context.cs.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    suffixIcon: _search.searchQuery.isNotEmpty
                        ? IconButton(
                            icon: Icon(
                              Icons.close,
                              color: context.cs.onSurface,
                              size: 20,
                            ),
                            onPressed: () {
                              _search.closeSearch();
                            },
                          )
                        : null,
                  ),
                  onChanged: (q) {
                    _search.search(q, chatState?.messages ?? []);
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
            if (_search.showSearch) {
              _search.closeSearch();
            } else {
              context.go('/');
            }
          },
          actions: _search.showSearch
              ? const []
              : [
                  IconButton(
                    icon: const Icon(Icons.search),
                    color: context.cs.primary,
                    onPressed: () {
                      _search.openSearch();
                    },
                  ),
                ],
          body: chatStateAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (state) => _ChatBody(
              charId: charId,
              state: state,
              drawerCtrl: _drawerCtrl,
              search: _search,
              keyboardHeight: keyboardHeight,
              targetBottomPanelInset: targetBottomPanelInset,
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
  final ChatDrawerController drawerCtrl;
  final ChatSearchDelegate search;
  final double keyboardHeight;
  final double targetBottomPanelInset;
  final ValueChanged<ScrollDirection>? onScrollDirection;
  final bool virtualKeyboardSend;
  final bool enterToSend;

  const _ChatBody({
    required this.charId,
    required this.state,
    required this.drawerCtrl,
    required this.search,
    required this.keyboardHeight,
    required this.targetBottomPanelInset,
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
  late final VoidCallback _drawerAnimListener;

  bool _isSelectionMode = false;
  bool _showScrollToBottom = false;
  Set<String> _selectedMessageIds = {};
  final GlobalKey<ChatWebViewWidgetState> _webViewStateKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _drawerAnimListener = () {
      if (mounted) setState(() {});
    };
    widget.drawerCtrl.drawerAnim.addListener(_drawerAnimListener);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkHeight());
  }

  @override
  void didUpdateWidget(covariant _ChatBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.drawerCtrl.drawerAnim, widget.drawerCtrl.drawerAnim)) {
      oldWidget.drawerCtrl.drawerAnim.removeListener(_drawerAnimListener);
      widget.drawerCtrl.drawerAnim.addListener(_drawerAnimListener);
    }
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
    final ImageProvider provider;
    if (imageUrl.startsWith('data:')) {
      final commaIdx = imageUrl.indexOf(',');
      if (commaIdx == -1) return;
      provider = MemoryImage(base64Decode(imageUrl.substring(commaIdx + 1)));
    } else if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
      provider = NetworkImage(imageUrl);
    } else {
      final path = imageUrl
          .replaceFirst('file:///', '')
          .replaceFirst('file://', '');
      provider = FileImage(File(path));
    }
    ImageViewer.show(context, imageProvider: provider);
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
  void dispose() {
    widget.drawerCtrl.drawerAnim.removeListener(_drawerAnimListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditingMessage =
        ref.watch(editingMessageIdProvider(widget.charId)) != null;
    ref.listen<String?>(
      editingMessageIdProvider(widget.charId),
      (prev, next) {
        if (next != null) {
          if (widget.drawerCtrl.inputFocus.hasFocus) {
            widget.drawerCtrl.inputFocus.unfocus();
          }
          if (_isSelectionMode || _selectedMessageIds.isNotEmpty) {
            setState(() {
              _isSelectionMode = false;
              _selectedMessageIds.clear();
            });
          }
        }
      },
    );
    final appSettings = ref.watch(appSettingsProvider).valueOrNull;
    final batterySaverMode = appSettings?.batterySaver ?? false;
    final preset = batterySaverMode
        ? ref.read(themeProvider).activePreset
        : ref.watch(themeProvider).activePreset;
    final batterySaver = appSettings?.batterySaver ?? false;
    // Reserve space below the message list for: input bar + (keyboard or
    // drawer) + the bottom safe area. We pass the FINAL inset so the list's
    // padding doesn't churn per animation frame.
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    // Top inset for the chat list: safe area + GlazeScaffold wrap padding (10)
    // + GlazeAppBar height (56). Matches the floating header above the webview.
    final messageListTop = MediaQuery.paddingOf(context).top + 10 + 56;
    // ...
    final drawerProgress = widget.drawerCtrl.drawerAnim.value;
    final targetDrawerInset =
        (widget.drawerCtrl.drawerOpen || widget.drawerCtrl.switchingToDrawer)
            ? widget.drawerCtrl.activeDrawerHeight * drawerProgress
            : 0.0;
    final panelHeight = math.max(targetDrawerInset, widget.keyboardHeight);
    final factor = math.min(1.0, panelHeight / math.max(1.0, safeBottom));
    final effectiveBottomInset = panelHeight + (safeBottom * (1 - factor));
    final messageListBottom = _inputBarHeight + effectiveBottomInset;

    final bgBlur = preset.bgBlur > 0 ? preset.bgBlur : 0.0;
    final bgOpacity = preset.bgOpacity.clamp(0.0, 1.0);
    final bgPath = preset.bgImage;
    final fontStyle = batterySaverMode
        ? ref.read(chatFontStyleProvider)
        : ref.watch(chatFontStyleProvider);
    final fontDataUrl = batterySaverMode
        ? ref.read(chatFontDataProvider).valueOrNull
        : ref.watch(chatFontDataProvider).valueOrNull;
    final character = batterySaverMode
        ? ref.read(characterByIdProvider(widget.charId))
        : ref.watch(characterByIdProvider(widget.charId));
    final personaKey = (
      charId: widget.charId,
      sessionId: widget.state.session?.id,
    );
    final effectivePersona = batterySaverMode
        ? ref.read(effectivePersonaForChatProvider(personaKey))
        : ref.watch(effectivePersonaForChatProvider(personaKey));
    ref.listen(effectivePersonaForChatProvider(personaKey), (prev, next) {
      if (prev?.id == next?.id &&
          prev?.name == next?.name &&
          prev?.avatarPath == next?.avatarPath) {
        return;
      }
      _webViewStateKey.currentState?.applyIdentity(
        charName: character?.name,
        charColor: character?.color,
        personaName: next?.name,
        charAvatarPath: character?.avatarPath,
        personaAvatarPath: next?.avatarPath,
        greetingTotal: character == null
            ? 0
            : ((character.firstMes?.isNotEmpty == true ? 1 : 0) +
                character.alternateGreetings
                    .where((g) => g.isNotEmpty)
                    .length),
      );
    });
    final memBook = batterySaverMode
        ? ref.read(memoryBookProvider(widget.state.session?.id ?? ''))
        : ref.watch(memoryBookProvider(widget.state.session?.id ?? ''));
    final greetingTotal = character == null
        ? 0
        : ((character.firstMes?.isNotEmpty == true ? 1 : 0) +
            character.alternateGreetings.where((g) => g.isNotEmpty).length);

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
              child: ChatWebViewWidget(
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
                    batterySaver: appSettings?.batterySaver ?? false,
                    hideMessageId: appSettings?.hideMessageId ?? false,
                    hideGenerationTime: appSettings?.hideGenerationTime ?? false,
                    hideTokenCount: appSettings?.hideTokenCount ?? false,
                    disableSwipeRegeneration:
                        appSettings?.disableSwipeRegeneration ?? false,
                    messageActions: MessageActionsCallbacks(
                      onMessageContext: (index, messageId, isUser, isSystem, content) {
                        showMessageContextMenu(
                          context: context,
                          ref: ref,
                          charId: widget.charId,
                          content: content,
                          messageIndex: index,
                          messageId: messageId,
                          isUser: isUser,
                          isTyping: widget.state.isGenerating && index == widget.state.messages.length - 1,
                          isError: false,
                          isLast: index == widget.state.messages.length - 1,
                          isGenerating: widget.state.isGenerating,
                          isHidden: widget.state.messages[index].isHidden,
                        );
                      },
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
                    ),
                    editActions: EditActionsCallbacks(
                      onEditSave: (id, text) {
                        final idx = widget.state.messages.indexWhere(
                          (m) => m.id == id,
                        );
                        if (idx >= 0 && text.isNotEmpty) {
                          ref
                              .read(chatProvider(widget.charId).notifier)
                              .editMessage(idx, text, tagStart: '<think>', tagEnd: '</think>');
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
                      onEditFocusChange: (id, focused) {
                        if (!focused) return;
                        final activeEditingId = ref.read(
                          editingMessageIdProvider(widget.charId),
                        );
                        if (activeEditingId == id && widget.drawerCtrl.inputFocus.hasFocus) {
                          widget.drawerCtrl.inputFocus.unfocus();
                        }
                      },
                    ),
                    imageGenActions: ImageGenCallbacks(
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
                    ),
                    scrollActions: ScrollCallbacks(
                      onHeaderScroll: (hidden) {
                        if (widget.onScrollDirection == null) return;
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
                    ),
                    miscActions: MiscCallbacks(
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
                      onSelectionAction: (action, text) {
                        if (action == 'copy') {
                          Clipboard.setData(ClipboardData(text: text));
                        }
                      },
                      onSelectionChange: (ids) {
                        if (mounted) {
                          setState(() {
                            _selectedMessageIds = ids.toSet();
                            _isSelectionMode = _selectedMessageIds.isNotEmpty;
                          });
                        }
                      },
                      onImageClick: (imageUrl) {
                        _showImageViewer(context, imageUrl);
                      },
                    ),
                    isSelectionMode: _isSelectionMode,
                    searchQuery: widget.search.searchQuery,
                    searchCurrentIndex: widget.search.searchCurrentIndex,
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
            animation: widget.drawerCtrl.drawerAnim,
            builder: (context, _) {
              final progress = widget.drawerCtrl.drawerAnim.value;
              final bool drawerActive =
                  widget.drawerCtrl.drawerOpen || widget.drawerCtrl.switchingToDrawer;
              final double targetPanelInset = drawerActive
                  ? widget.drawerCtrl.activeDrawerHeight
                  : 0.0;
              final panelHeight = math.max(
                targetPanelInset,
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
              final renderDrawer = widget.drawerCtrl.drawerOpen || progress > 0.001;

              return Stack(
                children: [
                  if (renderDrawer)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: -widget.drawerCtrl.activeDrawerHeight * (1 - progress),
                      height: widget.drawerCtrl.activeDrawerHeight,
                      child: MagicDrawerPanel(
                        charId: widget.charId,
                        onClose: () => widget.drawerCtrl.closeDrawer(),
                        disableEffects:
                            batterySaver && widget.drawerCtrl.isDrawerAnimating,
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
                                        focusNode: widget.drawerCtrl.inputFocus,
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
                                            widget.search.showSearch,
                                        searchQuery: widget.search.searchQuery,
                                        searchMatchCount:
                                            widget.search.matchCount,
                                        searchCurrentIndex:
                                            widget.search.searchCurrentIndex,
                                        onSearchNext: widget.search.onSearchNext,
                                        onSearchPrev: widget.search.onSearchPrev,
                                        isEditingMessage: isEditingMessage,
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
                                            widget.drawerCtrl.drawerOpen ||
                                            widget.drawerCtrl.switchingToDrawer,
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
                                        onMagicDrawer: () => widget.drawerCtrl.toggleDrawer(context),
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
          ),
        ),
      ],
    );
  }
}
