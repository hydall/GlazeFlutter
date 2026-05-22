import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../bridge/chat_bridge_controller.dart';
import '../bridge/chat_webview_keep_alive.dart';
import '../chat_provider.dart';
import '../chat_state.dart';
import '../editing_message_provider.dart';
import '../../../core/models/chat_message.dart';
import '../../../../shared/theme/app_colors.dart';

const String _kStreamingId = '__streaming__';

class ChatWebViewWidget extends ConsumerStatefulWidget {
  final List<ChatMessage> messages;
  final String charId;
  final bool isGenerating;
  final double bottomInset;
  final String searchQuery;
  final int searchCurrentIndex;
  final String? charName;
  final String? charColor;
  final String? personaName;
  final String? chatLayout;
  final String? charAvatarPath;
  final String? personaAvatarPath;
  final void Function(int index, bool isUser, bool isSystem, String content)? onMessageContext;
  final void Function(String id, String direction)? onSwipe;
  final void Function(String action, String text)? onSelectionAction;
  final void Function(String id, String text)? onEditSave;
  final void Function(String id)? onEditCancel;

  const ChatWebViewWidget({
    super.key,
    required this.messages,
    required this.charId,
    required this.isGenerating,
    this.bottomInset = 0,
    this.searchQuery = '',
    this.searchCurrentIndex = 0,
    this.charName,
    this.charColor,
    this.personaName,
    this.chatLayout,
    this.charAvatarPath,
    this.personaAvatarPath,
    this.onMessageContext,
    this.onSwipe,
    this.onSelectionAction,
    this.onEditSave,
    this.onEditCancel,
  });

  @override
  ConsumerState<ChatWebViewWidget> createState() => _ChatWebViewState();
}

class _ChatWebViewState extends ConsumerState<ChatWebViewWidget>
    with AutomaticKeepAliveClientMixin {
  ChatBridgeController? _bridge;
  bool _ready = false;
  bool _streamingSent = false;
  bool _wasGenerating = false;

  @override
  bool get wantKeepAlive => true;

  Future<void> _initWebView() async {
    if (_bridge == null) return;

    await _bridge!.setIdentity(
      charName: widget.charName,
      charColor: widget.charColor,
      personaName: widget.personaName,
      layout: widget.chatLayout,
      charAvatarPath: widget.charAvatarPath,
      personaAvatarPath: widget.personaAvatarPath,
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
      'user-quote-color': _colorHex(glaze.userQuote ?? cs.primary),
      'char-quote-color': _colorHex(glaze.charQuote ?? cs.primary),
      'user-italic-color': _colorHex(glaze.userItalic ?? cs.onSurfaceVariant),
      'char-italic-color': _colorHex(glaze.charItalic ?? cs.onSurfaceVariant),
      'primary-color': _colorHex(cs.primary),
      'border-color': _colorHex(cs.outline),
      'chat-layout': widget.chatLayout ?? 'bubble',
    });

    await _bridge!.setMessages(widget.messages);
    await _bridge!.setBottomPadding(widget.bottomInset);
    await _bridge!.scrollToBottom();

    setState(() => _ready = true);
  }

  @override
  void didUpdateWidget(ChatWebViewWidget old) {
    super.didUpdateWidget(old);
    if (!_ready || _bridge == null) return;

    if (widget.charName != old.charName ||
        widget.charColor != old.charColor ||
        widget.personaName != old.personaName ||
        widget.chatLayout != old.chatLayout) {
      _bridge!.setIdentity(
        charName: widget.charName,
        charColor: widget.charColor,
        personaName: widget.personaName,
        layout: widget.chatLayout,
        charAvatarPath: widget.charAvatarPath,
        personaAvatarPath: widget.personaAvatarPath,
      );
      _bridge!.applyTheme({'chat-layout': widget.chatLayout ?? 'bubble'});
    }

    if (widget.bottomInset != old.bottomInset) {
      if ((widget.bottomInset - old.bottomInset).abs() > 5) {
        _bridge!.setBottomPadding(widget.bottomInset);
      }
    }

    _syncMessages(old.messages);

    if (_wasGenerating && !widget.isGenerating) {
      _bridge?.removeMessage(_kStreamingId);
      _streamingSent = false;
    }
    _wasGenerating = widget.isGenerating;
  }

  void _syncMessages(List<ChatMessage> oldMsgs) {
    final oldIds = oldMsgs.map((m) => m.id).toList();
    final newIds = widget.messages.map((m) => m.id).toList();
    final skipLast = widget.isGenerating && _streamingSent;
    final newLen = newIds.length - (skipLast ? 1 : 0);

    if (newIds.length < oldIds.length) {
      _bridge?.clearAll();
      _bridge?.appendMessages(widget.messages);
      return;
    }

    if (newIds.length > oldIds.length) {
      final oldLastId = oldIds.last;
      final newIdx = newIds.indexOf(oldLastId);
      if (newIdx > 0) {
        _bridge?.prependMessages(widget.messages.sublist(0, newIdx));
      } else if (newLen > oldIds.length) {
        final appends = widget.messages.sublist(
          oldIds.length,
          newLen,
        );
        _bridge?.appendMessages(appends);
      }
    }

    final minLen = newLen < oldIds.length ? newLen : oldIds.length;
    for (int i = 0; i < minLen; i++) {
      if (i >= newIds.length) break;
      if (newIds[i] != oldIds[i]) {
        _bridge?.clearAll();
        _bridge?.appendMessages(widget.messages);
        return;
      }
      final o = oldMsgs[i];
      final n = widget.messages[i];
      if (o.content != n.content || o.swipeId != n.swipeId) {
        _bridge?.updateMessage(n);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    ref.listen<int?>(
      editingMessageIndexProvider(widget.charId),
      (prev, next) {
        if (!_ready || _bridge == null) return;
        if (prev != null && prev != next && prev < widget.messages.length) {
          final oldMsg = widget.messages[prev];
          _bridge!.stopEdit(oldMsg.id);
          _bridge!.updateMessageContent(oldMsg.id, oldMsg.content, oldMsg.role == 'user');
        }
        if (next != null && next < widget.messages.length) {
          final newMsg = widget.messages[next];
          _bridge!.startEdit(newMsg.id);
        }
      },
    );

    ref.listen<StreamingState>(
      streamingStateProvider(widget.charId),
      (prev, next) {
        if (!_ready || _bridge == null) return;
        if (next.text.isEmpty && next.reasoning == null) return;

        final msg = ChatMessage(
          id: _kStreamingId,
          role: 'assistant',
          content: next.text,
          timestamp: DateTime.now().millisecondsSinceEpoch,
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
            _bridge!.onMessageContext = (id, isUser, isSystem, content) {
              final idx = widget.messages.indexWhere((m) => m.id == id);
              if (idx < 0) return;
              widget.onMessageContext?.call(idx, isUser, isSystem, content);
            };
            _bridge!.onSwipe = (id, direction) {
              widget.onSwipe?.call(id, direction);
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

            final isAlive = await controller.isLoading() == false;
            if (isAlive && !_ready) {
              await _initWebView();
            }
          },
          onLoadStop: (controller, url) async {
            if (_bridge == null || _ready) return;
            await _initWebView();
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
