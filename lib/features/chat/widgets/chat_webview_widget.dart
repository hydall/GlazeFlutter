import 'dart:async';
import 'dart:ui' as ui;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../core/models/preset.dart';
import '../../../core/state/active_regex_provider.dart';
import '../../../core/state/character_provider.dart';
import '../../../core/state/persona_resolution.dart';
import '../../../../shared/theme/theme_font_provider.dart';
import '../bridge/chat_bridge_controller.dart';
import '../bridge/chat_webview_bridge_host.dart';
import '../bridge/chat_webview_keep_alive.dart';
import '../bridge/chat_webview_settings.dart';
import '../bridge/chat_webview_theme_builder.dart';
import '../chat_provider.dart';
import '../editing_message_provider.dart';
import '../../../core/models/chat_message.dart';
import '../../extensions/models/info_block.dart';
import '../../extensions/providers/extension_presets_provider.dart';
import '../../extensions/providers/extensions_settings_provider.dart';
import '../../extensions/providers/info_blocks_provider.dart';
import '../../extensions/services/js_engine_service.dart';
import '../../extensions/services/panel_host_service.dart';
import '../bridge/chat_bridge_registry.dart';
import '../chat_state.dart';
import 'chat_message_sync.dart';
import 'chat_webview_callbacks.dart';
import 'chat_webview_ext_block_callbacks.dart';
import 'chat_webview_panel_refresher.dart';
import 'chat_webview_sync_dispatcher.dart';
import 'webview_callbacks.dart';

const String _kStreamingId = '__streaming__';

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

  /// Geometry for the WebView's in-content blur strips that sit behind the
  /// Flutter chat header / input pills. Needed because Flutter's
  /// BackdropFilter cannot blur platform-view (WebView) content.
  final double headerOverlayTop;
  final double headerOverlayHeight;
  final double inputOverlayHeight;
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
    this.headerOverlayTop = 0,
    this.headerOverlayHeight = 0,
    this.inputOverlayHeight = 0,
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
  final ChatWebViewSyncState _syncState = ChatWebViewSyncState();
  late final ChatWebViewSyncDispatcher _syncDispatcher =
      ChatWebViewSyncDispatcher(state: _syncState);

  @override
  bool get wantKeepAlive => true;

  ChatWebViewPanelRefresher _panelRefresher() => ChatWebViewPanelRefresher(
        ref: ref,
        bridge: _bridge,
        ready: () => _ready,
        messages: () => widget.messages,
      );

  Future<void> _refreshExtBlocksPanel(
    String sessionId,
    String messageId,
  ) {
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

  /// Shallow comparison of two regex lists by id + disabled state.
  bool _regexListChanged(List<PresetRegex> a, List<PresetRegex> b) {
    if (a.length != b.length) return true;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].disabled != b[i].disabled) return true;
    }
    return false;
  }

  Future<void> _syncIdentityFromWidget() async {
    final bridge = _bridge;
    if (bridge == null) return;

    await bridge.setIdentity(
      charName: widget.charName,
      charColor: widget.charColor,
      personaName: widget.personaName,
      layout: widget.chatLayout,
      charAvatarPath: widget.charAvatarPath,
      personaAvatarPath: widget.personaAvatarPath,
      greetingTotal: widget.greetingTotal,
    );
  }

  Future<void> _initWebView() async {
    final bridge = _bridge;
    if (bridge == null) return;

    final character = ref.read(characterByIdProvider(widget.charId));
    final effectivePersona = ref.read(
      effectivePersonaForChatProvider((
        charId: widget.charId,
        sessionId: widget.sessionId,
      )),
    );
    final displayRegexes = ref.read(displayRegexesProvider).valueOrNull ?? [];
    bridge.setRegexContext(displayRegexes, character, effectivePersona);

    await _syncIdentityFromWidget();

    await _applyThemeToBridge();

    await _bridge!.setBackgroundNoise(
      widget.bgNoiseOpacity,
      widget.bgNoiseIntensity,
    );

    await _bridge!.setChatFont(
      fontName: widget.chatFontName,
      fontDataUrl: widget.chatFontDataUrl,
      fontSize: widget.chatFontSize,
      letterSpacing: widget.chatLetterSpacing,
    );

    await _bridge!.setMessageSettings(
      batterySaver: widget.batterySaver,
      hideMessageId: widget.hideMessageId,
      hideGenerationTime: widget.hideGenerationTime,
      hideTokenCount: widget.hideTokenCount,
      disableSwipeRegeneration: widget.disableSwipeRegeneration,
    );

    // Persona/char identity can resolve while theme and assets load above.
    await _syncIdentityFromWidget();
    await _bridge!.setMessages(
      widget.messages,
      visibleStartIndex: widget.visibleStartIndex,
    );
    _bridge!.updateMemoryBookData(
      entries: widget.memoryEntries
          .map((e) => {'status': e.status, 'messageIds': e.messageIds})
          .toList(),
      pendingDrafts: widget.memoryDrafts
          .map((e) => {'messageIds': e.messageIds})
          .toList(),
    );
    if (widget.bottomInset > 0) {
      await _bridge!.setBottomPadding(widget.bottomInset);
    }
    if (widget.topInset > 0) {
      await _bridge!.setTopPadding(widget.topInset);
    }
    await _bridge!.setHeaderOverlay(
      widget.headerOverlayTop,
      widget.headerOverlayHeight,
    );
    await _bridge!.setInputOverlay(widget.inputOverlayHeight);
    if (widget.searchQuery != null && widget.searchQuery!.isNotEmpty) {
      await _bridge!.setSearch(
        query: widget.searchQuery!,
        activeIndex: widget.searchCurrentIndex,
      );
    }
    await _bridge!.setSelectionMode(widget.isSelectionMode);
    await _bridge!.scrollToBottom();
    final initialAnyGen = widget.isGenerating || widget.isGeneratingImage;
    _bridge!.isGenerating = initialAnyGen;
    unawaited(
      _bridge!.evalJs(
        'if (window.bridge) window.bridge.isGenerating = $initialAnyGen;',
      ),
    );
    _ready = true;

    // Push initial ext-block panels on first load.
    unawaited(_syncExtBlockPanels());
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

    // Drop any interactive panels from the previous session before clearing
    // the WebView DOM. JS-side `clearAll()` also closes panels, but the
    // Dart-side registry has to be reset so the next `openPanel` call can
    // bind fresh handlers on the (potentially new) bridge.
    unawaited(PanelHostService.instance.disposeAll(charId: old.charId));
    unawaited(bridge.evalJs('window.bridge?.clearAll();'));
    if (mounted) setState(() => _sessionSwitching = true);
    if (widget.charId != old.charId) {
      await bridge.setIdentity(
        charName: widget.charName,
        charColor: widget.charColor,
        personaName: widget.personaName,
        layout: widget.chatLayout,
        charAvatarPath: widget.charAvatarPath,
        personaAvatarPath: widget.personaAvatarPath,
        greetingTotal: widget.greetingTotal,
      );
      await _applyThemeToBridge();

      await bridge.setBackgroundNoise(
        widget.bgNoiseOpacity,
        widget.bgNoiseIntensity,
      );
      await bridge.setChatFont(
        fontName: widget.chatFontName,
        fontDataUrl: widget.chatFontDataUrl,
        fontSize: widget.chatFontSize,
        letterSpacing: widget.chatLetterSpacing,
      );
    } else {
      await bridge.setIdentity(
        charName: widget.charName,
        charColor: widget.charColor,
        personaName: widget.personaName,
        layout: widget.chatLayout,
        charAvatarPath: widget.charAvatarPath,
        personaAvatarPath: widget.personaAvatarPath,
        greetingTotal: widget.greetingTotal,
      );
    }

    await bridge.clearAll();
    await bridge.setMessages(
      widget.messages,
      visibleStartIndex: widget.visibleStartIndex,
    );
    // Restore ext-block panels after session switch.
    unawaited(_syncExtBlockPanels());
    Future.delayed(const Duration(milliseconds: 150), () {
      bridge.scrollToBottom();
      if (mounted) setState(() => _sessionSwitching = false);
    });
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
      headerOverlayTop: w.headerOverlayTop,
      headerOverlayHeight: w.headerOverlayHeight,
      inputOverlayHeight: w.inputOverlayHeight,
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
      unawaited(_applySessionSwitch(oldWidget));
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
    final displayRegexes = ref.watch(displayRegexesProvider).valueOrNull ?? [];

    if (_bridge != null) {
      _bridge!.setRegexContext(displayRegexes, character, effectivePersona);
    }

    // Re-render all messages when display regex list changes (toggle, add, remove).
    ref.listen<AsyncValue<List<PresetRegex>>>(displayRegexesProvider, (
      prev,
      next,
    ) {
      if (!_ready || _bridge == null) return;
      final oldList = prev?.valueOrNull ?? [];
      final newList = next.valueOrNull ?? [];
      if (_regexListChanged(oldList, newList)) {
        _bridge!.setRegexContext(newList, character, effectivePersona);
        _bridge!.setMessages(
          widget.messages,
          visibleStartIndex: widget.visibleStartIndex,
        );
      }
    });

    ref.listen<String?>(editingMessageIdProvider(widget.charId), (prev, next) {
      if (!_ready || _bridge == null) return;
      if (prev != null && prev != next) {
        _bridge!.stopEdit(prev);
        final oldMsg = widget.messages.where((m) => m.id == prev).firstOrNull;
        if (oldMsg != null) {
          _bridge!.updateMessage(oldMsg);
        }
      }
      if (next != null) {
        _bridge!.startEdit(next);
      }
    });

    ref.listen<StreamingState>(streamingStateProvider(widget.charId), (
      prev,
      next,
    ) {
      if (!_ready || _bridge == null) return;
      if (next.text.isEmpty && next.reasoning == null) return;

      final regenId = widget.regenTargetId;
      if (regenId != null) {
        final idx = widget.messages.indexWhere((m) => m.id == regenId);
        if (idx >= 0) {
          final original = widget.messages[idx];
          final updated = original.copyWith(
            content: next.text,
            reasoning: next.reasoning ?? original.reasoning,
            isTyping: true,
          );
          _bridge?.updateMessage(updated);
          _syncState.regenStreamingSent = true;
        }
        return;
      }

      final msg = ChatMessage(
        id: _kStreamingId,
        role: 'assistant',
        content: next.text,
        reasoning: next.reasoning,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        isTyping: true,
      );

      if (!_syncState.streamingSent) {
        _bridge?.appendMessage(msg);
        _syncState.streamingSent = true;
      } else {
        _bridge?.updateMessage(msg);
      }
    });

    // Refresh inline ext-block panels when DB rows or extension settings change.
    final sessionId = widget.sessionId;
    if (sessionId != null && sessionId.isNotEmpty) {
      ref.listen<List<InfoBlock>>(infoBlocksProvider(sessionId), (prev, next) {
        if (_bridge == null || !_ready) return;
        final allIds = <String>{
          for (final b in prev ?? const <InfoBlock>[]) b.messageId,
          for (final b in next) b.messageId,
          for (final m in widget.messages)
            if (m.role == 'assistant' || m.role == 'character') m.id,
        };
        for (final msgId in allIds) {
          unawaited(_refreshExtBlocksPanel(sessionId, msgId));
        }
      });
    }
    ref.listen(extensionsSettingsProvider, (_, _) {
      if (_bridge != null && _ready) unawaited(_syncExtBlockPanels());
    });
    ref.listen(extensionPresetsProvider, (_, _) {
      if (_bridge != null && _ready) unawaited(_syncExtBlockPanels());
    });

    final bgImageBytes = ref.watch(bgImageBytesProvider);

    return Stack(
      children: [
        // Theme surface color — always visible behind the transparent WebView
        // so there's no white flash when no bg image is set.
        Positioned.fill(
          child: ColoredBox(color: Theme.of(context).colorScheme.surface),
        ),
        // Background image rendered in Flutter so it shows through the
        // transparent WebView. Uses decoded bytes (same as GlazeBackground)
        // because preset.bgImage is a base64 data URI, not a file path.
        if (bgImageBytes != null) ...[
          Positioned.fill(
            child: Opacity(
              opacity: widget.bgOpacity,
              child: widget.bgBlur > 0
                  ? ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(
                        sigmaX: widget.bgBlur,
                        sigmaY: widget.bgBlur,
                        tileMode: TileMode.clamp,
                      ),
                      child: Image.memory(
                        bgImageBytes,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      ),
                    )
                  : Image.memory(
                      bgImageBytes,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
            ),
          ),
          if (widget.bgDim > 0)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: widget.bgDim),
              ),
            ),
        ],
        AnimatedOpacity(
          opacity: _sessionSwitching ? 0.45 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: IgnorePointer(
            ignoring: _sessionSwitching,
            child: InAppWebView(
              keepAlive: chatWebViewKeepAlive,
              initialFile: 'assets/chat_webview/index.html',
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                domStorageEnabled: true,
                transparentBackground: chatWebViewTransparentBackground(),
                isInspectable: true,
                useHybridComposition: true,
                cacheEnabled: true,
                useWideViewPort: true,
                loadWithOverviewMode: true,
                allowFileAccess: true,
                allowContentAccess: true,
                // The chat page is loaded from `file://` assets. We do NOT
                // need file:// -> http(s) universal access — outbound links
                // are handled via `launchUrl(..., externalApplication)` in
                // the bridge, not from the WebView itself. Keeping these
                // `false` blocks an XSS'd panel / extension JS from doing
                // `fetch('file:///...')` or `fetch('http://...')` from a
                // local origin.
                allowFileAccessFromFileURLs: false,
                allowUniversalAccessFromFileURLs: false,
                // Mixed content is opt-in. The chat WebView itself does
                // not load HTTP resources, but the iframe panels do
                // receive base64 data: URIs only — never http(s).
                mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
              ),
              onWebViewCreated: (controller) async {
                final jsBridgeService = await _bridgeHost.buildJsBridgeService();
                _bridge = ChatBridgeController(
                  controller,
                  jsBridgeService: jsBridgeService,
                );
                // Register bridge in the registry so services can access it.
                ref
                        .read(
                          chatBridgeRegistryProvider(widget.charId).notifier,
                        )
                        .state =
                    _bridge;

                // Kick off the singleton headless engine. Failure is
                // non-fatal — the visual bridge above remains the fallback
                // for jsRunner blocks and for background scripts.
                unawaited(
                  JsEngineService.instance.init(
                    host: JsEngineBridgeHost(
                      bridge: jsBridgeService,
                      currentCharIdProvider: () => widget.charId,
                    ),
                  ),
                );
                unawaited(
                  controller.evaluateJavascript(
                    source: 'if(window.bridge) window.bridge.clearAll();',
                  ),
                );
                final callbacks = ChatWebViewCallbacks(
                  ref: ref,
                  charId: widget.charId,
                  messageActions: widget.messageActions,
                  editActions: widget.editActions,
                  imageGenActions: widget.imageGenActions,
                  scrollActions: widget.scrollActions,
                  miscActions: widget.miscActions,
                );
                _bridge!.onMessageContext = callbacks.onMessageContext;
                _bridge!.onSwipe = callbacks.onSwipe;
                _bridge!.onChangeGreeting = callbacks.onChangeGreeting;
                _bridge!.onHeaderScroll = callbacks.onHeaderScroll;
                _bridge!.onScrollToBottomVisibility =
                    callbacks.onScrollToBottomVisibility;
                _bridge!.onRegenerate = callbacks.onRegenerate;
                _bridge!.onSelectionAction = callbacks.onSelectionAction;
                _bridge!.onSelectionChange = callbacks.onSelectionChange;
                _bridge!.onEditSave = callbacks.onEditSave;
                _bridge!.onEditCancel = callbacks.onEditCancel;
                _bridge!.onEditFocusChange = callbacks.onEditFocusChange;
                _bridge!.onImageClick = callbacks.onImageClick;
                _bridge!.onGuidedSwipe = callbacks.onGuidedSwipe;
                _bridge!.onMemoryClick = callbacks.onMemoryClick;
                _bridge!.onToggleHidden = callbacks.onToggleHidden;
                _bridge!.onInjectClick = callbacks.onInjectClick;
                _bridge!.onImgRetry = callbacks.onImgRetry;
                _bridge!.onImgFind = callbacks.onImgFind;
                _bridge!.onImgRegen = callbacks.onImgRegen;
                _bridge!.onImgCancel = callbacks.onImgCancel;
                _bridge!.onStop = callbacks.onStop;
                _bridge!.onLinkClick = callbacks.onLinkClick;
                _bridge!.onLoadMore = callbacks.onLoadMore;
                final extBlocks = ChatWebViewExtBlockCallbacks(
                  ref: ref,
                  charId: widget.charId,
                  sessionId: widget.sessionId,
                  // ignore: use_build_context_synchronously
                  context: context,
                  isMounted: () => mounted,
                  refreshPanel: _refreshExtBlocksPanel,
                );
                _bridge!.onExtBlocksRunAll = extBlocks.onRunAll();
                _bridge!.onExtBlockStop = extBlocks.onStop();
                _bridge!.onExtBlockRegen = extBlocks.onRegen();
                _bridge!.onExtBlockRegenImage = extBlocks.onRegenImage();
                _bridge!.onExtBlockEdit = extBlocks.onEdit();
                _bridge!.onExtBlockDelete = extBlocks.onDelete();

                final isAlive = await controller.isLoading() == false;
                if (isAlive && !_ready) {
                  await _initWebView();
                }
              },
              onLoadStop: (controller, url) async {
                if (_bridge == null || _ready) return;
                unawaited(
                  controller.evaluateJavascript(
                    source: '''
              (function() {
                var els = [document.documentElement, document.body, document.getElementById('chat-container'), document.getElementById('loading-screen')];
                els.forEach(function(el) {
                  if (!el) return;
                  var cs = getComputedStyle(el);
                  console.log('DIAG ' + (el.id || el.tagName) + ' bg=' + cs.backgroundColor + ' opacity=' + el.style.opacity);
                });
              })();
            ''',
                  ),
                );
                await _initWebView();
              },
              onConsoleMessage: (controller, consoleMessage) {
                debugPrint('[JS] ${consoleMessage.message}');
              },
            ),
          ),
        ),
        if (_sessionSwitching)
          const Center(child: CircularProgressIndicator(strokeWidth: 3)),
        if (widget.bottomInset > 0)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.02),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
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
