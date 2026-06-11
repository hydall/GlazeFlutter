import 'dart:convert';

import '../../../core/models/chat_message.dart';
import 'chat_message_mapper.dart';
import 'chat_bridge_controller.dart';

/// Outgoing chat-message commands (Dart -> JS). All message rendering
/// goes through this group: bulk replace, append, prepend, update,
/// remove, plus scroll helpers. The mapper is invoked here to convert
/// from [ChatMessage] to a JS-friendly map before each call.
class MessageBridgeCommands {
  final ChatBridgeController _host;

  MessageBridgeCommands(this._host);

  Future<void> setMessages(
    List<ChatMessage> messages, {
    int visibleStartIndex = 0,
  }) async {
    final List<Map<String, dynamic>> mapped = [];
    for (int i = 0; i < messages.length; i++) {
      final map = ChatMessageMapper.toMap(
        messages[i],
        _host.mapperContext,
        isLast: i == messages.length - 1,
        messageIndex: visibleStartIndex + i,
        displayRegexes: _host.displayRegexes,
        character: _host.regexCharacter,
        persona: _host.regexPersona,
      );
      _resolveMappedFileUrls(map);
      mapped.add(map);
    }
    final resolved = await Future.wait(
      mapped.map((m) => _host.resolveImgResults(m['text'] as String)),
    );
    for (int i = 0; i < mapped.length; i++) {
      mapped[i]['text'] = resolved[i];
    }
    final json = jsonEncode(mapped);
    return _host.callJs('setMessages', json);
  }

  Future<void> appendMessage(ChatMessage message) async {
    final map = ChatMessageMapper.toMap(
      message,
      _host.mapperContext,
      displayRegexes: _host.displayRegexes,
      character: _host.regexCharacter,
      persona: _host.regexPersona,
    );
    _resolveMappedFileUrls(map);
    map['text'] = await _host.resolveImgResults(map['text'] as String);
    final json = jsonEncode(map);
    return _host.callJs('appendMessage', json);
  }

  Future<void> appendMessages(
    List<ChatMessage> messages, {
    int startIndex = 0,
  }) async {
    final List<Map<String, dynamic>> mapped = [];
    for (int i = 0; i < messages.length; i++) {
      final map = ChatMessageMapper.toMap(
        messages[i],
        _host.mapperContext,
        isLast: i == messages.length - 1,
        messageIndex: startIndex + i,
        displayRegexes: _host.displayRegexes,
        character: _host.regexCharacter,
        persona: _host.regexPersona,
      );
      _resolveMappedFileUrls(map);
      mapped.add(map);
    }
    final resolved = await Future.wait(
      mapped.map((m) => _host.resolveImgResults(m['text'] as String)),
    );
    for (int i = 0; i < mapped.length; i++) {
      mapped[i]['text'] = resolved[i];
    }
    final json = jsonEncode(mapped);
    return _host.callJs('appendMessages', json);
  }

  Future<void> prependMessages(
    List<ChatMessage> messages, {
    int visibleStartIndex = 0,
  }) async {
    final List<Map<String, dynamic>> mapped = [];
    for (int i = 0; i < messages.length; i++) {
      final map = ChatMessageMapper.toMap(
        messages[i],
        _host.mapperContext,
        messageIndex: visibleStartIndex + i,
        displayRegexes: _host.displayRegexes,
        character: _host.regexCharacter,
        persona: _host.regexPersona,
      );
      _resolveMappedFileUrls(map);
      mapped.add(map);
    }
    final resolved = await Future.wait(
      mapped.map((m) => _host.resolveImgResults(m['text'] as String)),
    );
    for (int i = 0; i < mapped.length; i++) {
      mapped[i]['text'] = resolved[i];
    }
    final json = jsonEncode(mapped);
    return _host.callJs('prependMessages', json);
  }

  Future<void> updateMessage(
    ChatMessage message, {
    bool isStreamingUpdate = false,
    bool isLast = false,
  }) async {
    final map = ChatMessageMapper.toMap(
      message,
      _host.mapperContext,
      isStreamingUpdate: isStreamingUpdate,
      isLast: isLast,
      displayRegexes: _host.displayRegexes,
      character: _host.regexCharacter,
      persona: _host.regexPersona,
    );
    _resolveMappedFileUrls(map);
    map['text'] = await _host.resolveImgResults(map['text'] as String);
    final json = jsonEncode(map);
    return _host.callJs('updateMessage', json);
  }

  Future<void> updateMessageContent(
    String messageId,
    String text,
    bool isUser,
  ) async {
    final resolved = await _host.resolveImgResults(text);
    final json = jsonEncode({'id': messageId, 'text': resolved, 'isUser': isUser});
    return _host.callJs('updateMessage', json);
  }

  Future<void> removeMessage(String messageId) {
    return _host.callJs('removeMessage', messageId);
  }

  void _resolveMappedFileUrls(Map<String, dynamic> map) {
    final imagePath = map['imagePath'];
    if (imagePath is String) {
      map['imagePath'] = _host.resolveLocalFileUrl(imagePath) ?? imagePath;
    }
  }

  Future<void> setLastMessage(String? messageId) {
    if (messageId != null) {
      return _host.evalJs(
        'window.bridge?.setLastMessage("${_host.escape(messageId)}")',
      );
    } else {
      return _host.evalJs('window.bridge?.setLastMessage(null)');
    }
  }

  Future<void> clearAll() {
    return _host.evalJs('window.bridge?.clearAll()');
  }

  Future<void> scrollToBottom() {
    return _host.evalJs('window.bridge?.scrollToBottom()');
  }

  Future<void> scrollToMessage(String messageId, {bool highlight = false}) {
    return _host.evalJs(
      'window.bridge?.scrollToMessage("${_host.escape(messageId)}", $highlight)',
    );
  }
}
