import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../bridge/chat_bridge_controller.dart';
import '../bridge/chat_webview_keep_alive.dart';
import '../chat_provider.dart';
import '../chat_state.dart';
import '../editing_message_provider.dart';
import '../../../core/models/chat_message.dart';
import '../../../../shared/theme/app_colors.dart';

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
  final List<ChatMessage> messages;
  final bool isGenerating;
  final bool isGeneratingImage;
  final double bottomInset;
  final double topInset;
  final String? searchQuery;
  final int searchCurrentIndex;
  final String? chatLayout;
  final void Function(int index, String messageId, bool isUser, bool isSystem, String content)? onMessageContext;
  final void Function(String id, String direction)? onSwipe;
  final void Function(String id, int direction)? onChangeGreeting;
  final void Function(String id)? onRegenerate;
  final void Function(bool hidden)? onHeaderScroll;
  final int greetingTotal;
  final void Function()? onStop;
  final void Function(String action, String text)? onSelectionAction;
  final void Function(String id, String text)? onEditSave;
  final void Function(String id)? onEditCancel;
  final void Function(String imageUrl)? onImageClick;
  final void Function(String id, String guidanceText)? onGuidedSwipe;
  final void Function(String id)? onMemoryClick;
  final void Function(String id)? onToggleHidden;
  final void Function(String id)? onInjectClick;
  final void Function(String instruction, String messageId)? onImgRetry;
  final void Function(String instruction, String messageId)? onImgFind;
  final void Function(String instruction, String messageId)? onImgRegen;
  final void Function()? onImgCancel;
  final String? chatFontName;
  final String? chatFontDataUrl;
  final double chatFontSize;
  final double chatLetterSpacing;
  final List<dynamic> memoryEntries;
  final List<dynamic> memoryDrafts;
  final String? sessionId;
  final int visibleStartIndex;
  final String? regenTargetId;

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
    required this.messages,
    required this.isGenerating,
    this.isGeneratingImage = false,
    this.bottomInset = 0,
    this.topInset = 0,
    this.searchQuery,
    this.searchCurrentIndex = 0,
    this.chatLayout,
    this.onMessageContext,
    this.onSwipe,
    this.onChangeGreeting,
    this.onRegenerate,
    this.onHeaderScroll,
    this.greetingTotal = 0,
    this.onStop,
    this.onSelectionAction,
    this.onEditSave,
    this.onEditCancel,
    this.onImageClick,
    this.onGuidedSwipe,
    this.onMemoryClick,
    this.onToggleHidden,
    this.onInjectClick,
    this.onImgRetry,
    this.onImgFind,
    this.onImgRegen,
    this.onImgCancel,
    this.chatFontName,
    this.chatFontDataUrl,
    this.chatFontSize = 15.0,
    this.chatLetterSpacing = 0.0,
    this.memoryEntries = const [],
    this.memoryDrafts = const [],
    this.sessionId,
    this.visibleStartIndex = 0,
    this.regenTargetId,
  });

  @override
  ConsumerState<ChatWebViewWidget> createState() => _ChatWebViewState();
}

class _ChatWebViewState extends ConsumerState<ChatWebViewWidget>
    with AutomaticKeepAliveClientMixin {
  ChatBridgeController? _bridge;
  bool _ready = false;
  bool _streamingSent = false;
  bool _regenStreamingSent = false;
  bool _wasGenerating = false;
  bool _sessionSwitching = false;

  @override
  bool get wantKeepAlive => true;

  Future<void> _initWebView() async {
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

    final glaze = context.colors;
    final cs = context.cs;
    await _bridge!.applyTheme({
      'bg-color': _colorHex(cs.surface),
      'text-color': _colorHex(cs.onSurface),
      'user-bg': _colorHex(glaze.userBubble),
      'assistant-bg': _colorHex(glaze.charBubble),
      'user-text': _colorHex(glaze.userText ?? cs.onSurface),
      'assistant-text': _colorHex(glaze.charText ?? cs.onSurface),
      'system-bg': _colorHex(cs.surfaceContainerHighest),
      'system-text': _colorHex(cs.onSurfaceVariant),
      'user-quote-color': _colorHex(glaze.userQuote ?? cs.primary),
      'char-quote-color': _colorHex(glaze.charQuote ?? cs.primary),
      'user-italic-color': _colorHex(glaze.userItalic ?? cs.primary),
      'char-italic-color': _colorHex(glaze.charItalic ?? cs.primary),
      'primary-color': _colorHex(cs.primary),
      'error-color': _colorHex(cs.error),
      'font-size': '${widget.chatFontSize}px',
      'chat-layout': widget.chatLayout ?? 'default',
    });

    await _bridge!.setBackgroundImage(widget.bgImagePath, widget.bgBlur.toInt(), widget.bgOpacity);
    
    await _bridge!.setChatFont(
      fontName: widget.chatFontName,
      fontDataUrl: widget.chatFontDataUrl,
      fontSize: widget.chatFontSize,
      letterSpacing: widget.chatLetterSpacing,
    );

    await _bridge!.setMessages(widget.messages, visibleStartIndex: widget.visibleStartIndex);
    _bridge!.updateMemoryBookData(
      entries: widget.memoryEntries.map((e) => {'status': e.status, 'messageIds': e.messageIds}).toList(),
      pendingDrafts: widget.memoryDrafts.map((e) => {'messageIds': e.messageIds}).toList(),
    );
    if (widget.bottomInset > 0) {
      await _bridge!.setBottomPadding(widget.bottomInset);
    }
    if (widget.topInset > 0) {
      await _bridge!.setTopPadding(widget.topInset);
    }
    if (widget.searchQuery != null && widget.searchQuery!.isNotEmpty) {
      await _bridge!.setSearch(query: widget.searchQuery!, activeIndex: widget.searchCurrentIndex);
    }
    await _bridge!.scrollToBottom();
    final initialAnyGen = widget.isGenerating || widget.isGeneratingImage;
    _bridge!.isGenerating = initialAnyGen;
    _bridge!.evalJs('if (window.bridge) window.bridge.isGenerating = ${initialAnyGen};');
    _ready = true;
  }

  @override
  void didUpdateWidget(ChatWebViewWidget old) {
    super.didUpdateWidget(old);
    if (!_ready || _bridge == null) return;

    if (widget.memoryEntries != old.memoryEntries || widget.memoryDrafts != old.memoryDrafts) {
      _bridge!.updateMemoryBookData(
        entries: widget.memoryEntries.map((e) => {'status': e.status, 'messageIds': e.messageIds}).toList(),
        pendingDrafts: widget.memoryDrafts.map((e) => {'messageIds': e.messageIds}).toList(),
      );
    }

    if (widget.charId != old.charId || widget.sessionId != old.sessionId) {
      _sessionSwitching = true;
      if (widget.charId != old.charId) {
        _bridge!.setIdentity(
          charName: widget.charName,
          charColor: widget.charColor,
          personaName: widget.personaName,
          layout: widget.chatLayout,
          charAvatarPath: widget.charAvatarPath,
          personaAvatarPath: widget.personaAvatarPath,
          greetingTotal: widget.greetingTotal,
        );
        _bridge!.applyTheme({'chat-layout': widget.chatLayout ?? 'default'});
        _bridge!.setBackgroundImage(widget.bgImagePath, widget.bgBlur.toInt(), widget.bgOpacity);
        _bridge!.setChatFont(
          fontName: widget.chatFontName,
          fontDataUrl: widget.chatFontDataUrl,
          fontSize: widget.chatFontSize,
          letterSpacing: widget.chatLetterSpacing,
        );
      }
      _bridge!.clearAll();
      _bridge!.setMessages(widget.messages, visibleStartIndex: widget.visibleStartIndex);
      Future.delayed(const Duration(milliseconds: 150), () {
        _bridge?.scrollToBottom();
        _sessionSwitching = false;
      });
      _wasGenerating = widget.isGenerating;
      _streamingSent = false;
      return;
    }

    if (widget.charName != old.charName ||
        widget.charColor != old.charColor ||
        widget.personaName != old.personaName ||
        widget.chatLayout != old.chatLayout ||
        widget.greetingTotal != old.greetingTotal) {
      _bridge!.setIdentity(
        charName: widget.charName,
        charColor: widget.charColor,
        personaName: widget.personaName,
        layout: widget.chatLayout,
        charAvatarPath: widget.charAvatarPath,
        personaAvatarPath: widget.personaAvatarPath,
        greetingTotal: widget.greetingTotal,
      );
      _bridge!.applyTheme({'chat-layout': widget.chatLayout ?? 'default'});
    }

    if (widget.bgImagePath != old.bgImagePath ||
        widget.bgBlur != old.bgBlur ||
        widget.bgOpacity != old.bgOpacity) {
      _bridge!.setBackgroundImage(widget.bgImagePath, widget.bgBlur.toInt(), widget.bgOpacity);
    }

    if (widget.chatFontName != old.chatFontName ||
        widget.chatFontDataUrl != old.chatFontDataUrl ||
        widget.chatFontSize != old.chatFontSize ||
        widget.chatLetterSpacing != old.chatLetterSpacing) {
      _bridge!.setChatFont(
        fontName: widget.chatFontName,
        fontDataUrl: widget.chatFontDataUrl,
        fontSize: widget.chatFontSize,
        letterSpacing: widget.chatLetterSpacing,
      );
    }

    if (widget.bottomInset != old.bottomInset) {
      _bridge!.setBottomPadding(widget.bottomInset);
    }

    if (widget.topInset != old.topInset) {
      _bridge!.setTopPadding(widget.topInset);
    }

    final anyGenerating = widget.isGenerating || widget.isGeneratingImage;
    final oldAnyGenerating = old.isGenerating || old.isGeneratingImage;
    if (anyGenerating != oldAnyGenerating || widget.isGenerating != old.isGenerating) {
      _bridge!.isGenerating = widget.isGenerating;
      _bridge!.isGeneratingImage = widget.isGeneratingImage;
      _bridge!.evalJs('if (window.bridge) { window.bridge.setGenerating(${widget.isGenerating}); window.bridge.isGeneratingImage = ${widget.isGeneratingImage}; }');
      if (!anyGenerating && widget.messages.isNotEmpty) {
        // Generation finished → mark the actual last message; bridge injects
        // the regen button only when that last message is from the user.
        _bridge?.setLastMessage(widget.messages.last.id);
      } else if (widget.isGenerating) {
        // Generation started → remove regen button
        _bridge?.setLastMessage(null);
      }
    }

    if (_wasGenerating && !widget.isGenerating) {
      if (!_regenStreamingSent) {
        _bridge?.removeMessage(_kStreamingId);
      }
      _streamingSent = false;
      _regenStreamingSent = false;
    }

    // Sync messages BEFORE injecting the typing placeholder, so the new user
    // message lands at its correct position (placeholder is appended after).
    if (!identical(old.messages, widget.messages) &&
        !_listsEqual(old.messages, widget.messages)) {
      _syncMessages(old.messages);
    }

    // Fresh generation started (no regenTargetId) → inject typing placeholder immediately
    final shouldInjectPlaceholder = !_wasGenerating &&
        widget.isGenerating &&
        widget.regenTargetId == null &&
        !_streamingSent;
    _wasGenerating = widget.isGenerating;
    if (shouldInjectPlaceholder) {
      final typingMsg = ChatMessage(
        id: _kStreamingId,
        role: 'assistant',
        content: '',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        isTyping: true,
      );
      _bridge?.appendMessage(typingMsg);
      _streamingSent = true;
    }
  }

  static bool _listsEqual(List<ChatMessage> a, List<ChatMessage> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  void _syncMessages(List<ChatMessage> oldMsgs) {
    if (_sessionSwitching) return;
    final oldIds = oldMsgs.map((m) => m.id).toList();
    final newIds = widget.messages.map((m) => m.id).toList();
    final skipLast = widget.isGenerating && _streamingSent;
    final newLen = newIds.length - (skipLast ? 1 : 0);

    if (oldIds.isEmpty) {
      _bridge?.setMessages(widget.messages, visibleStartIndex: widget.visibleStartIndex);
      return;
    }

    if (newIds.isEmpty) {
      _bridge?.clearAll();
      return;
    }

    if (newIds.length > oldIds.length) {
      final oldFirstId = oldIds.first;
      final newIdx = newIds.indexOf(oldFirstId);
      if (newIdx > 0) {
        _bridge?.prependMessages(
          widget.messages.sublist(0, newIdx),
          visibleStartIndex: widget.visibleStartIndex,
        );
        return;
      }
      if (newLen > oldIds.length) {
        final appends = widget.messages.sublist(
          oldIds.length,
          newLen,
        );
        _bridge?.appendMessages(
          appends,
          startIndex: widget.visibleStartIndex + oldIds.length,
        );
        if (appends.isNotEmpty && !widget.isGenerating) {
          _bridge?.setLastMessage(widget.messages.lastOrNull?.id);
        }
        return;
      }
    }

    if (newIds.length < oldIds.length) {
      final newFirstId = newIds.first;
      final oldIdx = oldIds.indexOf(newFirstId);
      if (oldIdx > 0) {
        for (int i = 0; i < oldIdx; i++) {
          _bridge?.removeMessage(oldIds[i]);
        }
        return;
      }
      final newLastId = newIds.last;
      final oldLastIdx = oldIds.indexOf(newLastId);
      if (oldLastIdx >= 0 && newIds.length == oldLastIdx + 1) {
        for (int i = oldIds.length - 1; i > oldLastIdx; i--) {
          _bridge?.removeMessage(oldIds[i]);
        }
        if (!widget.isGenerating) {
          _bridge?.setLastMessage(widget.messages.lastOrNull?.id);
        }
        return;
      }
      _bridge?.clearAll();
      _bridge?.setMessages(widget.messages, visibleStartIndex: widget.visibleStartIndex);
      return;
    }

    // Same length - check for updates
    final minLen = newLen < oldIds.length ? newLen : oldIds.length;
    for (int i = 0; i < minLen; i++) {
      if (i >= newIds.length) break;
      if (newIds[i] != oldIds[i]) {
        _bridge?.clearAll();
        _bridge?.setMessages(widget.messages, visibleStartIndex: widget.visibleStartIndex);
        return;
      }
      final o = oldMsgs[i];
      final n = widget.messages[i];
      
      final contentChanged = o.content != n.content;
      final swipeChanged = o.swipeId != n.swipeId;
      final hiddenChanged = o.isHidden != n.isHidden;
      final typingChanged = o.isTyping != n.isTyping;
      final errorChanged = o.isError != n.isError;
      final guidanceChanged = o.guidanceText != n.guidanceText;
      final greetingChanged = o.greetingIndex != n.greetingIndex;
      
      final needsUpdate = contentChanged || swipeChanged || hiddenChanged || 
                         typingChanged || errorChanged || guidanceChanged || greetingChanged;
      
      if (needsUpdate) {
        _bridge?.updateMessage(n);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    ref.listen<String?>(
      editingMessageIdProvider(widget.charId),
      (prev, next) {
        if (!_ready || _bridge == null) return;
        if (prev != null && prev != next) {
          _bridge!.stopEdit(prev);
          final oldMsg = widget.messages.where((m) => m.id == prev).firstOrNull;
          if (oldMsg != null) {
            _bridge!.updateMessageContent(oldMsg.id, oldMsg.content, oldMsg.role == 'user');
          }
        }
        if (next != null) {
          _bridge!.startEdit(next);
        }
      },
    );

    ref.listen<StreamingState>(
      streamingStateProvider(widget.charId),
      (prev, next) {
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
            _regenStreamingSent = true;
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

        if (!_streamingSent) {
          _bridge?.appendMessage(msg);
          _streamingSent = true;
        } else {
          _bridge?.updateMessage(msg);
        }
      },
    );

    return Stack(
      children: [
        InAppWebView(
          keepAlive: chatWebViewKeepAlive,
          initialFile: 'assets/chat_webview/index.html',
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            domStorageEnabled: true,
            transparentBackground: true,
            useHybridComposition: true,
            cacheEnabled: true,
            useWideViewPort: true,
            loadWithOverviewMode: true,
            allowFileAccessFromFileURLs: true,
            allowUniversalAccessFromFileURLs: true,
            mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
          ),
          onWebViewCreated: (controller) async {
            _bridge = ChatBridgeController(controller);
            controller.evaluateJavascript(source: 'if(window.bridge) window.bridge.clearAll();');
            _bridge!.onMessageContext = (id, isUser, isSystem, content) {
              final allMsgs = ref.read(chatProvider(widget.charId)).value?.messages ?? [];
              final idx = allMsgs.indexWhere((m) => m.id == id);
              if (idx < 0) return;
              widget.onMessageContext?.call(idx, id, isUser, isSystem, content);
            };
            _bridge!.onSwipe = (id, direction) {
              widget.onSwipe?.call(id, direction);
            };
            _bridge!.onChangeGreeting = (id, dir) {
              widget.onChangeGreeting?.call(id, dir);
            };
            _bridge!.onHeaderScroll = (hidden) {
              widget.onHeaderScroll?.call(hidden);
            };
            _bridge!.onRegenerate = (id) {
              widget.onRegenerate?.call(id);
            };
            _bridge!.onSelectionAction = (action, text) {
              widget.onSelectionAction?.call(action, text);
            };
            _bridge!.onEditSave = (id, text) {
              widget.onEditSave?.call(id, text);
            };
            _bridge!.onEditCancel = (id) {
              widget.onEditCancel?.call(id);
            };
            _bridge!.onImageClick = (imageUrl) {
              widget.onImageClick?.call(imageUrl);
            };
            _bridge!.onGuidedSwipe = (id, guidanceText) {
              widget.onGuidedSwipe?.call(id, guidanceText);
            };
            _bridge!.onMemoryClick = (id) {
              widget.onMemoryClick?.call(id);
            };
            _bridge!.onToggleHidden = (id) {
              widget.onToggleHidden?.call(id);
            };
            _bridge!.onInjectClick = (id) {
              widget.onInjectClick?.call(id);
            };
            _bridge!.onImgRetry = (instruction, messageId) {
              widget.onImgRetry?.call(instruction, messageId);
            };
            _bridge!.onImgFind = (instruction, messageId) {
              widget.onImgFind?.call(instruction, messageId);
            };
            _bridge!.onImgRegen = (instruction, messageId) {
              widget.onImgRegen?.call(instruction, messageId);
            };
            _bridge!.onImgCancel = () {
              widget.onImgCancel?.call();
            };
            _bridge!.onStop = () {
              widget.onStop?.call();
            };
            _bridge!.onLinkClick = (url) {
              launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            };
            _bridge!.onLoadMore = () {
              ref.read(chatProvider(widget.charId).notifier).loadOlderMessages();
            };

            final isAlive = await controller.isLoading() == false;
            if (isAlive && !_ready) {
              await _initWebView();
            }
          },
          onLoadStop: (controller, url) async {
            if (_bridge == null || _ready) return;
            await _initWebView();
          },
          onConsoleMessage: (controller, consoleMessage) {
            debugPrint('[JS] ${consoleMessage.message}');
          },
        ),
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

  String _colorHex(Color c) {
    final a = c.a;
    final r = (c.r * 255).round();
    final g = (c.g * 255).round();
    final b = (c.b * 255).round();
    if (a >= 0.99) {
      return '#${r.toRadixString(16).padLeft(2, '0')}'
          '${g.toRadixString(16).padLeft(2, '0')}'
          '${b.toRadixString(16).padLeft(2, '0')}';
    }
    final alphaR = (r * a + 255 * (1 - a)).round().clamp(0, 255);
    final alphaG = (g * a + 255 * (1 - a)).round().clamp(0, 255);
    final alphaB = (b * a + 0 * (1 - a)).round().clamp(0, 255);
    return '#${alphaR.toRadixString(16).padLeft(2, '0')}'
        '${alphaG.toRadixString(16).padLeft(2, '0')}'
        '${alphaB.toRadixString(16).padLeft(2, '0')}';
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
}
