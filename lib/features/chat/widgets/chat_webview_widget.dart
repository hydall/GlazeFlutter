import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../bridge/chat_bridge_controller.dart';
import '../chat_provider.dart';
import '../chat_state.dart';
import '../../../core/models/chat_message.dart';
import '../../../../shared/theme/theme_provider.dart';

const String _kStreamingId = '__streaming__';

class ChatWebViewWidget extends ConsumerStatefulWidget {
  final List<ChatMessage> messages;
  final String charId;
  final bool isGenerating;
  final double bottomInset;
  final String searchQuery;
  final int searchCurrentIndex;

  const ChatWebViewWidget({
    super.key,
    required this.messages,
    required this.charId,
    required this.isGenerating,
    this.bottomInset = 0,
    this.searchQuery = '',
    this.searchCurrentIndex = 0,
  });

  @override
  ConsumerState<ChatWebViewWidget> createState() => _ChatWebViewState();
}

class _ChatWebViewState extends ConsumerState<ChatWebViewWidget> {
  ChatBridgeController? _bridge;
  bool _ready = false;
  bool _streamingSent = false;
  bool _wasGenerating = false;

  @override
  void didUpdateWidget(ChatWebViewWidget old) {
    super.didUpdateWidget(old);
    if (!_ready) return;

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
          initialFile: 'assets/chat_webview/index.html',
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            domStorageEnabled: true,
            transparentBackground: true,
            useHybridComposition: true,
          ),
          onWebViewCreated: (controller) {
            _bridge = ChatBridgeController(controller);
            _bridge!.onReady = _onReady;
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

  void _onReady() {
    _bridge!.setMessages(widget.messages);
    final preset = ref.read(themeProvider).activePreset;
    _bridge!.applyTheme({
      'user-bg': preset.userBubbleColor ?? '',
      'assistant-bg': preset.charBubbleColor ?? '',
      'user-text': preset.userTextColor ?? '',
      'assistant-text': preset.charTextColor ?? '',
      'quote-color': preset.charQuoteColor ?? preset.userQuoteColor ?? '',
      'italic-color': preset.charItalicColor ?? preset.userItalicColor ?? '',
      'primary-color': preset.accentColor ?? '',
    });
    setState(() => _ready = true);
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
