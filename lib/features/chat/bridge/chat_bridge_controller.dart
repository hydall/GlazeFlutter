import 'dart:convert';
import 'dart:io';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../core/models/chat_message.dart';

class ChatBridgeController {
  final InAppWebViewController _controller;

  String? currentCharName;
  String? currentCharColor;
  String? currentPersonaName;
  String? currentChatLayout;
  String? _charAvatarDataUrl;
  String? _personaAvatarDataUrl;

  ChatBridgeController(this._controller) {
    _setupHandlers();
  }

  Future<void> setIdentity({
    String? charName,
    String? charColor,
    String? personaName,
    String? layout,
    String? charAvatarPath,
    String? personaAvatarPath,
  }) async {
    currentCharName = charName;
    currentCharColor = charColor;
    currentPersonaName = personaName;
    currentChatLayout = layout;
    await _loadAvatarDataUrl(charAvatarPath, isChar: true);
    await _loadAvatarDataUrl(personaAvatarPath, isChar: false);
  }

  Future<void> _loadAvatarDataUrl(String? path, {required bool isChar}) async {
    if (path == null || path.isEmpty) {
      if (isChar) _charAvatarDataUrl = null;
      else _personaAvatarDataUrl = null;
      return;
    }
    try {
      final file = File(path);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        final base64Str = base64Encode(bytes);
        final ext = path.toLowerCase();
        final mime = ext.endsWith('.jpg') || ext.endsWith('.jpeg')
            ? 'image/jpeg'
            : ext.endsWith('.gif')
                ? 'image/gif'
                : ext.endsWith('.webp')
                    ? 'image/webp'
                    : 'image/png';
        final dataUrl = 'data:$mime;base64,$base64Str';
        if (isChar) _charAvatarDataUrl = dataUrl;
        else _personaAvatarDataUrl = dataUrl;
      }
    } catch (_) {}
  }

  Future<void> applyLayout(String layout) {
    currentChatLayout = layout;
    return _eval('window.bridge?.applyLayout?.("${_escape(layout)}")');
  }

  void Function()? onReady;
  void Function()? onLoadMore;
  void Function(String url)? onLinkClick;
  void Function(String url)? onImageClick;
  void Function(String id, bool isUser, bool isSystem, String content)? onMessageContext;
  void Function(String id, String direction)? onSwipe;
  void Function(String action, String text)? onSelectionAction;
  void Function(String id, String text)? onEditSave;
  void Function(String id)? onEditCancel;

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

    _controller.addJavaScriptHandler(
      handlerName: 'onMessageContext',
      callback: (args) {
        if (args.isEmpty) return;
        try {
          final data = jsonDecode(args[0] as String);
          onMessageContext?.call(
            data['id'] as String? ?? '',
            data['isUser'] as bool? ?? false,
            data['isSystem'] as bool? ?? false,
            data['content'] as String? ?? '',
          );
        } catch (_) {}
      },
    );

    _controller.addJavaScriptHandler(
      handlerName: 'onSwipe',
      callback: (args) {
        if (args.isEmpty) return;
        try {
          final data = jsonDecode(args[0] as String);
          onSwipe?.call(
            data['id'] as String? ?? '',
            data['direction'] as String? ?? 'left',
          );
        } catch (_) {}
      },
    );

    _controller.addJavaScriptHandler(
      handlerName: 'onSelectionAction',
      callback: (args) {
        if (args.isEmpty) return;
        try {
          final data = jsonDecode(args[0] as String);
          onSelectionAction?.call(
            data['action'] as String? ?? 'copy',
            data['text'] as String? ?? '',
          );
        } catch (_) {}
      },
    );

    _controller.addJavaScriptHandler(
      handlerName: 'onEditSave',
      callback: (args) {
        if (args.length < 2) return;
        onEditSave?.call(args[0] as String, args[1] as String);
      },
    );

    _controller.addJavaScriptHandler(
      handlerName: 'onEditCancel',
      callback: (args) {
        if (args.isEmpty) return;
        onEditCancel?.call(args[0] as String);
      },
    );
  }

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
    return _eval('window.bridge?.clearAll()');
  }

  Future<void> scrollToBottom() {
    return _eval('window.bridge?.scrollToBottom()');
  }

  Future<void> scrollToMessage(String messageId) {
    return _eval('window.bridge?.scrollToMessage("$messageId")');
  }

  Future<void> setSearch({
    required String query,
    int activeIndex = -1,
  }) {
    return _eval('window.bridge?.setSearch("${_escape(query)}", $activeIndex)');
  }

  Future<void> setBottomPadding(double px) {
    return _eval('window.bridge?.setBottomPadding(${px.toStringAsFixed(1)})');
  }

  Future<void> startEdit(String messageId) {
    return _eval('window.bridge?.startEdit("${_escape(messageId)}")');
  }

  Future<void> stopEdit(String messageId) {
    return _eval('window.bridge?.stopEdit("${_escape(messageId)}")');
  }

  Future<void> updateMessageContent(String messageId, String text, bool isUser) {
    final json = jsonEncode({'id': messageId, 'text': text, 'isUser': isUser});
    return _callJs('updateMessage', json);
  }

  Future<void> applyTheme(Map<String, String> theme) {
    final json = jsonEncode(theme);
    return _callJs('applyTheme', json);
  }

  Future<void> _callJs(String method, String arg) {
    return _eval('window.bridge?.$method(${_escapeJsonStr(arg)})');
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
    final isAssistant = m.role == 'assistant' || m.role == 'character';
    final isUser = m.role == 'user';

    String? displayName;
    String? avatarColor;
    String? avatarUrl;

    if (isAssistant) {
      displayName = currentCharName ?? m.personaName ?? 'Character';
      avatarColor = currentCharColor;
      avatarUrl = _charAvatarDataUrl;
    } else if (isUser) {
      displayName = m.personaName ?? currentPersonaName ?? 'You';
      avatarUrl = _personaAvatarDataUrl;
    } else {
      displayName = m.personaName ?? 'System';
    }

    return {
      'id': m.id,
      'role': m.role,
      'text': m.content,
      'timestamp': m.timestamp,
      'isUser': isUser,
      'isAssistant': isAssistant,
      'isSystem': m.role == 'system',
      'displayName': displayName,
      if (avatarColor != null) 'avatarColor': avatarColor,
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
      if (m.imagePath != null) 'imagePath': m.imagePath,
      if (m.personaName != null) 'personaName': m.personaName,
      if (m.swipes.isNotEmpty) 'swipeIndex': m.swipeId,
      if (m.swipes.isNotEmpty) 'swipeTotal': m.swipes.length,
      if (m.genTime != null) 'genTime': m.genTime,
      if (m.tokens != null) 'tokens': m.tokens,
      if (m.isError) 'isError': true,
      if (m.isTyping) 'isTyping': true,
      if (m.reasoning != null && m.reasoning!.isNotEmpty) 'reasoning': m.reasoning,
      if (m.triggeredLorebooks.isNotEmpty) 'triggeredLorebooks': m.triggeredLorebooks.length,
      if (m.triggeredMemories.isNotEmpty) 'triggeredMemories': m.triggeredMemories.length,
      if (m.isHidden) 'isHidden': true,
    };
  }
}
