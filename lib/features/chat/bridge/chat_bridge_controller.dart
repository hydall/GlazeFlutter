import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../core/models/chat_message.dart';
import 'chat_message_mapper.dart';

class ChatBridgeController {
  final InAppWebViewController _controller;
  final Map<String, Completer<dynamic>> _pendingRequests = {};

  String? currentCharName;
  String? currentCharColor;
  String? currentPersonaName;
  String? currentChatLayout;
  String? _charAvatarUrl;
  String? _personaAvatarUrl;
  int currentGreetingTotal = 0;
  bool isGenerating = false;
  bool isGeneratingImage = false;
  final Set<String> _coveredMemoryIds = {};
  final Set<String> _pendingMemoryIds = {};
  final Set<String> _draftMemoryIds = {};

  ChatBridgeController(this._controller) {
    _setupHandlers();
  }

  ChatMessageMapperContext get _ctx => ChatMessageMapperContext(
    currentCharName: currentCharName,
    currentCharColor: currentCharColor,
    currentPersonaName: currentPersonaName,
    charAvatarDataUrl: _charAvatarUrl,
    personaAvatarDataUrl: _personaAvatarUrl,
    isGenerating: isGenerating,
    coveredMemoryIds: _coveredMemoryIds,
    pendingMemoryIds: _pendingMemoryIds,
    draftMemoryIds: _draftMemoryIds,
    greetingTotal: currentGreetingTotal,
  );

  void resolveRequest(String requestId, dynamic result) {
    final completer = _pendingRequests.remove(requestId);
    completer?.complete(result);
  }

  void rejectRequest(String requestId, String error) {
    final completer = _pendingRequests.remove(requestId);
    completer?.completeError(Exception(error));
  }

  Future<dynamic> requestFromJs(String requestId, Duration timeout) {
    final completer = Completer<dynamic>();
    _pendingRequests[requestId] = completer;
    Future.delayed(timeout, () {
      if (_pendingRequests.remove(requestId) != null) {
        completer.completeError(TimeoutException('Bridge request timed out'));
      }
    });
    return completer.future;
  }

  Future<void> setIdentity({
    String? charName,
    String? charColor,
    String? personaName,
    String? layout,
    String? charAvatarPath,
    String? personaAvatarPath,
    int? greetingTotal,
  }) async {
    currentCharName = charName;
    currentCharColor = charColor;
    currentPersonaName = personaName;
    currentChatLayout = layout;
    if (greetingTotal != null) currentGreetingTotal = greetingTotal;
    _setAvatarUrl(charAvatarPath, isChar: true);
    _setAvatarUrl(personaAvatarPath, isChar: false);
    // Push identity to the WebView so already-rendered messages refresh their
    // user name / persona avatar when the active persona resolves late.
    final payload = jsonEncode({
      'charName': currentCharName,
      'personaName': currentPersonaName,
      'charAvatarUrl': _charAvatarUrl,
      'personaAvatarUrl': _personaAvatarUrl,
    });
    await _eval('window.bridge?.setIdentity($payload)');
  }

  void _setAvatarUrl(String? path, {required bool isChar}) {
    String? url;
    if (path != null && path.isNotEmpty) {
      if (path.startsWith('data:') ||
          path.startsWith('http://') ||
          path.startsWith('https://') ||
          path.startsWith('file://')) {
        url = path;
      } else {
        url = 'file:///${path.replaceAll('\\', '/')}';
      }
    }
    if (isChar) {
      _charAvatarUrl = url;
    } else {
      _personaAvatarUrl = url;
    }
  }

  Future<String> _resolveImgResults(String text) async {
    // Keep image paths in the bridge payload. The WebView formatter resolves
    // local paths to file:// URLs, avoiding huge base64 strings on Android.
    return text;
  }

  Future<void> applyLayout(String layout) {
    currentChatLayout = layout;
    return _eval('window.bridge?.applyLayout?.("${_escape(layout)}")');
  }

  void Function()? onReady;
  void Function()? onLoadMore;
  void Function(bool hidden)? onHeaderScroll;
  void Function(bool visible)? onScrollToBottomVisibility;
  void Function(String url)? onLinkClick;
  void Function(String url)? onImageClick;
  void Function(String id, bool isUser, bool isSystem, String content)? onMessageContext;
  void Function(String id, String direction)? onSwipe;
  void Function(String id, int direction)? onChangeGreeting;
  void Function(String id)? onRegenerate;
  void Function(String action, String text)? onSelectionAction;
  void Function(String id, String text)? onEditSave;
  void Function(String id)? onEditCancel;
  void Function(String id, bool focused)? onEditFocusChange;
  void Function(String id, String guidanceText)? onGuidedSwipe;
  void Function(String id)? onMemoryClick;
  void Function(String id)? onToggleHidden;
  void Function(List<String> ids)? onSelectionChange;
  void Function(String id)? onInjectClick;
  void Function(String instruction, String messageId)? onImgRetry;
  void Function(String instruction, String messageId)? onImgFind;
  void Function(String instruction, String messageId)? onImgRegen;
  void Function()? onImgCancel;
  void Function()? onStop;

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
      handlerName: 'onHeaderScroll',
      callback: (args) {
        if (args.isEmpty) return;
        onHeaderScroll?.call(args[0] == true);
      },
    );

    _controller.addJavaScriptHandler(
      handlerName: 'onScrollToBottomVisibility',
      callback: (args) {
        if (args.isEmpty) return;
        onScrollToBottomVisibility?.call(args[0] == true);
      },
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
      handlerName: 'onRegenerate',
      callback: (args) {
        if (args.isNotEmpty) onRegenerate?.call(args[0] as String);
      },
    );

    _controller.addJavaScriptHandler(
      handlerName: 'onChangeGreeting',
      callback: (args) {
        if (args.length < 2) return;
        final id = args[0] as String? ?? '';
        final dir = args[1] is int
            ? args[1] as int
            : int.tryParse('${args[1]}') ?? 0;
        if (id.isEmpty || dir == 0) return;
        onChangeGreeting?.call(id, dir);
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

    _controller.addJavaScriptHandler(
      handlerName: 'onEditFocusChange',
      callback: (args) {
        if (args.length < 2) return;
        onEditFocusChange?.call(args[0] as String, args[1] == true);
      },
    );

    _controller.addJavaScriptHandler(
      handlerName: 'onGuidedSwipe',
      callback: (args) {
        if (args.length < 2) return;
        onGuidedSwipe?.call(args[0] as String, args[1] as String);
      },
    );

    _controller.addJavaScriptHandler(
      handlerName: 'onMemoryClick',
      callback: (args) {
        if (args.isEmpty) return;
        onMemoryClick?.call(args[0] as String);
      },
    );

    _controller.addJavaScriptHandler(
      handlerName: 'onToggleHidden',
      callback: (args) {
        if (args.isEmpty) return;
        onToggleHidden?.call(args[0] as String);
      },
    );

    _controller.addJavaScriptHandler(
      handlerName: 'onSelectionChange',
      callback: (args) {
        if (args.isEmpty) return;
        try {
          final list = jsonDecode(args[0] as String) as List;
          onSelectionChange?.call(list.cast<String>());
        } catch (_) {}
      },
    );

    _controller.addJavaScriptHandler(
      handlerName: 'onInjectClick',
      callback: (args) {
        if (args.isEmpty) return;
        onInjectClick?.call(args[0] as String);
      },
    );

    _controller.addJavaScriptHandler(
      handlerName: 'onImgRetry',
      callback: (args) {
        if (args.length < 2) return;
        onImgRetry?.call(args[0] as String, args[1] as String);
      },
    );

    _controller.addJavaScriptHandler(
      handlerName: 'onImgFind',
      callback: (args) {
        if (args.length < 2) return;
        onImgFind?.call(args[0] as String, args[1] as String);
      },
    );

    _controller.addJavaScriptHandler(
      handlerName: 'onImgRegen',
      callback: (args) {
        debugPrint('[BRIDGE] onImgRegen called, args=$args');
        if (args.length < 2) return;
        onImgRegen?.call(args[0] as String, args[1] as String);
      },
    );

    _controller.addJavaScriptHandler(
      handlerName: 'onImgCancel',
      callback: (args) {
        debugPrint('[BRIDGE] onImgCancel called');
        onImgCancel?.call();
      },
    );

    _controller.addJavaScriptHandler(
      handlerName: 'onStop',
      callback: (args) => onStop?.call(),
    );

    _controller.addJavaScriptHandler(
      handlerName: 'onBridgeResolve',
      callback: (args) {
        if (args.length < 2) return;
        resolveRequest(args[0] as String, args[1]);
      },
    );

    _controller.addJavaScriptHandler(
      handlerName: 'onBridgeReject',
      callback: (args) {
        if (args.length < 2) return;
        rejectRequest(args[0] as String, args[1].toString());
      },
    );
  }

  Future<void> setMessages(List<ChatMessage> messages, {int visibleStartIndex = 0}) async {
    final List<Map<String, dynamic>> mapped = [];
    for (int i = 0; i < messages.length; i++) {
      final map = ChatMessageMapper.toMap(messages[i], _ctx, isLast: i == messages.length - 1, messageIndex: visibleStartIndex + i);
      mapped.add(map);
    }
    final resolved = await Future.wait(mapped.map((m) => _resolveImgResults(m['text'] as String)));
    for (int i = 0; i < mapped.length; i++) {
      mapped[i]['text'] = resolved[i];
    }
    final json = jsonEncode(mapped);
    return _callJs('setMessages', json);
  }

  Future<void> appendMessage(ChatMessage message) async {
    final map = ChatMessageMapper.toMap(message, _ctx);
    map['text'] = await _resolveImgResults(map['text'] as String);
    final json = jsonEncode(map);
    return _callJs('appendMessage', json);
  }

  Future<void> appendMessages(List<ChatMessage> messages, {int startIndex = 0}) async {
    final List<Map<String, dynamic>> mapped = [];
    for (int i = 0; i < messages.length; i++) {
      final map = ChatMessageMapper.toMap(messages[i], _ctx, isLast: i == messages.length - 1, messageIndex: startIndex + i);
      mapped.add(map);
    }
    final resolved = await Future.wait(mapped.map((m) => _resolveImgResults(m['text'] as String)));
    for (int i = 0; i < mapped.length; i++) {
      mapped[i]['text'] = resolved[i];
    }
    final json = jsonEncode(mapped);
    return _callJs('appendMessages', json);
  }

  Future<void> prependMessages(List<ChatMessage> messages, {int visibleStartIndex = 0}) async {
    final List<Map<String, dynamic>> mapped = [];
    for (int i = 0; i < messages.length; i++) {
      final map = ChatMessageMapper.toMap(messages[i], _ctx, messageIndex: visibleStartIndex + i);
      mapped.add(map);
    }
    final resolved = await Future.wait(mapped.map((m) => _resolveImgResults(m['text'] as String)));
    for (int i = 0; i < mapped.length; i++) {
      mapped[i]['text'] = resolved[i];
    }
    final json = jsonEncode(mapped);
    return _callJs('prependMessages', json);
  }

  Future<void> updateMessage(ChatMessage message) async {
    final map = ChatMessageMapper.toMap(message, _ctx, isStreamingUpdate: true);
    map['text'] = await _resolveImgResults(map['text'] as String);
    final json = jsonEncode(map);
    return _callJs('updateMessage', json);
  }

  Future<void> removeMessage(String messageId) {
    return _callJs('removeMessage', messageId);
  }

  Future<void> setLastMessage(String? messageId) {
    if (messageId != null) {
      return _eval('window.bridge?.setLastMessage("${_escape(messageId)}")');
    } else {
      return _eval('window.bridge?.setLastMessage(null)');
    }
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

  Future<void> setTopPadding(double px) {
    return _eval('window.bridge?.setTopPadding(${px.toStringAsFixed(1)})');
  }

  Future<void> startEdit(String messageId) {
    return _eval('window.bridge?.startEdit("${_escape(messageId)}")');
  }

  Future<void> stopEdit(String messageId) {
    return _eval('window.bridge?.stopEdit("${_escape(messageId)}")');
  }

  Future<void> setBackgroundNoise(double opacity, double intensity) {
    return _eval(
      'window.bridge?.setBackgroundNoise(${opacity.toStringAsFixed(3)}, ${intensity.toStringAsFixed(3)})',
    );
  }

  Future<void> setBackgroundImage(String? src, int blur, double opacity) {
    if (src == null || src.isEmpty) {
      return _eval('window.bridge?.setBackgroundImage(null, 0, 1)');
    }
    String url;
    if (src.startsWith('data:') ||
        src.startsWith('http://') ||
        src.startsWith('https://') ||
        src.startsWith('file://')) {
      url = src;
    } else {
      url = 'file:///${src.replaceAll('\\', '/')}';
    }
    // Pass through JSON encoder — data URIs can be megabytes long and may
    // contain characters that the lightweight _escape helper doesn't handle.
    final encoded = jsonEncode(url);
    return _eval('window.bridge?.setBackgroundImage($encoded, $blur, $opacity)');
  }

  Future<void> setChatFont({String? fontName, String? fontDataUrl, required double fontSize, required double letterSpacing}) {
    final name = fontName != null ? '"${_escape(fontName)}"' : 'null';
    final url = fontDataUrl != null ? '"${_escape(fontDataUrl)}"' : 'null';
    return _eval('window.bridge?.setChatFont($name, $url, ${fontSize.toStringAsFixed(1)}, ${letterSpacing.toStringAsFixed(2)})');
  }

  Future<void> updateMessageContent(String messageId, String text, bool isUser) async {
    final resolved = await _resolveImgResults(text);
    final json = jsonEncode({'id': messageId, 'text': resolved, 'isUser': isUser});
    return _callJs('updateMessage', json);
  }

  Future<void> applyTheme(Map<String, String> theme) {
    final json = jsonEncode(theme);
    return _callJs('applyTheme', json);
  }

  Future<void> setPerformanceMode(bool enabled) {
    return _eval('window.bridge?.setPerformanceMode($enabled)');
  }

  Future<void> setMessageSettings({
    required bool batterySaver,
    required bool hideMessageId,
    required bool hideGenerationTime,
    required bool hideTokenCount,
    required bool disableSwipeRegeneration,
  }) {
    final json = jsonEncode({
      'batterySaver': batterySaver,
      'hideMessageId': hideMessageId,
      'hideGenerationTime': hideGenerationTime,
      'hideTokenCount': hideTokenCount,
      'disableSwipeRegeneration': disableSwipeRegeneration,
    });
    return _callJs('setMessageSettings', json);
  }

  Future<void> setSelectionMode(bool enabled) {
    return _eval('window.bridge?.setSelectionMode($enabled)');
  }

  Future<void> toggleMessageSelection(String id) {
    return _eval('window.bridge?.renderer?.toggleMessageSelection("${_escape(id)}")');
  }

  Future<void> _callJs(String method, String arg) {
    return _eval('window.bridge?.$method(${_escapeJsonStr(arg)})');
  }

  Future<void> _eval(String source) async {
    await _controller.evaluateJavascript(source: source);
  }

  Future<void> evalJs(String source) async {
    await _controller.evaluateJavascript(source: source);
  }

  String _escape(String s) {
    return s.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('\n', '\\n');
  }

  String _escapeJsonStr(String s) {
    return '"${jsonEncode(s).substring(1, jsonEncode(s).length - 1)}"';
  }

  void updateMemoryBookData({
    required List<Map<String, dynamic>> entries,
    required List<Map<String, dynamic>> pendingDrafts,
  }) {
    _coveredMemoryIds.clear();
    _pendingMemoryIds.clear();
    _draftMemoryIds.clear();
    for (final entry in entries) {
      final status = entry['status'] as String?;
      final ids = entry['messageIds'];
      if (ids is List) {
        if (status == 'active') {
          for (final id in ids) {
            _coveredMemoryIds.add(id.toString());
          }
        } else if (status == 'pending_generation') {
          for (final id in ids) {
            _pendingMemoryIds.add(id.toString());
          }
        }
      }
    }
    for (final draft in pendingDrafts) {
      final ids = draft['messageIds'];
      if (ids is List) {
        for (final id in ids) {
          _draftMemoryIds.add(id.toString());
        }
      }
    }
  }
}
