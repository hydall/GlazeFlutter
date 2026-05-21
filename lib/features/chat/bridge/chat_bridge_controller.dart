import 'dart:convert';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/models/chat_message.dart';

class ChatBridgeController {
  final InAppWebViewController _controller;

  ChatBridgeController(this._controller) {
    _setupHandlers();
  }

  void _setupHandlers() {
    _controller.addJavaScriptHandler(
      handlerName: 'onWebViewReady',
      callback: (args) {
        _onWebViewReady();
      },
    );

    _controller.addJavaScriptHandler(
      handlerName: 'onScrollTop',
      callback: (args) {
        _onScrollToTop();
      },
    );

    _controller.addJavaScriptHandler(
      handlerName: 'onScrollBottom',
      callback: (args) {
        _onScrollToBottom();
      },
    );

    _controller.addJavaScriptHandler(
      handlerName: 'onLinkClick',
      callback: (args) {
        if (args.isNotEmpty) {
          _onLinkClick(args[0] as String);
        }
      },
    );

    _controller.addJavaScriptHandler(
      handlerName: 'onImageClick',
      callback: (args) {
        if (args.isNotEmpty) {
          _onImageClick(args[0] as String);
        }
      },
    );
  }

  void dispose() {
    // Cleanup handlers if needed
  }

  // Callbacks for JavaScript events
  void Function()? onReady;
  void Function()? onScrollToTop;
  void Function()? onScrollBottom;
  void Function(String url)? onLinkClick;
  void Function(String imageUrl)? onImageClick;

  void _onWebViewReady() {
    onReady?.call();
  }

  void _onScrollToTop() {
    onScrollToTop?.call();
  }

  void _onScrollBottom() {
    onScrollBottom?.call();
  }

  void _onLinkClick(String url) {
    onLinkClick?.call(url);
  }

  void _onImageClick(String url) {
    onImageClick?.call(url);
  }

  // Methods to call JavaScript
  Future<void> setMessages(List<ChatMessage> messages) async {
    final messagesJson = messages.map((m) => _messageToJson(m)).toList();
    await _callJs('setMessages', [jsonEncode(messagesJson)]);
  }

  Future<void> appendMessage(ChatMessage message) async {
    final messageJson = _messageToJson(message);
    await _callJs('appendMessage', [jsonEncode(messageJson)]);
  }

  Future<void> updateMessage(ChatMessage message) async {
    final messageJson = _messageToJson(message);
    await _callJs('updateMessage', [jsonEncode(messageJson)]);
  }

  Future<void> deleteMessage(String messageId) async {
    await _callJs('deleteMessage', [messageId]);
  }

  Future<void> scrollToBottom() async {
    await _callJs('scrollToBottom', []);
  }

  Future<void> scrollToMessage(String messageId) async {
    await _callJs('scrollToMessage', [messageId]);
  }

  Future<void> scrollToTop() async {
    await _callJs('scrollToTop', []);
  }

  Future<void> setSearch({
    required String query,
    int activeIndex = -1,
  }) async {
    await _callJs('setSearch', [query, activeIndex]);
  }

  Future<void> scrollToSearchMatch(int index) async {
    await _callJs('scrollToSearchMatch', [index]);
  }

  Future<bool?> isNearBottom() async {
    final result = await _controller.evaluateJavascript(
      source: 'window.glazeBridge ? window.glazeBridge.isNearBottom() : false',
    );
    return result as bool?;
  }

  Future<bool?> isNearTop() async {
    final result = await _controller.evaluateJavascript(
      source: 'window.glazeBridge ? window.glazeBridge.isNearTop() : false',
    );
    return result as bool?;
  }

  Future<void> _callJs(String method, List<dynamic> args) async {
    final argsStr = args.map((a) {
      if (a is String) return "'${_escapeJs(a)}'";
      if (a is bool || a is num) return a.toString();
      return "null";
    }).join(', ');

    await _controller.evaluateJavascript(
      source: 'window.glazeBridge?.$method($argsStr)',
    );
  }

  String _escapeJs(String str) {
    return str
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'")
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('\t', '\\t');
  }

  Map<String, dynamic> _messageToJson(ChatMessage message) {
    return {
      'id': message.id,
      'role': message.role,
      'text': message.content,
      'timestamp': message.timestamp,
      'isUser': message.role == 'user',
      'isAssistant': message.role == 'assistant',
      'isSystem': message.role == 'system',
      if (message.imagePath != null) 'imagePath': message.imagePath,
      if (message.personaName != null) 'personaName': message.personaName,
    };
  }
}
