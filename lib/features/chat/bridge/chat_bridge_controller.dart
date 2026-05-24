import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../core/models/chat_message.dart';

class ChatBridgeController {
  final InAppWebViewController _controller;
  final Map<String, Completer<dynamic>> _pendingRequests = {};

  String? currentCharName;
  String? currentCharColor;
  String? currentPersonaName;
  String? currentChatLayout;
  String? _charAvatarDataUrl;
  String? _personaAvatarDataUrl;
  int currentGreetingTotal = 0;
  bool isGenerating = false;
  bool isGeneratingImage = false;
  final Set<String> _coveredMemoryIds = {};
  final Set<String> _pendingMemoryIds = {};
  final Set<String> _draftMemoryIds = {};
  final Map<String, String> _imgBase64Cache = {};
  final Map<String, String> _stripThinkCache = {};
  static final _imgResultRegex = RegExp(r'\[IMG:RESULT:(.*?)\]');

  ChatBridgeController(this._controller) {
    _setupHandlers();
  }

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
    await _loadAvatarDataUrl(charAvatarPath, isChar: true);
    await _loadAvatarDataUrl(personaAvatarPath, isChar: false);
    // Push identity to the WebView so already-rendered messages refresh their
    // user name / persona avatar when the active persona resolves late.
    final payload = jsonEncode({
      'charName': currentCharName,
      'personaName': currentPersonaName,
      'charAvatarUrl': _charAvatarDataUrl,
      'personaAvatarUrl': _personaAvatarDataUrl,
    });
    await _eval('window.bridge?.setIdentity($payload)');
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

  Future<String> _resolveImgResults(String text) async {
    final matches = _imgResultRegex.allMatches(text).toList();
    if (matches.isEmpty) return text;
    final uncached = <int, String>{};
    for (int i = 0; i < matches.length; i++) {
      final payload = matches[i].group(1) ?? '';
      final pipeIdx = payload.indexOf('|');
      final path = pipeIdx != -1 ? payload.substring(0, pipeIdx) : payload;
      if (!_imgBase64Cache.containsKey(path)) {
        uncached[i] = path;
      }
    }
    if (uncached.isNotEmpty) {
      await Future.wait(uncached.entries.map((e) async {
        final path = e.value;
        try {
          final file = File(path);
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            final b64 = base64Encode(bytes);
            final ext = path.toLowerCase();
            final mime = ext.endsWith('.jpg') || ext.endsWith('.jpeg')
                ? 'image/jpeg'
                : ext.endsWith('.gif') ? 'image/gif'
                : ext.endsWith('.webp') ? 'image/webp'
                : 'image/png';
            _imgBase64Cache[path] = 'data:$mime;base64,$b64';
          }
        } catch (_) {}
      }));
    }
    final result = text.replaceAllMapped(_imgResultRegex, (m) {
      final payload = m.group(1) ?? '';
      final pipeIdx = payload.indexOf('|');
      final path = pipeIdx != -1 ? payload.substring(0, pipeIdx) : payload;
      final dataUrl = _imgBase64Cache[path];
      if (dataUrl != null) {
        final rest = pipeIdx != -1 ? payload.substring(pipeIdx) : '';
        return '[IMG:RESULT:$dataUrl$rest]';
      }
      return m.group(0)!;
    });
    return result;
  }

  Future<void> applyLayout(String layout) {
    currentChatLayout = layout;
    return _eval('window.bridge?.applyLayout?.("${_escape(layout)}")');
  }

  void Function()? onReady;
  void Function()? onLoadMore;
  void Function(bool hidden)? onHeaderScroll;
  void Function(String url)? onLinkClick;
  void Function(String url)? onImageClick;
  void Function(String id, bool isUser, bool isSystem, String content)? onMessageContext;
  void Function(String id, String direction)? onSwipe;
  void Function(String id, int direction)? onChangeGreeting;
  void Function(String id)? onRegenerate;
  void Function(String action, String text)? onSelectionAction;
  void Function(String id, String text)? onEditSave;
  void Function(String id)? onEditCancel;
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
      final map = _toMap(messages[i], isLast: i == messages.length - 1, messageIndex: visibleStartIndex + i);
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
    final map = _toMap(message);
    map['text'] = await _resolveImgResults(map['text'] as String);
    final json = jsonEncode(map);
    return _callJs('appendMessage', json);
  }

  Future<void> appendMessages(List<ChatMessage> messages, {int startIndex = 0}) async {
    final List<Map<String, dynamic>> mapped = [];
    for (int i = 0; i < messages.length; i++) {
      final map = _toMap(messages[i], isLast: i == messages.length - 1, messageIndex: startIndex + i);
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
      final map = _toMap(messages[i], messageIndex: visibleStartIndex + i);
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
    final map = _toMap(message);
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

  Future<void> setBackgroundImage(String? filePath, int blur, double opacity) {
    if (filePath == null || filePath.isEmpty) {
      return _eval('window.bridge?.setBackgroundImage(null, 0, 1)');
    }
    var url = filePath.replaceAll('\\', '/');
    if (!url.startsWith('file://')) {
      url = 'file:///$url';
    }
    return _eval('window.bridge?.setBackgroundImage("${_escape(url)}", $blur, $opacity)');
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
    return _eval('window.bridge?.setPerformanceMode(${enabled})');
  }

  Future<void> setSelectionMode(bool enabled) {
    return _eval('window.bridge?.setSelectionMode(${enabled})');
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

  Map<String, dynamic> _toMap(ChatMessage m, {bool isLast = false, int? messageIndex, bool isStreamingUpdate = false}) {
    final isAssistant = m.role == 'assistant' || m.role == 'character';
    final isUser = m.role == 'user';

    String? displayName;
    String? avatarColor;
    String? avatarUrl;

    if (isAssistant) {
      displayName = currentCharName ?? m.personaName ?? 'Character';
      avatarColor = currentCharColor;
      if (!isStreamingUpdate) avatarUrl = _charAvatarDataUrl;
    } else if (isUser) {
      displayName = m.personaName ?? currentPersonaName ?? 'You';
      if (!isStreamingUpdate) avatarUrl = _personaAvatarDataUrl;
    } else {
      displayName = m.personaName ?? 'System';
    }

    String? memoryStatus;
    if (m.memoryCoverage.isNotEmpty) {
      final needsRebuild = m.memoryCoverage['needsRebuild'] as bool? ?? false;
      final stale = m.memoryCoverage['stale'] as bool? ?? false;
      if (needsRebuild) {
        memoryStatus = 'REBUILD';
      } else if (stale) {
        memoryStatus = 'STALE';
      }
    }
    if (memoryStatus == null && _coveredMemoryIds.contains(m.id)) {
      memoryStatus = 'MEM';
    }
    if (memoryStatus == null && _pendingMemoryIds.contains(m.id)) {
      memoryStatus = 'PENDING';
    }
    if (memoryStatus == null && _draftMemoryIds.contains(m.id)) {
      memoryStatus = 'DRAFT';
    }

    return {
      'id': m.id,
      'role': m.role,
      'text': _stripThinkTags(m.content),
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
      'isError': m.isError,
      if (m.isTyping) 'isTyping': true,
      if (m.reasoning != null && m.reasoning!.isNotEmpty) 'reasoning': m.reasoning,
      if (m.isHidden) 'isHidden': true,
      if (isLast) 'isLast': true,
      if (messageIndex != null) 'messageIndex': messageIndex,
      if (m.guidanceText != null && m.guidanceText!.isNotEmpty) 'guidanceText': m.guidanceText,
      if (m.guidanceType != 'GENERATION') 'guidanceType': m.guidanceType,
      if (m.greetingIndex != null) 'greetingIndex': m.greetingIndex,
      if (m.greetingIndex != null && currentGreetingTotal > 1)
        'greetingTotal': currentGreetingTotal,
      if (memoryStatus != null) 'memoryStatus': memoryStatus,
      if (m.triggeredLorebooks.isNotEmpty) 'triggeredLorebooks': m.triggeredLorebooks.map((e) => {'name': e.name, 'lorebookName': e.lorebookName}).toList(),
      if (m.triggeredMemories.isNotEmpty) 'triggeredMemories': m.triggeredMemories.map((e) => {'name': e.name, 'lorebookName': e.lorebookName}).toList(),
      'isGenerating': isGenerating,
    };
  }

  static final _thinkTagRegex = RegExp(r'<think\b[^>]*>[\s\S]*?<\/think\b[^>]*>', caseSensitive: false);
  static final _thinkTagAltRegex = RegExp(r'<think\b([^>]*?)(?:>|\n)([\s\S]*?)<\/think\b', caseSensitive: false);
  static final _thinkingTagRegex = RegExp(r'<thinking\b[^>]*>[\s\S]*?<\/thinking\b[^>]*>', caseSensitive: false);
  static final _thinkingTagAltRegex = RegExp(r'<thinking\b([^>]*?)(?:>|\n)([\s\S]*?)<\/thinking\b', caseSensitive: false);

  String _stripThinkTags(String text) {
    if (_stripThinkCache.containsKey(text)) return _stripThinkCache[text]!;
    if (text.length < 8 && !text.contains('<think')) return text;
    var result = text.replaceAll(_thinkTagRegex, '');
    result = result.replaceAll(_thinkTagAltRegex, '');
    result = result.replaceAll(_thinkingTagRegex, '');
    result = result.replaceAll(_thinkingTagAltRegex, '');
    result = result.trim();
    if (_stripThinkCache.length > 500) _stripThinkCache.clear();
    _stripThinkCache[text] = result;
    return result;
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
