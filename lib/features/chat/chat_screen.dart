import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/utils/platform_paths.dart';
import 'editing_message_provider.dart';

import '../../core/state/character_provider.dart';
import '../../core/llm/regex_service.dart';
import '../../core/state/active_selection_provider.dart';
import '../../core/state/memory_settings_provider.dart';
import '../../core/state/memory_agent_providers.dart';
import '../../core/state/shared_prefs_provider.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/shell/desktop/desktop_layout_provider.dart'
    show isDesktopLayout;
import 'widgets/message_actions.dart';
import '../../shared/theme/theme_font_provider.dart';
import '../../shared/theme/theme_preset.dart';
import '../../shared/theme/theme_provider.dart';

import '../../shared/widgets/glaze_scaffold.dart';
import '../../shared/widgets/glaze_bottom_sheet.dart';
import '../../shared/widgets/glaze_error_dialog.dart';
import '../../shared/widgets/image_viewer.dart';
import '../personas/persona_list_screen.dart';
import '../settings/api_list_provider.dart';
import '../settings/api_settings_screen.dart';
import '../settings/app_settings_provider.dart';
import 'chat_drawer_controller.dart'
    show ChatDrawerController, DrawerPanel, kKeyboardHeightPref;
import 'chat_provider.dart';
import 'controllers/chat_message_selection_controller.dart';
import 'chat_search_delegate.dart';
import 'chat_state.dart';
import 'state/chat_body_selectors.dart';
import 'state/memory_activity_provider.dart';
import 'widgets/chat_header.dart';
import 'widgets/chat_input_bar.dart';
import 'widgets/magic_drawer.dart';
import 'widgets/memory_activity_card.dart';
import 'widgets/post_cleaner_status_card.dart';
import 'widgets/studio_status_card.dart';
import 'widgets/quick_replies_panel.dart';
import 'widgets/chat_webview_widget.dart';
import 'widgets/triggered_items_sheet.dart';
import 'widgets/webview_callbacks.dart';
import '../../core/models/chat_message.dart';
import '../../core/state/db_provider.dart';
import 'widgets/session_lifecycle_tracker.dart';

String _chatWebViewThemeSyncKey(ThemePreset preset, String chatLayout) {
  return [
    preset.id,
    preset.accentColor,
    preset.uiColor,
    preset.userBubbleColor,
    preset.charBubbleColor,
    preset.userBubbleGradient,
    preset.charBubbleGradient,
    preset.userTextColor,
    preset.charTextColor,
    preset.userQuoteColor,
    preset.charQuoteColor,
    preset.userItalicColor,
    preset.charItalicColor,
    preset.elementOpacity,
    preset.elementBlur,
    preset.uiFontWeight,
    preset.userMessageFontWeight,
    preset.charMessageFontWeight,
    preset.userBubbleRadius,
    preset.charBubbleRadius,
    preset.showUserAvatar,
    preset.showCharAvatar,
    preset.showUserName,
    preset.showCharName,
    chatLayout,
  ].join('|');
}

class ChatScreen extends ConsumerStatefulWidget {
  final String charId;
  final int? initialSessionIndex;
  final bool forceNewSession;

  /// When set (e.g. opening from a "new message" notification tap), the chat
  /// scrolls to and briefly flashes this message once the WebView is ready.
  final String? targetMessageId;

  const ChatScreen({
    super.key,
    required this.charId,
    this.initialSessionIndex,
    this.forceNewSession = false,
    this.targetMessageId,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with SingleTickerProviderStateMixin {
  bool _sessionApplied = false;
  bool _sessionSwitchPending = false;
  int _applyEpoch = 0;
  // True once `_ChatBody` (and the keep-alive WebView) has been rendered at
  // least once. After that, an in-chat session switch overlays a spinner
  // instead of destroying the body, so the WebView is never recreated.
  bool _everBuiltBody = false;
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
    final epoch = ++_applyEpoch;
    final needsSwitch =
        widget.forceNewSession || widget.initialSessionIndex != null;
    if (needsSwitch && mounted) {
      setState(() => _sessionSwitchPending = true);
    }
    try {
      // Wait for chatProvider's initial build to complete before switching,
      // otherwise the build's final state may overwrite our switchSession.
      await ref.read(chatProvider(widget.charId).future);
      if (!mounted || epoch != _applyEpoch) return;
      final notifier = ref.read(chatProvider(widget.charId).notifier);
      if (widget.forceNewSession) {
        await notifier.createNewSession();
      } else if (widget.initialSessionIndex != null) {
        await notifier
            .switchSession(widget.initialSessionIndex!)
            .timeout(const Duration(seconds: 30));
      }
      if (!mounted || epoch != _applyEpoch) return;
    } on TimeoutException catch (e) {
      if (mounted && epoch == _applyEpoch) {
        GlazeErrorDialog.show(
          context,
          e,
          prefix: 'Failed to open chat session',
        );
      }
    } catch (e) {
      if (mounted && epoch == _applyEpoch) {
        GlazeErrorDialog.show(
          context,
          e,
          prefix: 'Failed to open chat session',
        );
      }
    } finally {
      if (mounted && epoch == _applyEpoch && _sessionSwitchPending) {
        setState(() => _sessionSwitchPending = false);
      }
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
    final session = chatState?.session;
    final customSessionName = session?.sessionVars['sessionName']?.trim();
    final sessionName = session != null
        ? (customSessionName != null && customSessionName.isNotEmpty
              ? customSessionName
              : 'Session #${session.sessionIndex + 1}')
        : 'status_connecting'.tr();
    final sessionIndex = chatState?.session?.sessionIndex ?? 0;

    final appSettings = ref.watch(appSettingsProvider).value;
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

    if (keyboardHeight > 0 &&
        _drawerCtrl.drawerOpen &&
        !_drawerCtrl.switchingToDrawer) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _drawerCtrl.checkDrawerCollision(keyboardHeight);
      });
    }

    return SessionLifecycleTracker(
      charId: charId,
      // Chat is always reached via `context.go('/chat/...')`, which replaces the
      // navigation stack — so a real pop has nothing beneath it and the OS would
      // close the app. We must NOT add our own `PopScope` here: `GlazeScaffold`
      // already wraps its body in a `PopScope` (canPop is false because showBack
      // is true) and routes the intercepted back gesture to `onBack`. Flutter
      // invokes the callbacks of *every* registered PopEntry on the route, so a
      // second `PopScope` would fire alongside `onBack` and still navigate away
      // even after we dismissed an overlay. All back handling lives in `onBack`.
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
                  hintText: 'search_messages'.tr(),
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
          // Dismiss any open overlay first; only navigate up when nothing is
          // open. Order mirrors the precedence the back gesture should follow.
          if (_drawerCtrl.inputFocus.hasFocus) {
            _drawerCtrl.inputFocus.unfocus();
            return;
          }
          // Covers both the open magic drawer / quick replies panel and the
          // brief keyboard→drawer transition window; closeDrawer handles both.
          if (_drawerCtrl.drawerOpen || _drawerCtrl.switchingToDrawer) {
            _drawerCtrl.closeDrawer();
            return;
          }
          if (_search.showSearch) {
            _search.closeSearch();
            return;
          }
          context.go('/');
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
          error: (e, _) => Center(child: Text('${'title_error'.tr()}: $e')),
          data: (state) {
            // The index comparison only gates the INITIAL navigation to a
            // requested session (deep link / history open). Once that initial
            // session has been applied (`_sessionApplied`), in-chat switches
            // like branchSession produce a session with a *different*
            // sessionIndex than `initialSessionIndex` — comparing against it
            // forever would leave the spinner stuck after branching until an
            // app restart. After the initial apply, only `_sessionSwitchPending`
            // gates the spinner.
            final awaitingTargetSession =
                _sessionSwitchPending ||
                (!_sessionApplied &&
                    widget.initialSessionIndex != null &&
                    state.session?.sessionIndex != widget.initialSessionIndex);
            // Only replace the body with a full-screen spinner on the very
            // first open, when the WebView hasn't been built yet. For an
            // in-chat switch (e.g. after importing a chat, which re-navigates
            // to /chat/<id>?session=N) the keep-alive WebView is already
            // mounted; destroying and recreating `_ChatBody` here would not
            // re-run WebView init reliably and left a grey, unresponsive page
            // until restart. Keep the body mounted and overlay the spinner so
            // the WebView's own `_applySessionSwitch` handles the transition.
            if (awaitingTargetSession && !_everBuiltBody) {
              return const Center(child: CircularProgressIndicator());
            }
            _everBuiltBody = true;
            return Stack(
              children: [
                _ChatBody(
                  charId: charId,
                  state: state,
                  drawerCtrl: _drawerCtrl,
                  search: _search,
                  keyboardHeight: keyboardHeight,
                  onScrollDirection: _onScrollDirection,
                  virtualKeyboardSend: virtualKeyboardSend,
                  enterToSend: enterToSend,
                  targetMessageId: widget.targetMessageId,
                ),
                if (awaitingTargetSession)
                  const Positioned.fill(
                    child: IgnorePointer(
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
              ],
            );
          },
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
  final ValueChanged<ScrollDirection>? onScrollDirection;
  final bool virtualKeyboardSend;
  final bool enterToSend;
  final String? targetMessageId;

  const _ChatBody({
    required this.charId,
    required this.state,
    required this.drawerCtrl,
    required this.search,
    required this.keyboardHeight,
    this.onScrollDirection,
    this.virtualKeyboardSend = false,
    this.enterToSend = true,
    this.targetMessageId,
  });

  @override
  ConsumerState<_ChatBody> createState() => _ChatBodyState();
}

class _ChatBodyState extends ConsumerState<_ChatBody>
    with WidgetsBindingObserver {
  double _inputBarHeight = 130.0;
  final GlobalKey _inputBarKey = GlobalKey();

  /// Last bottom inset (input bar + keyboard/drawer) pushed to the WebView.
  /// Cached so it can be re-asserted on app resume — see
  /// [didChangeAppLifecycleState].
  double _lastMessageListBottom = 0;

  /// Measured height of the floating [MemoryActivityCard] (0 when hidden) so
  /// the message list reserves room at the *top* for it — otherwise the card
  /// floats under the header and covers the first visible messages.
  double _memoryCardHeight = 0.0;
  final GlobalKey _memoryCardKey = GlobalKey();

  final _selectionCtrl = ChatMessageSelectionController();
  bool _showScrollToBottom = false;
  bool _showMemoryActivity = false;
  final GlobalKey<ChatWebViewWidgetState> _webViewStateKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkHeight());
    final targetId = widget.targetMessageId;
    if (targetId != null && targetId.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(_scrollToTargetMessage(targetId)),
      );
    }
  }

  /// Waits for the keep-alive WebView to finish initializing, then scrolls to
  /// and flashes the message that a tapped notification points at. Mirrors
  /// Vue's openChat(msgId) → scrollToAnchor + search-highlight behaviour.
  Future<void> _scrollToTargetMessage(String messageId) async {
    for (var i = 0; i < 100; i++) {
      if (!mounted) return;
      final st = _webViewStateKey.currentState;
      if (st != null && st.isReady) {
        // Let the initializer's opening scroll-to-bottom settle before
        // retargeting, otherwise the two scrolls fight each other.
        await Future<void>.delayed(const Duration(milliseconds: 400));
        if (!mounted) return;
        await st.scrollToMessage(messageId, highlight: true);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  void _checkHeight() {
    if (!mounted) return;
    var changed = false;
    var nextInputBarHeight = _inputBarHeight;
    var nextMemoryCardHeight = _memoryCardHeight;

    final inputCtx = _inputBarKey.currentContext;
    if (inputCtx != null) {
      final size = inputCtx.size;
      if (size != null && size.height != _inputBarHeight && size.height > 0) {
        nextInputBarHeight = size.height;
        changed = true;
      }
    }

    // The memory card is only mounted while visible. When it is absent its
    // reserved top height collapses back to 0 so the list reclaims the space.
    final memoryHeight = _memoryCardKey.currentContext?.size?.height ?? 0.0;
    if (memoryHeight != _memoryCardHeight) {
      nextMemoryCardHeight = memoryHeight;
      changed = true;
    }

    if (changed) {
      setState(() {
        _inputBarHeight = nextInputBarHeight;
        _memoryCardHeight = nextMemoryCardHeight;
      });
    }
  }

  Future<void> _scrollToBottom() async {
    final webViewState = _webViewStateKey.currentState;
    if (webViewState != null) {
      // Mirror Vue: the scroll-to-bottom button animates smoothly (the JS side
      // falls back to an instant jump when more than 3000px away).
      await webViewState.scrollToBottom(smooth: true);
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
    } else if (imageUrl.startsWith('http://') ||
        imageUrl.startsWith('https://')) {
      provider = NetworkImage(imageUrl);
    } else {
      final path = _imageSrcToFilePath(imageUrl);
      provider = FileImage(File(path));
    }
    ImageViewer.show(context, imageProvider: provider);
  }

  String _imageSrcToFilePath(String src) {
    if (src.startsWith('file://')) {
      try {
        return Uri.parse(src).toFilePath(windows: Platform.isWindows);
      } catch (_) {
        final withoutScheme = src.replaceFirst('file://', '');
        if (Platform.isWindows) return withoutScheme.replaceFirst('/', '');
        return withoutScheme.startsWith('/')
            ? withoutScheme
            : '/$withoutScheme';
      }
    }
    return src;
  }

  /// Saves/shares a generated image. The native share sheet on iOS/Android
  /// exposes "Save Image"/"Save to Photos", which is the supported way to get
  /// the image into the gallery without a dedicated gallery-saver dependency.
  Future<void> _downloadImage(String src) async {
    try {
      Uint8List bytes;
      String ext = 'png';
      if (src.startsWith('data:')) {
        final commaIdx = src.indexOf(',');
        if (commaIdx == -1) return;
        bytes = base64Decode(src.substring(commaIdx + 1));
        final header = src.substring(0, commaIdx).toLowerCase();
        if (header.contains('jpeg') || header.contains('jpg')) ext = 'jpg';
      } else if (src.startsWith('http://') || src.startsWith('https://')) {
        final resp = await Dio().get<List<int>>(
          src,
          options: Options(responseType: ResponseType.bytes),
        );
        bytes = Uint8List.fromList(resp.data ?? const []);
        if (src.toLowerCase().contains('.jpg') ||
            src.toLowerCase().contains('.jpeg')) {
          ext = 'jpg';
        }
      } else {
        final path = _imageSrcToFilePath(src);
        final resolved = resolveGlazeFilePath(path) ?? path;
        final file = File(resolved);
        if (!await file.exists()) return;
        bytes = await file.readAsBytes();
        final lower = resolved.toLowerCase();
        if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) ext = 'jpg';
      }
      if (bytes.isEmpty) return;

      final tmpDir = await getTemporaryDirectory();
      final tmpFile = File(
        p.join(
          tmpDir.path,
          'glaze_image_${DateTime.now().millisecondsSinceEpoch}.$ext',
        ),
      );
      await tmpFile.writeAsBytes(bytes);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(tmpFile.path)],
          // Required on iPad so the share popover has an anchor rect.
          sharePositionOrigin: const Rect.fromLTWH(0, 0, 1, 1),
        ),
      );
    } catch (e) {
      if (mounted) {
        GlazeErrorDialog.show(context, e, prefix: 'settings_err_failed'.tr());
      }
    }
  }

  /// Recomputes which display regex scripts fire on [msg]'s raw content,
  /// mirroring the tracking done by [ChatMessageMapper] when rendering. Used
  /// so the triggered-items sheet can show the firing regexes alongside the
  /// lorebook / memory entries (parity with Glaze/Vue).
  List<TriggeredEntry> _computeTriggeredRegexes(ChatMessage msg) {
    final scripts = ref.read(displayRegexesProvider).value ?? const [];
    if (scripts.isEmpty) return const [];
    final character = ref.read(characterByIdProvider(widget.charId));
    final persona = ref.read(
      effectivePersonaForChatProvider((
        charId: widget.charId,
        sessionId: widget.state.session?.id,
      )),
    );
    final isUser = msg.role == 'user';
    final triggered = <TriggeredEntry>[];
    applyRegexes(
      msg.content,
      isUser ? 1 : 2,
      1,
      scripts,
      RegexApplyContext(char: character, persona: persona),
      isMarkdown: true,
      triggered: triggered,
    );
    return triggered;
  }

  void _showTriggeredItemsSheet(
    BuildContext context, {
    List<TriggeredEntry> lorebooks = const [],
    List<TriggeredEntry> memories = const [],
    List<TriggeredEntry> regexes = const [],
  }) {
    showTriggeredItemsSheet(
      context,
      lorebooks: lorebooks,
      memories: memories,
      regexes: regexes,
    );
  }

  /// Options sheet for a generated/janitor image (Imagen UI, ported from
  /// Glaze useMessageImageGen.js): Expand → fullscreen, Save → share/save,
  /// Regenerate → re-run image generation for the owning message. The
  /// Regenerate entry is hidden when there is no owning message (e.g. inline
  /// janitor `![](url)` images, which carry no messageId).
  void _showImageOptionsSheet(
    String src,
    String instruction,
    String messageId,
  ) {
    final messages = widget.state.messages;
    final idx = messageId.isEmpty
        ? -1
        : messages.indexWhere((m) => m.id == messageId);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.cs.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: context.cs.outlineVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.fullscreen),
              title: Text('imggen_expand_image'.tr()),
              onTap: () {
                Navigator.pop(sheetCtx);
                _showImageViewer(context, src);
              },
            ),
            ListTile(
              leading: const Icon(Icons.save_alt),
              title: Text('action_save_image'.tr()),
              onTap: () {
                Navigator.pop(sheetCtx);
                _downloadImage(src);
              },
            ),
            if (idx >= 0)
              ListTile(
                leading: const Icon(Icons.refresh),
                title: Text('action_regenerate'.tr()),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  ref
                      .read(chatProvider(widget.charId).notifier)
                      .retryImageGenerationForMessage(idx);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Guards message sending behind an explicitly selected persona. When no
  /// persona is selected in the persona list, shows a notice sheet with a
  /// shortcut to pick one and returns false so the caller aborts the send.
  bool _ensurePersonaSelected() {
    if (ref.read(activePersonaIdProvider) != null) return true;
    GlazeBottomSheet.show<void>(
      context,
      title: 'persona_required_title'.tr(),
      bigInfo: BottomSheetBigInfo(
        icon: Icons.person_off_outlined,
        description: 'persona_required_desc'.tr(),
        buttonText: 'persona_required_select'.tr(),
        onButtonTap: () {
          Navigator.of(context, rootNavigator: true).pop();
          showModalBottomSheet<void>(
            context: context,
            useRootNavigator: true,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => const PersonaListScreen(),
          );
        },
      ),
    );
    return false;
  }

  /// Guards message sending behind a configured API. When no API config is
  /// available, shows a notice sheet with a shortcut to the API settings and
  /// returns false so the caller aborts the send.
  bool _ensureApiSelected() {
    if (ref.read(activeApiConfigProvider) != null) return true;
    GlazeBottomSheet.show<void>(
      context,
      title: 'api_required_title'.tr(),
      bigInfo: BottomSheetBigInfo(
        icon: Icons.cloud_off_outlined,
        description: 'api_required_desc'.tr(),
        buttonText: 'api_required_select'.tr(),
        onButtonTap: () {
          Navigator.of(context, rootNavigator: true).pop();
          showModalBottomSheet<void>(
            context: context,
            useRootNavigator: true,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            barrierColor: Colors.black54,
            builder: (_) => const ApiSettingsScreen(),
          );
        },
      ),
    );
    return false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // The native WebView freezes its JS while the app is backgrounded, so a
    // bottom-inset change pushed during the background transition (e.g. the
    // keyboard hiding) can be dropped. If the app then resumes with the
    // keyboard re-opening at the same height, Dart's bottomInset is unchanged
    // so the per-frame diff in the sync dispatcher never re-pushes it — leaving
    // stale, oversized reserved space under the input bar. Re-assert the
    // current inset once now and again after the keyboard settles; the JS side
    // no-ops when the padding already matches.
    void resync() {
      if (!mounted) return;
      unawaited(
        _webViewStateKey.currentState?.applyBottomInset(
              _lastMessageListBottom,
            ) ??
            Future<void>.value(),
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => resync());
    Future<void>.delayed(const Duration(milliseconds: 400), resync);
  }

  @override
  Widget build(BuildContext context) {
    final isEditingMessage =
        ref.watch(editingMessageIdProvider(widget.charId)) != null;
    final memoryActivity = ref.watch(lastMemoryActivityProvider(widget.charId));
    final memoryEnabled = ref.watch(
      memoryGlobalSettingsProvider.select((s) => s.enabled),
    );
    ref.listen<String?>(editingMessageIdProvider(widget.charId), (prev, next) {
      if (next != null) {
        if (widget.drawerCtrl.inputFocus.hasFocus) {
          widget.drawerCtrl.inputFocus.unfocus();
        }
        if (_selectionCtrl.isSelectionMode ||
            _selectionCtrl.selectedMessageIds.isNotEmpty) {
          setState(() {
            _selectionCtrl.clearSelection();
          });
        }
      }
    });
    final appSettings = ref.watch(appSettingsProvider).value;
    final batterySaverMode = appSettings?.batterySaver ?? false;
    final preset = batteryAware(
      ref,
      batterySaverMode,
      themeProvider.select((p) => p.activePreset),
    );
    final batterySaver = appSettings?.batterySaver ?? false;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final messageListTop = MediaQuery.paddingOf(context).top + 10 + 56;

    final bgBlur = preset.bgBlur > 0 ? preset.bgBlur : 0.0;
    final bgOpacity = preset.bgOpacity.clamp(0.0, 1.0);
    final bgPath = preset.bgImage;
    final fontStyle = batteryAware(
      ref,
      batterySaverMode,
      chatFontStyleProvider,
    );
    final fontDataUrl = batteryAware(
      ref,
      batterySaverMode,
      chatFontDataProvider.select((p) => p.value),
    );
    final character = batteryAware(
      ref,
      batterySaverMode,
      characterByIdProvider(widget.charId),
    );
    final personaKey = (
      charId: widget.charId,
      sessionId: widget.state.session?.id,
    );
    final effectivePersona = batteryAware(
      ref,
      batterySaverMode,
      effectivePersonaForChatProvider(personaKey),
    );
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
    final memBook = batteryAware(
      ref,
      batterySaverMode,
      memoryBookProvider(widget.state.session?.id ?? ''),
    );
    final greetingTotal = character == null
        ? 0
        : ((character.firstMes?.isNotEmpty == true ? 1 : 0) +
              character.alternateGreetings.where((g) => g.isNotEmpty).length);

    return AnimatedBuilder(
      animation: widget.drawerCtrl.drawerAnim,
      builder: (context, _) {
        final progress = widget.drawerCtrl.drawerAnim.value;
        final bool drawerActive =
            widget.drawerCtrl.drawerOpen || widget.drawerCtrl.switchingToDrawer;
        final targetDrawerInset = drawerActive
            ? widget.drawerCtrl.activeDrawerHeight * progress
            : 0.0;
        final panelHeight = math.max(targetDrawerInset, widget.keyboardHeight);
        final factor = math.min(1.0, panelHeight / math.max(1.0, safeBottom));
        final effectiveBottomInset = panelHeight + (safeBottom * (1 - factor));
        // The memory activity card floats under the header (top of the chat).
        // Hidden entirely when memory books are disabled globally.
        final showMemoryCard =
            memoryActivity != null &&
            memoryActivity.hasDiagnostics &&
            memoryEnabled;
        // When the card is dismissed its widget unmounts, so the size notifier
        // can't fire — reclaim the reserved top space on the next frame.
        if (!showMemoryCard && _memoryCardHeight != 0.0) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _checkHeight());
        }
        // Reserve room at the top so the card sits in a gap under the header
        // instead of covering the first visible messages.
        final memoryTopReserve = showMemoryCard ? _memoryCardHeight + 8 : 0.0;
        final effectiveTopInset = messageListTop + memoryTopReserve;

        final messageListBottom = _inputBarHeight + effectiveBottomInset;
        _lastMessageListBottom = messageListBottom;
        final showScrollBtn = _showScrollToBottom && !widget.search.showSearch;

        final animatedBottomPanelInset =
            panelHeight + (safeBottom * (1 - factor));
        final renderDrawer =
            !isDesktopLayout(context) &&
            (widget.drawerCtrl.drawerOpen || progress > 0.001);

        return Stack(
          children: [
            Positioned.fill(
              child: NotificationListener<UserScrollNotification>(
                onNotification: (notification) {
                  // Do NOT drive the header from Flutter scroll notifications.
                  // The chat list is an InAppWebView platform view whose internal
                  // scroll never bubbles here — the only notifications this can
                  // catch are from stray Flutter scrollables inside the subtree
                  // (panels, overlays, dropdowns). Forwarding those flipped
                  // `_isHeaderHidden` out of band while JS still believed the
                  // opposite, and since JS only emits header events on
                  // transitions (edge-triggered) it never corrected the desync,
                  // leaving the header frozen. JS `onHeaderScroll` is the single
                  // source of truth (see ScrollCallbacks.onHeaderScroll below).
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
                    topInset: effectiveTopInset,
                    charName: character?.name,
                    charColor: character?.color,
                    personaName: effectivePersona?.name,
                    greetingTotal: greetingTotal,
                    chatLayout: preset.chatLayout,
                    themeSyncKey: _chatWebViewThemeSyncKey(
                      preset,
                      preset.chatLayout,
                    ),
                    elementOpacity: preset.elementOpacity,
                    elementBlur: preset.elementBlur,
                    uiFontWeight: preset.uiFontWeight,
                    userMessageFontWeight: preset.userMessageFontWeight,
                    charMessageFontWeight: preset.charMessageFontWeight,
                    userBubbleRadius: preset.userBubbleRadius,
                    charBubbleRadius: preset.charBubbleRadius,
                    userBubbleGradient: preset.userBubbleGradientParsed,
                    charBubbleGradient: preset.charBubbleGradientParsed,
                    textBgOpacity: preset.textBgOpacity,
                    showUserAvatar: preset.showUserAvatar,
                    showCharAvatar: preset.showCharAvatar,
                    showUserName: preset.showUserName,
                    showCharName: preset.showCharName,
                    charAvatarPath: character?.avatarPath,
                    personaAvatarPath: effectivePersona?.avatarPath,
                    bgImagePath: bgPath,
                    bgBlur: bgBlur,
                    bgOpacity: bgOpacity,
                    bgNoiseOpacity: preset.bgNoiseOpacity,
                    bgNoiseIntensity: preset.bgNoiseIntensity,
                    bgDim: preset.bgDim,
                    chatBgMode: preset.chatBgMode,
                    chatBgColor: preset.chatBgColorParsed,
                    chatFontName: fontStyle.fontFamily,
                    chatFontDataUrl: fontDataUrl,
                    chatFontSize: fontStyle.fontSize,
                    chatLetterSpacing: fontStyle.letterSpacing,
                    memoryEntries: memBook.value?.entries ?? [],
                    memoryDrafts: memBook.value?.pendingDrafts ?? [],
                    sessionId: widget.state.session?.id,
                    visibleStartIndex: widget.state.visibleStartIndex,
                    batterySaver: appSettings?.batterySaver ?? false,
                    hideMessageId:
                        preset.hideMessageId ??
                        (appSettings?.hideMessageId ?? false),
                    hideGenerationTime:
                        preset.hideGenerationTime ??
                        (appSettings?.hideGenerationTime ?? false),
                    hideTokenCount:
                        preset.hideTokenCount ??
                        (appSettings?.hideTokenCount ?? false),
                    disableSwipeRegeneration:
                        appSettings?.disableSwipeRegeneration ?? false,
                    messageActions: MessageActionsCallbacks(
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
                      onSwipe: (id, direction) {
                        final idx = widget.state.messages.indexWhere(
                          (m) => m.id == id,
                        );
                        if (idx < 0) return;
                        final dir = direction == 'right' ? 1 : -1;
                        ref
                            .read(chatProvider(widget.charId).notifier)
                            .changeSwipe(idx, dir, fromSwipe: true);
                        ref
                            .read(memorySidecarPrewarmCacheProvider)
                            .invalidateSession(widget.state.session?.id ?? '');
                      },
                      onAgentSwipe: (id, direction) {
                        final idx = widget.state.messages.indexWhere(
                          (m) => m.id == id,
                        );
                        if (idx < 0) return;
                        final dir = direction == 'right' ? 1 : -1;
                        ref
                            .read(chatProvider(widget.charId).notifier)
                            .changeAgentSwipe(idx, dir, fromSwipe: true);
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
                      onRegenerate: (id, mode) {
                        ref
                            .read(chatProvider(widget.charId).notifier)
                            .regenerateLastAssistant();
                        ref
                            .read(memorySidecarPrewarmCacheProvider)
                            .invalidateSession(widget.state.session?.id ?? '');
                      },
                      onRerunCleaner: (id) {
                        ref
                            .read(chatProvider(widget.charId).notifier)
                            .rerunCleaner(id);
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
                            memories: msg.triggeredMemories,
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
                        _showTriggeredItemsSheet(
                          context,
                          lorebooks: msg.triggeredLorebooks,
                          memories: msg.triggeredMemories,
                          regexes: _computeTriggeredRegexes(msg),
                        );
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
                              .editMessage(
                                idx,
                                text,
                                tagStart: '<think>',
                                tagEnd: '</think>',
                              );
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
                        if (activeEditingId == id &&
                            widget.drawerCtrl.inputFocus.hasFocus) {
                          widget.drawerCtrl.inputFocus.unfocus();
                        }
                      },
                    ),
                    imageGenActions: ImageGenCallbacks(
                      onImgRetry: (instruction, messageId) {
                        final allMsgs = widget.state.messages;
                        final idx = allMsgs.indexWhere(
                          (m) => m.id == messageId,
                        );
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
                        final idx = allMsgs.indexWhere(
                          (m) => m.id == messageId,
                        );
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
                      onImgDownload: _downloadImage,
                      onImgOptions: _showImageOptionsSheet,
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
                            _selectionCtrl.updateSelection(ids);
                          });
                        }
                      },
                      onImageClick: (imageUrl) {
                        _showImageViewer(context, imageUrl);
                      },
                    ),
                    isSelectionMode: _selectionCtrl.isSelectionMode,
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
                // Mirror Vue ChatInput (`v-if="!isSearchMode"`): the
                // scroll-to-bottom button is suppressed while searching.
                ignoring: !showScrollBtn,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  opacity: showScrollBtn ? 1 : 0,
                  child: AnimatedSlide(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    offset: showScrollBtn ? Offset.zero : const Offset(0, 0.2),
                    child: GestureDetector(
                      onTap: _scrollToBottom,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: context.cs.surface.withValues(alpha: 0.9),
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
            // Memory activity card: floats under the header, over the chat.
            if (showMemoryCard)
              Positioned(
                top: messageListTop,
                left: 12,
                right: 12,
                child: NotificationListener<SizeChangedLayoutNotification>(
                  onNotification: (n) {
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _checkHeight(),
                    );
                    return true;
                  },
                  child: SizeChangedLayoutNotifier(
                    child: Container(
                      key: _memoryCardKey,
                      child: MemoryActivityCard(
                        activity: memoryActivity,
                        expanded: _showMemoryActivity,
                        sessionId: widget.state.session?.id,
                        onToggle: () {
                          setState(() {
                            _showMemoryActivity = !_showMemoryActivity;
                          });
                        },
                      ),
                    ),
                  ),
                ),
              ),
            // POST-cleaner live status card. Rendered AFTER the memory activity
            // card so it sits ABOVE it in z-order — the Stop button must stay
            // clickable even when the memory card is visible underneath.
            Positioned(
              left: 12,
              right: 12,
              top: messageListTop + memoryTopReserve,
              child: const PostCleanerStatusCard(),
            ),
            // Studio tracker-cycle live status card. Shown during generation
            // while Studio trackers / final generator are running.
            Positioned(
              left: 12,
              right: 12,
              top: messageListTop + memoryTopReserve + 56,
              child: const StudioStatusCard(),
            ),
            // Bottom panel: drawer + input bar
            Positioned.fill(
              child: Stack(
                children: [
                  if (renderDrawer)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom:
                          -widget.drawerCtrl.activeDrawerHeight *
                          (1 - progress),
                      height: widget.drawerCtrl.activeDrawerHeight,
                      child:
                          widget.drawerCtrl.activePanel ==
                              DrawerPanel.quickReplies
                          ? QuickRepliesPanel(
                              charId: widget.charId,
                              onClose: () => widget.drawerCtrl.closeDrawer(),
                              disableEffects:
                                  batterySaver &&
                                  widget.drawerCtrl.isDrawerAnimating,
                            )
                          : MagicDrawerPanel(
                              charId: widget.charId,
                              onClose: () => widget.drawerCtrl.closeDrawer(),
                              disableEffects:
                                  batterySaver &&
                                  widget.drawerCtrl.isDrawerAnimating,
                              onScrollToMessage: (id) =>
                                  _scrollToTargetMessage(id),
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
                                  final allSelectedHidden = _selectionCtrl
                                      .allSelectedHidden(widget.state.messages);
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
                                    searchMatchCount: widget.search.matchCount,
                                    searchCurrentIndex:
                                        widget.search.searchCurrentIndex,
                                    onSearchNext: widget.search.onSearchNext,
                                    onSearchPrev: widget.search.onSearchPrev,
                                    isEditingMessage: isEditingMessage,
                                    isSelectionMode:
                                        _selectionCtrl.isSelectionMode,
                                    selectedCount: _selectionCtrl
                                        .selectedMessageIds
                                        .length,
                                    allSelectedHidden: allSelectedHidden,
                                    onCancelSelection: () {
                                      setState(() {
                                        _selectionCtrl.clearSelection();
                                      });
                                    },
                                    onHideSelected: () async {
                                      await _selectionCtrl.hideSelected(
                                        ref,
                                        widget.charId,
                                        widget.state.messages,
                                      );
                                      if (mounted) setState(() {});
                                    },
                                    onDeleteSelected: () async {
                                      await _selectionCtrl.deleteSelected(
                                        ref,
                                        widget.charId,
                                        widget.state.messages,
                                      );
                                      if (mounted) setState(() {});
                                    },
                                    isDrawerOpen:
                                        (widget.drawerCtrl.drawerOpen ||
                                            widget
                                                .drawerCtrl
                                                .switchingToDrawer) &&
                                        widget.drawerCtrl.activePanel ==
                                            DrawerPanel.magic,
                                    isQuickRepliesOpen:
                                        (widget.drawerCtrl.drawerOpen ||
                                            widget
                                                .drawerCtrl
                                                .switchingToDrawer) &&
                                        widget.drawerCtrl.activePanel ==
                                            DrawerPanel.quickReplies,
                                    virtualKeyboardSend:
                                        widget.virtualKeyboardSend,
                                    enterToSend: widget.enterToSend,
                                    canSend: () =>
                                        _ensurePersonaSelected() &&
                                        _ensureApiSelected(),
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
                                    onSendWithImage:
                                        (text, guidanceText, imageDataUrl) {
                                          ref
                                              .read(
                                                chatProvider(
                                                  widget.charId,
                                                ).notifier,
                                              )
                                              .sendMessage(
                                                text,
                                                guidanceText: guidanceText,
                                                imageDataUrl: imageDataUrl,
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
                                                !widget.state.isGenerating) {
                                              notifier.abortImageGeneration();
                                            } else {
                                              notifier.abortGeneration();
                                            }
                                          }
                                        : null,
                                    onMagicDrawer: () =>
                                        widget.drawerCtrl.toggleDrawer(context),
                                    onQuickReplies: () =>
                                        widget.drawerCtrl.toggleDrawer(
                                          context,
                                          panel: DrawerPanel.quickReplies,
                                        ),
                                    onImpersonate: () => ref
                                        .read(
                                          chatProvider(widget.charId).notifier,
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
              ),
            ),
          ],
        );
      },
    );
  }
}
