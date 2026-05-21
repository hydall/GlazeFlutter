import 'dart:convert';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../core/models/chat_message.dart';

class ChatBridgeController {
  final InAppWebViewController _controller;

  ChatBridgeController(this._controller) {
    _setupHandlers();
  }

  void Function()? onReady;
  void Function()? onLoadMore;
  void Function(String url)? onLinkClick;
  void Function(String url)? onImageClick;

  void _setupHandlers() {
    _controller.addJavaScriptHandler(
      handlerName: 'onWebViewReady',
      callback: (args) => onReady?.call(),
    );

    _controller.addJavaScriptHandler(
      handlerName: 'onLoadMore',
      callback: (args) => onLoadMore?.call(),
    );

    _controller.addJavaScriptHandler(
      handlerName: 'onLinkClick',
      callback: (args) {
        if (args.isNotEmpty) onLinkClick?.call(args[0] as String);
      },
    );

    _controller.addJavaScriptHandler(
      handlerName: 'onImageClick',
      callback: (args) {
        if (args.isNotEmpty) onImageClick?.call(args[0] as String);
      },
    );
  }

  void dispose() {}

  Future<void> setMessages(List<ChatMessage> messages) {
    final json = jsonEncode(messages.map(_toMap).toList());
    return _callJs('setMessages', json);
  }

  Future<void> appendMessage(ChatMessage message) {
    final json = jsonEncode(_toMap(message));
    return _callJs('appendMessage', json);
  }

  Future<void> appendMessages(List<ChatMessage> messages) {
    final json = jsonEncode(messages.map(_toMap).toList());
    return _callJs('appendMessages', json);
  }

  Future<void> prependMessages(List<ChatMessage> messages) {
    final json = jsonEncode(messages.map(_toMap).toList());
    return _callJs('prependMessages', json);
  }

  Future<void> updateMessage(ChatMessage message) {
    final json = jsonEncode(_toMap(message));
    return _callJs('updateMessage', json);
  }

  Future<void> removeMessage(String messageId) {
    return _callJs('removeMessage', messageId);
  }

  Future<void> clearAll() {
    return _eval('window.glazeBridge?.clearAll()');
  }

  Future<void> scrollToBottom() {
    return _eval('window.glazeBridge?.scrollToBottom()');
  }

  Future<void> scrollToMessage(String messageId) {
    return _eval('window.glazeBridge?.scrollToMessage("$messageId")');
  }

  Future<void> setSearch({
    required String query,
    int activeIndex = -1,
  }) {
    return _eval('window.glazeBridge?.setSearch("${_escape(query)}", $activeIndex)');
  }

  Future<void> applyTheme(Map<String, String> theme) {
    final json = jsonEncode(theme);
    return _callJs('applyTheme', json);
  }

  Future<void> _callJs(String method, String arg) {
    return _eval('window.glazeBridge?.$method(${_escapeJsonStr(arg)})');
  }

  Future<void> _eval(String source) async {
    await _controller.evaluateJavascript(source: source);
  }

  String _escape(String s) {
    return s.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('\n', '\\n');
  }

  String _escapeJsonStr(String s) {
    return '"${jsonEncode(s).substring(1, jsonEncode(s).length - 1)}"';
  }

  Map<String, dynamic> _toMap(ChatMessage m) {
    return {
      'id': m.id,
      'role': m.role,
      'text': m.content,
      'timestamp': m.timestamp,
      'isUser': m.role == 'user',
      'isAssistant': m.role == 'assistant',
      'isSystem': m.role == 'system',
      if (m.imagePath != null) 'imagePath': m.imagePath,
      if (m.personaName != null) 'personaName': m.personaName,
      if (m.swipes.isNotEmpty) 'swipeIndex': m.swipeId,
      if (m.swipes.isNotEmpty) 'swipeTotal': m.swipes.length,
      if (m.genTime != null) 'genTime': m.genTime,
      if (m.tokens != null) 'tokens': m.tokens,
      if (m.isError) 'isError': true,
      if (m.isTyping) 'isTyping': true,
    };
  }
}
