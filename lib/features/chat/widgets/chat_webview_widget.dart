import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/active_regex_provider.dart';
import '../../../core/state/character_provider.dart';
import '../../../core/state/persona_resolution.dart';
import '../../../../shared/theme/theme_font_provider.dart';
import '../bridge/chat_bridge_controller.dart';
import '../bridge/chat_webview_bridge_host.dart';
import '../bridge/chat_webview_theme_builder.dart';
import '../../../core/models/chat_message.dart';
import '../../../shared/widgets/glaze_toast.dart';
import '../../extensions/services/panel_host_service.dart';
import '../bridge/chat_bridge_registry.dart';
import 'chat_message_sync.dart';
import 'chat_webview_build_listeners.dart';
import 'chat_webview_initializer.dart';
import 'chat_webview_panel_refresher.dart';
import 'chat_webview_surface.dart';
import 'chat_webview_sync_dispatcher.dart';
import 'webview_callbacks.dart';

const String _kStreamingId = '__streaming__';
const Duration _kBridgeOpTimeout = Duration(seconds: 15);
const Duration _kWebViewInitTimeout = Duration(seconds: 45);
const Duration _kJsBridgeReadyTimeout = Duration(seconds: 30);

class ChatWebViewWidget extends ConsumerStatefulWidget {
  final String charId;
  final String? charName;
  final String? charColor;
  final String? personaName;
  final String? personaColor;
  final String? charAvatarPath;
  final String? personaAvatarPath;
  final String? bgImagePath;
  final double bgBlur;
  final double bgOpacity;
  final double bgNoiseOpacity;
  final double bgNoiseIntensity;
  final double bgDim;
  final List<ChatMessage> messages;
  final bool isGenerating;
  final bool isGeneratingImage;
  final double bottomInset;
  final double topInset;
  final String? searchQuery;
  final int searchCurrentIndex;
  final String? chatLayout;

  /// Changes when preset colors/layout tokens affecting the WebView change.
  final String? themeSyncKey;
  final double elementOpacity;
  final double elementBlur;
  final int greetingTotal;
  final String? chatFontName;
  final String? chatFontDataUrl;
  final double chatFontSize;
  final double chatLetterSpacing;
  final List<dynamic> memoryEntries;
  final List<dynamic> memoryDrafts;
  final String? sessionId;
  final int visibleStartIndex;
  final String? regenTargetId;
  final bool isSelectionMode;
  final bool batterySaver;
  final bool hideMessageId;
  final bool hideGenerationTime;
  final bool hideTokenCount;
  final bool disableSwipeRegeneration;

  // Callback objects
  final MessageActionsCallbacks messageActions;
  final EditActionsCallbacks editActions;
  final ImageGenCallbacks imageGenActions;
  final ScrollCallbacks scrollActions;
  final MiscCallbacks miscActions;

  const ChatWebViewWidget({
    super.key,
    required this.charId,
    this.charName,
    this.charColor,
    this.personaName,
    this.personaColor,
    this.charAvatarPath,
    this.personaAvatarPath,
    this.bgImagePath,
    this.bgBlur = 0.0,
    this.bgOpacity = 1.0,
    this.bgNoiseOpacity = 0.0,
    this.bgNoiseIntensity = 1.0,
    this.bgDim = 0.0,
    required this.messages,
    required this.isGenerating,
    this.isGeneratingImage = false,
    this.bottomInset = 0,
    this.topInset = 0,
    this.searchQuery,
    this.searchCurrentIndex = 0,
    this.chatLayout,
    this.themeSyncKey,
    this.elementOpacity = 0.8,
    this.elementBlur = 12,
    this.greetingTotal = 0,
    this.chatFontName,
    this.chatFontDataUrl,
    this.chatFontSize = 15.0,
    this.chatLetterSpacing = 0.0,
    this.memoryEntries = const [],
    this.memoryDrafts = const [],
    this.sessionId,
    this.visibleStartIndex = 0,
    this.regenTargetId,
    this.isSelectionMode = false,
    this.batterySaver = false,
    this.hideMessageId = false,
    this.hideGenerationTime = false,
    this.hideTokenCount = false,
    this.disableSwipeRegeneration = false,
    this.messageActions = const MessageActionsCallbacks(),
    this.editActions = const EditActionsCallbacks(),
    this.imageGenActions = const ImageGenCallbacks(),
    this.scrollActions = const ScrollCallbacks(),
    this.miscActions = const MiscCallbacks(),
  });

  @override
  ConsumerState<ChatWebViewWidget> createState() => ChatWebViewWidgetState();
}

class ChatWebViewWidgetState extends ConsumerState<ChatWebViewWidget>
    with AutomaticKeepAliveClientMixin {
  ChatBridgeController? _bridge;
  bool _ready = false;
  bool _sessionSwitching = false;
  Future<void>? _initFuture;
  ChatWebViewWidget? _deferredSwitchFrom;
  bool _bridgeFailureNotified = false;
  final ChatWebViewSyncState _syncState = ChatWebViewSyncState();
  late final ChatWebViewSyncDispatcher _syncDispatcher =
      ChatWebViewSyncDispatcher(state: _syncState);

  @override
  bool get wantKeepAlive => true;

  ChatWebViewPanelRefresher _panelRefresher() => ChatWebViewPanelRefresher(
    ref: ref,
    bridge: _bridge,
    ready: () => _ready,
    charId: widget.charId,
    messages: () => widget.messages,
  );

  Future<void> _refreshExtBlocksPanel(String sessionId, String messageId) {
    return _panelRefresher().refreshForMessage(sessionId, messageId);
  }

  Future<void> _syncExtBlockPanels() {
    return _panelRefresher().syncForSession(widget.sessionId);
  }

  /// Owns the chat WebView's bridge-side dependencies: the
  /// [JsBridgeService] handler implementations (generateText,
  /// injectPrompt, uninjectPrompt, triggerGeneration, playAudio,
  /// showToast, executeCommand), the permission gate, and the long-lived
  /// helper instances (audio bridge, toast controller, command registry,
  /// trigger handler, prompt injection notifier).
  late final ChatWebViewBridgeHost _bridgeHost = ChatWebViewBridgeHost(
    ref: ref,
    overlayContextResolver: () => context,
    currentSessionId: () => widget.sessionId,
    currentCharacterId: () => widget.charId,
  );

  @override
  void dispose() {
    // Unregister bridge so the service doesn't hold a stale reference.
    ref.read(chatBridgeRegistryProvider(widget.charId).notifier).state = null;
    // Drop interactive panel state for this character so the singleton
    // registry doesn't keep references to disposed bridge callbacks.
    PanelHostService.instance.disposeAll(charId: widget.charId);
    // Release long-lived resources owned by the bridge host (audio
    // player, etc.). Errors are swallowed; teardown must not throw.
    _bridgeHost.dispose().catchError((Object _) {});
    super.dispose();
  }

  Future<void> _initWebView() {
    return _initFuture ??= _initWebViewOnce();
  }

  Future<void> _waitForJsBridgeReady() async {
    final bridge = _bridge;
    if (bridge == null) return;

    // Fast path: JS already fired onWebViewReady (keep-alive preload case —
    // the page was loaded before the chat screen opened).
    final alreadyReady = await bridge.evalJsWithResult(
      'typeof window.bridge !== "undefined" && window.bridge != null',
    );
    if (alreadyReady == true) return;

    // Slow path: race between the JS-side onWebViewReady signal (event-driven)
    // and a polling fallback. The event wins on normal loads; the poll catches
    // the race where JS fired onWebViewReady before Dart installed the handler.
    final completer = Completer<void>();
    final prevOnReady = bridge.onReady;
    bridge.onReady = () {
      bridge.onReady = prevOnReady;
      if (!completer.isCompleted) completer.complete();
      prevOnReady?.call();
    };

    // Polling fallback: re-check window.bridge every 200 ms independently of
    // the event so we don't miss a signal that arrived before the callback was
    // wired (can happen on iOS keep-alive WebView re-attach).
    unawaited(() async {
      final deadline = DateTime.now().add(_kJsBridgeReadyTimeout);
      while (!completer.isCompleted && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        if (completer.isCompleted) return;
        final ready = await bridge.evalJsWithResult(
          'typeof window.bridge !== "undefined" && window.bridge != null',
        );
        if (ready == true && !completer.isCompleted) completer.complete();
      }
    }());

    try {
      await completer.future.timeout(
        _kJsBridgeReadyTimeout,
        onTimeout: () {
          throw TimeoutException(
            'Chat WebView JS bridge did not initialize within '
            '${_kJsBridgeReadyTimeout.inSeconds}s',
          );
        },
      );
    } finally {
      // Restore the previous callback if we were disposed before the signal.
      if (!completer.isCompleted) bridge.onReady = prevOnReady;
    }
  }

  Future<void> _initWebViewOnce() async {
    final bridge = _bridge;
    if (bridge == null) return;
    final initSessionId = widget.sessionId;
    try {
      await _waitForJsBridgeReady();
      await ChatWebViewInitializer(
      ref: ref,
      bridge: bridge,
      input: ChatWebViewInitInput(
        charId: widget.charId,
        sessionId: widget.sessionId,
        charName: widget.charName,
        charColor: widget.charColor,
        personaName: widget.personaName,
        chatLayout: widget.chatLayout,
        charAvatarPath: widget.charAvatarPath,
        personaAvatarPath: widget.personaAvatarPath,
        greetingTotal: widget.greetingTotal,
        bgNoiseOpacity: widget.bgNoiseOpacity,
        bgNoiseIntensity: widget.bgNoiseIntensity,
        chatFontName: widget.chatFontName,
        chatFontDataUrl: widget.chatFontDataUrl,
        chatFontSize: widget.chatFontSize,
        chatLetterSpacing: widget.chatLetterSpacing,
        batterySaver: widget.batterySaver,
        hideMessageId: widget.hideMessageId,
        hideGenerationTime: widget.hideGenerationTime,
        hideTokenCount: widget.hideTokenCount,
        disableSwipeRegeneration: widget.disableSwipeRegeneration,
        messages: widget.messages,
        visibleStartIndex: widget.visibleStartIndex,
        memoryEntries: widget.memoryEntries,
        memoryDrafts: widget.memoryDrafts,
        bottomInset: widget.bottomInset,
        topInset: widget.topInset,
        searchQuery: widget.searchQuery,
        searchCurrentIndex: widget.searchCurrentIndex,
        isSelectionMode: widget.isSelectionMode,
        isGenerating: widget.isGenerating,
        isGeneratingImage: widget.isGeneratingImage,
      ),
      onReady: () => _ready = true,
      onSyncExtBlockPanels: _syncExtBlockPanels,
      applyTheme: _applyThemeToBridge,
    ).run().timeout(_kWebViewInitTimeout);
    } on TimeoutException catch (e, st) {
      _handleWebViewFailure(e, st, phase: 'init');
      return;
    } catch (e, st) {
      _handleWebViewFailure(e, st, phase: 'init');
      return;
    } finally {
      if (!_ready) _initFuture = null;
    }

    if (!mounted) return;
    final deferred = _deferredSwitchFrom;
    _deferredSwitchFrom = null;
    if (deferred != null) {
      unawaited(_applySessionSwitch(deferred));
    } else if (initSessionId != widget.sessionId) {
      unawaited(_syncCurrentSessionToBridge());
    }
  }

  void _handleWebViewFailure(
    Object e,
    StackTrace? st, {
    required String phase,
  }) {
    debugPrint('[ChatWebView] $phase failed: $e\n$st');
    if (!mounted) return;
    setState(() => _sessionSwitching = false);
    if (_bridgeFailureNotified) return;
    _bridgeFailureNotified = true;
    GlazeToast.error(context, 'Chat view failed to load', e);
  }

  Future<void> _bridgeOp(
    Future<void> op, {
    required String label,
  }) async {
    try {
      await op.timeout(_kBridgeOpTimeout);
    } on TimeoutException catch (e, st) {
      debugPrint('[ChatWebView] bridge op timed out: $label');
      _handleWebViewFailure(e, st, phase: label);
    } catch (e, st) {
      debugPrint('[ChatWebView] bridge op failed ($label): $e\n$st');
      _handleWebViewFailure(e, st, phase: label);
    }
  }

  Future<void> _syncCurrentSessionToBridge() async {
    final bridge = _bridge;
    if (bridge == null || !_ready) return;
    try {
      if (mounted) setState(() => _sessionSwitching = true);
      await _bridgeOp(bridge.clearAll(), label: 'clearAll');
      await _bridgeOp(
        bridge.setMessages(
          widget.messages,
          visibleStartIndex: widget.visibleStartIndex,
        ),
        label: 'setMessages',
      );
      unawaited(_syncExtBlockPanels());
      await _bridgeOp(bridge.scrollToBottom(), label: 'scrollToBottom');
    } finally {
      if (mounted) setState(() => _sessionSwitching = false);
    }
  }

  Future<void> applyIdentity({
    String? charName,
    String? charColor,
    String? personaName,
    String? charAvatarPath,
    String? personaAvatarPath,
    int? greetingTotal,
  }) {
    final bridge = _bridge;
    if (bridge == null || !_ready) return Future.value();
    return bridge.setIdentity(
      charName: charName ?? widget.charName,
      charColor: charColor ?? widget.charColor,
      personaName: personaName ?? widget.personaName,
      layout: widget.chatLayout,
      charAvatarPath: charAvatarPath ?? widget.charAvatarPath,
      personaAvatarPath: personaAvatarPath ?? widget.personaAvatarPath,
      greetingTotal: greetingTotal ?? widget.greetingTotal,
    );
  }

  Future<void> _applySessionSwitch(ChatWebViewWidget old) async {
    final bridge = _bridge;
    if (bridge == null) return;
    if (!_ready) {
      _deferredSwitchFrom = old;
      return;
    }

    // Drop any interactive panels from the previous session before clearing
    // the WebView DOM. JS-side `clearAll()` also closes panels, but the
    // Dart-side registry has to be reset so the next `openPanel` call can
    // bind fresh handlers on the (potentially new) bridge.
    unawaited(PanelHostService.instance.disposeAll(charId: old.charId));
    unawaited(bridge.evalJs('window.bridge?.clearAll();'));
    try {
      if (mounted) setState(() => _sessionSwitching = true);
      if (widget.charId != old.charId) {
        await _bridgeOp(
          bridge.setIdentity(
            charName: widget.charName,
            charColor: widget.charColor,
            personaName: widget.personaName,
            layout: widget.chatLayout,
            charAvatarPath: widget.charAvatarPath,
            personaAvatarPath: widget.personaAvatarPath,
            greetingTotal: widget.greetingTotal,
          ),
          label: 'setIdentity',
        );
        await _bridgeOp(_applyThemeToBridge(), label: 'applyTheme');
        await _bridgeOp(
          bridge.setBackgroundNoise(
            widget.bgNoiseOpacity,
            widget.bgNoiseIntensity,
          ),
          label: 'setBackgroundNoise',
        );
        await _bridgeOp(
          bridge.setChatFont(
            fontName: widget.chatFontName,
            fontDataUrl: widget.chatFontDataUrl,
            fontSize: widget.chatFontSize,
            letterSpacing: widget.chatLetterSpacing,
          ),
          label: 'setChatFont',
        );
      } else {
        await _bridgeOp(
          bridge.setIdentity(
            charName: widget.charName,
            charColor: widget.charColor,
            personaName: widget.personaName,
            layout: widget.chatLayout,
            charAvatarPath: widget.charAvatarPath,
            personaAvatarPath: widget.personaAvatarPath,
            greetingTotal: widget.greetingTotal,
          ),
          label: 'setIdentity',
        );
      }

      await _bridgeOp(bridge.clearAll(), label: 'clearAll');
      await _bridgeOp(
        bridge.setMessages(
          widget.messages,
          visibleStartIndex: widget.visibleStartIndex,
        ),
        label: 'setMessages',
      );
      unawaited(_syncExtBlockPanels());
      await _bridgeOp(bridge.scrollToBottom(), label: 'scrollToBottom');
    } finally {
      if (mounted) setState(() => _sessionSwitching = false);
    }
    _syncState.wasGenerating = widget.isGenerating;
    _syncState.streamingSent = false;
  }

  ChatWebViewWidgetFields _fieldsFor(ChatWebViewWidget w) {
    return ChatWebViewWidgetFields(
      charId: w.charId,
      charName: w.charName,
      charColor: w.charColor,
      personaName: w.personaName,
      charAvatarPath: w.charAvatarPath,
      personaAvatarPath: w.personaAvatarPath,
      bgImagePath: w.bgImagePath,
      bgBlur: w.bgBlur,
      bgOpacity: w.bgOpacity,
      bgDim: w.bgDim,
      bgNoiseOpacity: w.bgNoiseOpacity,
      bgNoiseIntensity: w.bgNoiseIntensity,
      bottomInset: w.bottomInset,
      topInset: w.topInset,
      searchQuery: w.searchQuery,
      searchCurrentIndex: w.searchCurrentIndex,
      chatLayout: w.chatLayout,
      themeSyncKey: w.themeSyncKey,
      elementOpacity: w.elementOpacity,
      elementBlur: w.elementBlur,
      chatFontName: w.chatFontName,
      chatFontDataUrl: w.chatFontDataUrl,
      chatFontSize: w.chatFontSize,
      chatLetterSpacing: w.chatLetterSpacing,
      isSelectionMode: w.isSelectionMode,
      batterySaver: w.batterySaver,
      hideMessageId: w.hideMessageId,
      hideGenerationTime: w.hideGenerationTime,
      hideTokenCount: w.hideTokenCount,
      disableSwipeRegeneration: w.disableSwipeRegeneration,
      memoryEntries: w.memoryEntries,
      memoryDrafts: w.memoryDrafts,
      sessionId: w.sessionId,
      isGenerating: w.isGenerating,
      isGeneratingImage: w.isGeneratingImage,
      regenTargetId: w.regenTargetId,
      greetingTotal: w.greetingTotal,
      messages: w.messages,
      buildThemeMap: _buildThemeMap,
    );
  }

  @override
  void didUpdateWidget(ChatWebViewWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_ready &&
        (widget.charId != oldWidget.charId ||
            widget.sessionId != oldWidget.sessionId)) {
      _deferredSwitchFrom = oldWidget;
    }
    final result = _syncDispatcher.dispatch(
      bridge: _bridge,
      old: _fieldsFor(oldWidget),
      current: _fieldsFor(widget),
      oldMessages: oldWidget.messages,
      newMessages: widget.messages,
      streamingId: _kStreamingId,
      onSyncExtBlockPanels: _syncExtBlockPanels,
      appendMessage: (m) async {
        await _bridge?.appendMessage(m);
      },
      buildStreamingPlaceholder: () => ChatMessage(
        id: _kStreamingId,
        role: 'assistant',
        content: '',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        isTyping: true,
      ),
      ready: _ready,
    );
    if (result.sessionSwitched) {
      if (!_ready) {
        _deferredSwitchFrom = oldWidget;
      } else {
        unawaited(_applySessionSwitch(oldWidget));
      }
      return;
    }
    if (result.runMessageSync) {
      _syncMessages(oldWidget.messages);
      unawaited(_syncExtBlockPanels());
    }
    if (result.appendPlaceholder && result.placeholder != null) {
      unawaited(_bridge?.appendMessage(result.placeholder!));
      _syncDispatcher.onPlaceholderAppended();
    }
  }

  static const _messageSync = ChatMessageSync();

  void _syncMessages(List<ChatMessage> oldMsgs) {
    _messageSync.sync(
      bridge: _bridge,
      oldMsgs: oldMsgs,
      newMsgs: widget.messages,
      visibleStartIndex: widget.visibleStartIndex,
      streamingSkipLast: widget.isGenerating && _syncState.streamingSent,
      isGenerating: widget.isGenerating,
      sessionSwitching: _sessionSwitching,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final character = ref.watch(characterByIdProvider(widget.charId));
    final effectivePersona = ref.watch(
      effectivePersonaForChatProvider((
        charId: widget.charId,
        sessionId: widget.sessionId,
      )),
    );
    final displayRegexes = ref.watch(displayRegexesProvider).value ?? [];

    if (_bridge != null) {
      _bridge!.setRegexContext(displayRegexes, character, effectivePersona);
    }

    ChatWebViewBuildListeners(
      ref: ref,
      bridge: _bridge,
      ready: () => _ready,
      syncState: _syncState,
      streamingId: _kStreamingId,
      charId: widget.charId,
      sessionId: widget.sessionId,
      messages: widget.messages,
      regenTargetId: widget.regenTargetId,
      visibleStartIndex: widget.visibleStartIndex,
      onRefreshExtBlocksPanel: _refreshExtBlocksPanel,
      onSyncExtBlockPanels: _syncExtBlockPanels,
    ).attach();

    final bgImageBytes = ref.watch(bgImageBytesProvider);

    return ChatWebViewSurface(
      bridgeHost: _bridgeHost,
      charId: widget.charId,
      sessionId: widget.sessionId,
      messageActions: widget.messageActions,
      editActions: widget.editActions,
      imageGenActions: widget.imageGenActions,
      scrollActions: widget.scrollActions,
      miscActions: widget.miscActions,
      isMounted: () => mounted,
      sessionSwitching: _sessionSwitching,
      refreshPanel: _refreshExtBlocksPanel,
      bgImageBytes: bgImageBytes,
      bgOpacity: widget.bgOpacity,
      bgBlur: widget.bgBlur,
      bgDim: widget.bgDim,
      bottomInset: widget.bottomInset,
      onBridgeReady: (ChatBridgeController b) => _bridge = b,
      onInitWebView: _initWebView,
    );
  }

  Map<String, String> _buildThemeMap() {
    return ChatWebViewThemeBuilder.build(
      context,
      ChatWebViewThemeInput(
        elementOpacity: widget.elementOpacity,
        elementBlur: widget.elementBlur,
        chatFontSize: widget.chatFontSize,
        chatLayout: widget.chatLayout,
        bgDim: widget.bgDim,
      ),
    );
  }

  Future<void> _applyThemeToBridge() async {
    await _bridge?.applyTheme(_buildThemeMap());
  }

  Future<void> scrollToBottom() {
    final b = _bridge;
    if (b == null) return Future.value();
    return b.scrollToBottom();
  }

  Future<void> scrollToMessage(String id) {
    final b = _bridge;
    if (b == null) return Future.value();
    return b.scrollToMessage(id);
  }

  Future<void> setSearch(String q, int i) {
    final b = _bridge;
    if (b == null) return Future.value();
    return b.setSearch(query: q, activeIndex: i);
  }

  Future<void> toggleMessageSelection(String id) {
    final b = _bridge;
    if (b == null) return Future.value();
    return b.toggleMessageSelection(id);
  }
}
