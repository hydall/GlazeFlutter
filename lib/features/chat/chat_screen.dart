import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
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
import 'bridge/chat_overlay_blur_region.dart';
import 'widgets/chat_blur_region_tracker.dart';
import 'widgets/magic_drawer.dart';
import 'widgets/memory_activity_card.dart';
import 'widgets/post_cleaner_status_card.dart';
import 'widgets/post_gen_status_card.dart';
import 'widgets/studio_status_card.dart';
import 'widgets/quick_replies_panel.dart';
import 'widgets/chat_webview_widget.dart';
import 'widgets/chat_input_ui_state.dart';
import '../../shared/widgets/fullscreen_editor.dart';
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
    // Seed the drawer height from the last measured keyboard so the magic /
    // quick-replies panel opens at the right size on the first tap.
    unawaited(_drawerCtrl.restoreKeyboardHeight());
    _search = ChatSearchDelegate();
    // The header now lives inside the WebView; toggling search mode must rebuild
    // this screen so `hideHeader` (native search bar) and the WebView's
    // `isSearchActive` flag both follow the delegate.
    _search.addListener(_onSearchChanged);
    if (widget.forceNewSession || widget.initialSessionIndex != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _applySessionPreference();
      });
    }
  }

  @override
  void dispose() {
    _drawerCtrl.dispose();
    _search.removeListener(_onSearchChanged);
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  /// Back-gesture precedence, shared by the scaffold's `onBack` (hardware /
  /// swipe back) and the in-WebView header's back button. Dismisses any open
  /// overlay before navigating up.
  void _handleBack() {
    // The compose field lives in the WebView now; ask it to blur (dismiss the
    // on-screen keyboard) before any drawer close / navigation.
    if (_drawerCtrl.requestBlurIfFocused()) {
      return;
    }
    // Covers both the open magic drawer / quick replies panel and the brief
    // keyboard→drawer transition window; closeDrawer handles both.
    if (_drawerCtrl.drawerOpen || _drawerCtrl.switchingToDrawer) {
      _drawerCtrl.closeDrawer();
      return;
    }
    if (_search.showSearch) {
      _search.closeSearch();
      return;
    }
    context.go('/');
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

    final appSettings = ref.watch(appSettingsProvider).value;
    final virtualKeyboardSend = appSettings?.virtualKeyboardSend ?? false;
    final enterToSend = appSettings?.enterToSend ?? true;
    final batterySaver = appSettings?.batterySaver ?? false;
    _drawerCtrl.setBatterySaverMode(batterySaver);

    // The on-screen keyboard is now WebView-owned (the compose field lives in
    // the WebView). Flutter's viewInsets no longer track it reliably, so the
    // keyboard↔drawer swap is driven by the WebView's onKeyboardInset reports
    // (see ChatDrawerController.handleWebViewKeyboard). This value is still read
    // for the blur-region settle gate below.
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;

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
        // The body is a full-screen chat WebView that now owns the whole
        // header (avatar + name + session + back/search buttons) as a real
        // backdrop-filter strip. The native app bar is only shown for the
        // search text field (kept native for the platform keyboard); the rest
        // of the time it is hidden and the WebView header takes over.
        headerBlurViaWebView: true,
        hideHeader: !_search.showSearch,
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
            : null,
        onBack: _handleBack,
        actions: const [],
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
                  sessionName: sessionName,
                  onHeaderBack: _handleBack,
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

  /// Session display name shown as the in-WebView header subtitle.
  final String sessionName;

  /// Back-gesture handler shared with the scaffold, invoked by the
  /// in-WebView header's back button.
  final VoidCallback onHeaderBack;
  final bool virtualKeyboardSend;
  final bool enterToSend;
  final String? targetMessageId;

  const _ChatBody({
    required this.charId,
    required this.state,
    required this.drawerCtrl,
    required this.search,
    required this.keyboardHeight,
    required this.sessionName,
    required this.onHeaderBack,
    this.virtualKeyboardSend = false,
    this.enterToSend = true,
    this.targetMessageId,
  });

  @override
  ConsumerState<_ChatBody> createState() => _ChatBodyState();
}

class _ChatBodyState extends ConsumerState<_ChatBody>
    with WidgetsBindingObserver {
  /// Measured height of the floating [MemoryActivityCard] (0 when hidden) so
  /// the message list reserves room at the *top* for it — otherwise the card
  /// floats under the header and covers the first visible messages.
  double _memoryCardHeight = 0.0;
  final GlobalKey _memoryCardKey = GlobalKey();

  final _selectionCtrl = ChatMessageSelectionController();
  bool _showMemoryActivity = false;
  final GlobalKey<ChatWebViewWidgetState> _webViewStateKey = GlobalKey();

  /// Rects of the glass overlays (header + input bar elements) measured in
  /// WebView-local coordinates and mirrored into the WebView so the messages
  /// scrolling underneath get blurred (Flutter's BackdropFilter cannot
  /// sample the platform view — see [ChatOverlayBlurRegion]).
  final ChatBlurRegionRegistry _blurRegistry = ChatBlurRegionRegistry();
  List<ChatOverlayBlurRegion> _blurRegions = const [];
  bool _blurMeasureScheduled = false;

  /// Keyboard-inset settle tracking for the WebView-bound bottom inset.
  /// While the keyboard animates, the WebView receives the predicted end
  /// value once (per-frame `setBottomPadding` pushes relayout the whole
  /// message list in the WebView every frame — the main keyboard-jank
  /// source). [_keyboardSettled] flips back once the inset stops changing
  /// and the actual value is pushed as a correction — a no-op in JS when
  /// the prediction was right.
  bool _keyboardSettled = true;
  Timer? _keyboardSettleTimer;

  @override
  void didUpdateWidget(covariant _ChatBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.keyboardHeight != widget.keyboardHeight) {
      _keyboardSettled = false;
      _keyboardSettleTimer?.cancel();
      _keyboardSettleTimer = Timer(const Duration(milliseconds: 100), () {
        if (!mounted) return;
        setState(() => _keyboardSettled = true);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Let the drawer controller dismiss the WebView-owned keyboard (there is no
    // Flutter FocusNode to unfocus) — e.g. on the back gesture. The closure
    // resolves the WebView state lazily, so it is safe to set before build.
    widget.drawerCtrl.onRequestBlurInput =
        () => _webViewStateKey.currentState?.blurInput();
    // Re-measure when the input bar swaps tracked elements (e.g. entering
    // search/selection mode) without this widget rebuilding.
    _blurRegistry.addListener(_scheduleBlurMeasure);
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
    // The input bar now lives in the WebView (it owns its own height); only the
    // floating memory card is still measured on the Flutter side so the message
    // list reserves top room for it.
    final memoryHeight = _memoryCardKey.currentContext?.size?.height ?? 0.0;
    if (memoryHeight != _memoryCardHeight) {
      setState(() => _memoryCardHeight = memoryHeight);
    }
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

  /// Wires the in-WebView input bar's gestures to the same chatProvider actions
  /// and drawer controls the native ChatInputBar used to drive (Phase 2).
  InputCallbacks _buildInputCallbacks() {
    final notifier = ref.read(chatProvider(widget.charId).notifier);
    return InputCallbacks(
      onInputSend: (text, guidance, imageDataUrl) {
        // Prerequisites (persona / API): on failure keep the composed text —
        // the WebView is NOT told to clear, so nothing is lost.
        if (!_ensurePersonaSelected() || !_ensureApiSelected()) return;
        final g = (guidance != null && guidance.isNotEmpty) ? guidance : null;
        if (imageDataUrl != null && imageDataUrl.isNotEmpty) {
          notifier.sendMessage(
            text,
            guidanceText: g,
            imageDataUrl: imageDataUrl,
          );
        } else {
          if (text.trim().isEmpty) return;
          notifier.sendMessage(text, guidanceText: g);
        }
        _webViewStateKey.currentState?.clearInput();
      },
      onInputStop: () {
        if (widget.state.isGeneratingImage &&
            !widget.state.isGenerating &&
            !widget.state.isPostGenRunning) {
          notifier.abortImageGeneration();
        } else {
          notifier.abortGeneration();
        }
      },
      onInputImpersonate: () => notifier.regenerateLastAssistant(),
      onInputDraftChanged: (text) => notifier.saveDraft(text),
      onInputFocus: (focused) {
        // The WebView owns the compose field's focus now; the controller closes
        // the native drawer when the user returns to typing (the focus side of
        // the keyboard↔drawer swap).
        widget.drawerCtrl.setInputFocused(focused);
      },
      onKeyboardInset: (height, open) {
        // WebView (visualViewport) keyboard geometry: persists the height and
        // drives the swap / collision handling.
        widget.drawerCtrl.handleWebViewKeyboard(height, open);
      },
      onFullScreenEditor: (text) async {
        await FullscreenEditorScreen.show(
          context,
          title: 'chat_message_title'.tr(),
          initialValue: text,
          hintText: 'chat_placeholder'.tr(),
          onChanged: (value) {
            _webViewStateKey.currentState?.applyDraft(value);
            notifier.saveDraft(value);
          },
        );
      },
      onMagicDrawer: () => widget.drawerCtrl.toggleDrawer(),
      onQuickReplies: () =>
          widget.drawerCtrl.toggleDrawer(panel: DrawerPanel.quickReplies),
      onSearchNext: widget.search.onSearchNext,
      onSearchPrev: widget.search.onSearchPrev,
      onCancelSelection: () =>
          setState(() => _selectionCtrl.clearSelection()),
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
      onScrollToBottomTap: () =>
          _webViewStateKey.currentState?.scrollToBottom(smooth: true),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.drawerCtrl.onRequestBlurInput = null;
    _keyboardSettleTimer?.cancel();
    _blurRegistry.dispose();
    super.dispose();
  }

  /// Coalesces measurement requests into one post-frame pass. Scheduled on
  /// every build (keyboard/drawer animations move the input bar each frame)
  /// and on registry changes.
  void _scheduleBlurMeasure() {
    if (_blurMeasureScheduled) return;
    _blurMeasureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _blurMeasureScheduled = false;
      _measureBlurRegions();
    });
  }

  void _measureBlurRegions() {
    if (!mounted) return;
    // Transient layout: while the keyboard or drawer animates, the overlays
    // move every frame — re-measuring would push per-frame region updates
    // over the JS bridge and repaint the Flutter blur sandwich each frame.
    // A build is guaranteed at settle (the keyboard settle-timer setState,
    // the drawer animation's final tick with isAnimating == false), and it
    // re-schedules this measure, so the final rects always land.
    if (!_keyboardSettled || widget.drawerCtrl.isDrawerAnimating) return;
    final box = _webViewStateKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    // The header no longer needs a mirrored blur region: it lives inside the
    // WebView now and draws its own backdrop-filter strip (see #chat-header in
    // styles.css). Only the input-bar overlays are still measured here.
    final regions = <ChatOverlayBlurRegion>[..._blurRegistry.measure(box)];
    regions.sort((a, b) => a.id.compareTo(b.id));
    if (!listEquals(regions, _blurRegions)) {
      setState(() => _blurRegions = regions);
    }
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
        if (widget.drawerCtrl.inputFocused) {
          _webViewStateKey.currentState?.blurInput();
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
    final safeTop = MediaQuery.paddingOf(context).top;
    final messageListTop = safeTop + 10 + 56;

    final bgBlur = preset.bgBlur > 0 ? preset.bgBlur : 0.0;
    final bgOpacity = preset.bgOpacity.clamp(0.0, 1.0);
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
    // Source for the in-WebView background copy, mirroring what the Flutter
    // ChatWebViewSurface._background() paints for each chatBgMode so the
    // duplicated background matches. 'color' has no image.
    final bgPath = switch (preset.chatBgMode) {
      'custom' => preset.chatBgImage,
      'avatar' => character?.avatarPath,
      'color' => null,
      _ => preset.bgImage, // 'inherit'
    };
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

        final renderDrawer =
            !isDesktopLayout(context) &&
            (widget.drawerCtrl.drawerOpen || progress > 0.001);

        // The WebView owns its own bottom padding: it measures the in-WebView
        // input bar and lifts it above the *keyboard* itself (visualViewport).
        // Flutter therefore pushes only the native drawer height — never the
        // keyboard inset, which would double-count with the WebView's own lift.
        // On desktop the drawer isn't a bottom panel (`renderDrawer` false), so
        // it contributes no inset there.
        final panelInset = (renderDrawer && drawerActive)
            ? widget.drawerCtrl.activeDrawerHeight
            : 0.0;

        // The overlays move with every rebuild here (keyboard, drawer
        // animation, input growth), so re-measure their rects post-frame.
        _scheduleBlurMeasure();

        return Stack(
          children: [
            Positioned.fill(
              child: NotificationListener<UserScrollNotification>(
                onNotification: (notification) {
                  // The header lives inside the WebView and hides itself on
                  // scroll; Flutter no longer reacts to scroll notifications
                  // here. The chat list is an InAppWebView platform view whose
                  // internal scroll never bubbles up anyway — the only
                  // notifications this could catch are from stray Flutter
                  // scrollables inside the subtree (panels, overlays), which we
                  // deliberately ignore.
                  return false;
                },
                child: RepaintBoundary(
                  child: ChatWebViewWidget(
                    key: _webViewStateKey,
                    messages: widget.state.visibleMessages,
                    charId: widget.charId,
                    isGenerating: widget.state.isGenerating,
                    isGeneratingImage: widget.state.isGeneratingImage,
                    isPostGenRunning: widget.state.isPostGenRunning,
                    regenTargetId: widget.state.regenTargetId,
                    topInset: effectiveTopInset,
                    panelInset: panelInset,
                    sessionName: widget.sessionName,
                    safeTop: safeTop,
                    isSearchActive: widget.search.showSearch,
                    initialDraft: widget.state.session?.draft ?? '',
                    inputState: ChatInputUiState(
                      safeBottom: safeBottom,
                      placeholder: 'chat_placeholder'.tr(),
                      guidancePlaceholder: 'guidance_placeholder'.tr(),
                      isGenerating:
                          widget.state.isGenerating ||
                          widget.state.isGeneratingImage ||
                          widget.state.isPostGenRunning,
                      isEditing: isEditingMessage,
                      isDrawerOpen:
                          (widget.drawerCtrl.drawerOpen ||
                              widget.drawerCtrl.switchingToDrawer) &&
                          widget.drawerCtrl.activePanel == DrawerPanel.magic,
                      isQuickRepliesOpen:
                          (widget.drawerCtrl.drawerOpen ||
                              widget.drawerCtrl.switchingToDrawer) &&
                          widget.drawerCtrl.activePanel ==
                              DrawerPanel.quickReplies,
                      isSelectionMode: _selectionCtrl.isSelectionMode,
                      showSearch: widget.search.showSearch,
                      searchLabel: widget.search.matchCount > 0
                          ? '${widget.search.searchCurrentIndex + 1} of ${widget.search.matchCount} matches'
                          : 'search_no_results'.tr(),
                      selectionLabel:
                          '${_selectionCtrl.selectedMessageIds.length} ${'selected_count'.tr()}',
                      selectedCount: _selectionCtrl.selectedMessageIds.length,
                      allSelectedHidden: _selectionCtrl.allSelectedHidden(
                        widget.state.messages,
                      ),
                      enterToSend: widget.enterToSend,
                      virtualKeyboardSend: widget.virtualKeyboardSend,
                    ),
                    inputActions: _buildInputCallbacks(),
                    blurRegions: (batterySaver || preset.elementBlur <= 0)
                        ? const <ChatOverlayBlurRegion>[]
                        : _blurRegions,
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
                            widget.drawerCtrl.inputFocused) {
                          _webViewStateKey.currentState?.blurInput();
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
                    // Hide-on-scroll (header) and the scroll-to-bottom button
                    // are both owned by the WebView now, so Flutter wires no
                    // scroll callbacks.
                    miscActions: MiscCallbacks(
                      onStop: () {
                        final notifier = ref.read(
                          chatProvider(widget.charId).notifier,
                        );
                        if (widget.state.isGeneratingImage &&
                            !widget.state.isGenerating &&
                            !widget.state.isPostGenRunning) {
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
                      onHeaderBack: widget.onHeaderBack,
                      onHeaderSearch: () => widget.search.openSearch(),
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
            // The bottom fade gradient and scroll-to-bottom button now live
            // inside the WebView alongside the input bar (Phase 2).
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
            // Post-generation tasks (Ledger and extension blocks) live status.
            Positioned(
              left: 12,
              right: 12,
              top: messageListTop + memoryTopReserve + 112,
              child: const PostGenStatusCard(),
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
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
