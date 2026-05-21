import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../bridge/chat_bridge_controller.dart';
import '../../../core/models/chat_message.dart';

class ChatWebViewWidget extends StatefulWidget {
  final String assetPath;

  const ChatWebViewWidget({
    super.key,
    this.assetPath = 'assets/chat_webview',
  });

  @override
  State<ChatWebViewWidget> createState() => _ChatWebViewWidgetState();
}

class _ChatWebViewWidgetState extends State<ChatWebViewWidget> {
  InAppWebViewController? _webViewController;
  ChatBridgeController? _bridgeController;
  bool _isLoading = true;
  bool _isWebViewReady = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _bridgeController?.dispose();
    _webViewController = null;
    super.dispose();
  }

  void _onWebViewCreated(InAppWebViewController controller) {
    _webViewController = controller;
    _bridgeController = ChatBridgeController(controller);
  }

  void _onLoadStop(InAppWebViewController controller, Uri? url) {
    setState(() {
      _isLoading = false;
      _isWebViewReady = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        InAppWebView(
          initialFile: '${widget.assetPath}/index.html',
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            domStorageEnabled: true,
            mediaPlaybackRequiresUserGesture: false,
            allowsInlineMediaPlayback: true,
            transparentBackground: true,
            useWideViewPort: false,
            useHybridComposition: true,
          ),
          onWebViewCreated: _onWebViewCreated,
          onLoadStop: _onLoadStop,
        ),
        if (_isLoading)
          const Center(
            child: CircularProgressIndicator(),
          ),
      ],
    );
  }

  bool get isReady => _isWebViewReady;

  Future<void> setMessages(List<ChatMessage> messages) async {
    if (!_isWebViewReady || _bridgeController == null) return;
    await _bridgeController!.setMessages(messages);
  }

  Future<void> appendMessage(ChatMessage message) async {
    if (!_isWebViewReady || _bridgeController == null) return;
    await _bridgeController!.appendMessage(message);
  }

  Future<void> updateMessage(ChatMessage message) async {
    if (!_isWebViewReady || _bridgeController == null) return;
    await _bridgeController!.updateMessage(message);
  }

  Future<void> deleteMessage(String messageId) async {
    if (!_isWebViewReady || _bridgeController == null) return;
    await _bridgeController!.deleteMessage(messageId);
  }

  Future<void> scrollToBottom() async {
    if (!_isWebViewReady || _bridgeController == null) return;
    await _bridgeController!.scrollToBottom();
  }

  Future<void> scrollToMessage(String messageId) async {
    if (!_isWebViewReady || _bridgeController == null) return;
    await _bridgeController!.scrollToMessage(messageId);
  }

  Future<void> setSearch({
    required String query,
    int activeIndex = -1,
  }) async {
    if (!_isWebViewReady || _bridgeController == null) return;
    await _bridgeController!.setSearch(
      query: query,
      activeIndex: activeIndex,
    );
  }

  Future<bool?> isNearBottom() async {
    if (!_isWebViewReady || _bridgeController == null) return null;
    return await _bridgeController!.isNearBottom();
  }

  Future<bool?> isNearTop() async {
    if (!_isWebViewReady || _bridgeController == null) return null;
    return await _bridgeController!.isNearTop();
  }
}
