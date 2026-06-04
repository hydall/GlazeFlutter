import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../core/models/character.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/persona.dart';
import '../../../core/models/preset.dart';
import 'chat_message_mapper.dart';
import 'bridge_handlers.dart';
import 'bridge_message_commands.dart';
import 'bridge_theme_commands.dart';
import 'bridge_identity_commands.dart';
import 'bridge_layout_commands.dart';
import 'bridge_memory_commands.dart';

/// Bridge between the chat WebView (JS) and Flutter. Owns the shared
/// state (current character, persona, layout, memory coverage, regex
/// display config) and the JS handler registration. Splits outgoing
/// commands into focused groups:
///
///   - [messages]: set/append/update/remove messages, scroll helpers
///   - [theme]:    applyTheme, fonts, background image/noise, perf mode
///   - [identity]: setIdentity, applyLayout, regex context
///   - [layout]:   padding, search, edit, selection, message settings
///   - [memory]:   memory book data updates + covered/pending/draft sets
///
/// Inbound callbacks (JS -> Dart) are exposed as nullable function
/// properties on the host and registered via [setupHandlers].
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

  List<PresetRegex> _displayRegexes = [];
  Character? _regexCharacter;
  Persona? _regexPersona;

  late final MessageBridgeCommands messages = MessageBridgeCommands(this);
  late final ThemeBridgeCommands theme = ThemeBridgeCommands(this);
  late final IdentityBridgeCommands identity = IdentityBridgeCommands(this);
  late final LayoutBridgeCommands layout = LayoutBridgeCommands(this);
  late final MemoryBridgeCommands memory = MemoryBridgeCommands(this);

  ChatBridgeController(this._controller) {
    setupHandlers();
  }

  // Getters used by command groups. They intentionally expose mutable
  // internals so groups can read and update shared state without
  // bouncing every access through a getter method.
  String? get charAvatarUrl => _charAvatarUrl;
  String? get personaAvatarUrl => _personaAvatarUrl;
  Set<String> get coveredMemoryIds => _coveredMemoryIds;
  Set<String> get pendingMemoryIds => _pendingMemoryIds;
  Set<String> get draftMemoryIds => _draftMemoryIds;
  List<PresetRegex> get displayRegexes => _displayRegexes;
  Character? get regexCharacter => _regexCharacter;
  Persona? get regexPersona => _regexPersona;

  ChatMessageMapperContext get mapperContext => ChatMessageMapperContext(
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

  void setRegexContext(List<PresetRegex> regexes, Character? char, Persona? persona) {
    _displayRegexes = regexes;
    _regexCharacter = char;
    _regexPersona = persona;
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

  // ── Helpers used by command groups. Exposed as instance methods so
  // groups don't need to know about the InAppWebViewController or
  // private state of the host.

  Future<String> resolveImgResults(String text) async {
    // Keep image paths in the bridge payload. The WebView formatter
    // resolves local paths to file:// URLs, avoiding huge base64
    // strings on Android.
    return text;
  }

  String normalizeLayout(String? layout) {
    final raw = (layout ?? '').trim().toLowerCase();
    if (raw == 'bubble' || raw == 'bubbles') return 'bubble';
    return 'default';
  }

  void setAvatarUrl(String? path, {required bool isChar}) {
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

  Future<void> callJs(String method, String arg) {
    return evalJs('window.bridge?.$method(${escapeJsonStr(arg)})');
  }

  Future<void> evalJs(String source) async {
    await _controller.evaluateJavascript(source: source);
  }

  String escape(String s) {
    return s.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('\n', '\\n');
  }

  String escapeJsonStr(String s) {
    return '"${jsonEncode(s).substring(1, jsonEncode(s).length - 1)}"';
  }

  // ── Inbound callbacks (JS -> Dart). Set by the host (chat_webview_widget)
  // and forwarded to a typed bridge command when the user interacts with
  // the WebView.

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

  /// Register JS handlers for every callback declared on this host. The
  /// declarations live in [bridgeHandlers] (data-driven) so the actual
  /// dispatch table is short and auditable.
  void setupHandlers() {
    for (final entry in bridgeHandlers.entries) {
      final name = entry.key;
      final spec = entry.value;
      _controller.addJavaScriptHandler(
        handlerName: name,
        callback: (args) => _dispatch(name, spec, args),
      );
    }
  }

  dynamic _dispatch(String name, HandlerSpec spec, List<dynamic> args) {
    switch (spec.kind) {
      case HandlerKind.noArgs:
        return _dispatchNoArgs(name);
      case HandlerKind.boolArg:
        return _dispatchBoolArg(name, args);
      case HandlerKind.stringArg:
        return _dispatchStringArg(name, args);
      case HandlerKind.jsonObject:
        return _dispatchJsonObject(name, spec, args);
      case HandlerKind.idStringPair:
        return _dispatchIdStringPair(name, args);
      case HandlerKind.idIntPair:
        return _dispatchIdIntPair(name, args);
      case HandlerKind.idBoolPair:
        return _dispatchIdBoolPair(name, args);
      case HandlerKind.idStringStringPair:
        return _dispatchIdStringStringPair(name, args);
      case HandlerKind.imageAction:
        return _dispatchImageAction(name, spec, args);
      case HandlerKind.idList:
        return _dispatchIdList(name, args);
    }
  }

  void _dispatchNoArgs(String name) {
    switch (name) {
      case 'onWebViewReady': onReady?.call();
      case 'onLoadMore': onLoadMore?.call();
      case 'onStop': onStop?.call();
      case 'onImgCancel': onImgCancel?.call();
    }
  }

  void _dispatchBoolArg(String name, List<dynamic> args) {
    if (args.isEmpty) return;
    final v = args[0] == true;
    switch (name) {
      case 'onHeaderScroll': onHeaderScroll?.call(v);
      case 'onScrollToBottomVisibility': onScrollToBottomVisibility?.call(v);
    }
  }

  void _dispatchStringArg(String name, List<dynamic> args) {
    if (args.isEmpty) return;
    final s = args[0] as String;
    switch (name) {
      case 'onLinkClick': onLinkClick?.call(s);
      case 'onImageClick': onImageClick?.call(s);
      case 'onRegenerate': onRegenerate?.call(s);
      case 'onEditCancel': onEditCancel?.call(s);
      case 'onMemoryClick': onMemoryClick?.call(s);
      case 'onToggleHidden': onToggleHidden?.call(s);
      case 'onInjectClick': onInjectClick?.call(s);
    }
  }

  void _dispatchJsonObject(String name, HandlerSpec spec, List<dynamic> args) {
    if (args.isEmpty) return;
    try {
      final data = jsonDecode(args[0] as String) as Map<String, dynamic>;
      switch (name) {
        case 'onMessageContext':
          onMessageContext?.call(
            data['id'] as String? ?? '',
            data['isUser'] as bool? ?? false,
            data['isSystem'] as bool? ?? false,
            data['content'] as String? ?? '',
          );
        case 'onSwipe':
          onSwipe?.call(
            data['id'] as String? ?? '',
            data['direction'] as String? ?? 'left',
          );
        case 'onSelectionAction':
          onSelectionAction?.call(
            data['action'] as String? ?? 'copy',
            data['text'] as String? ?? '',
          );
      }
    } catch (_) {}
  }

  void _dispatchIdStringPair(String name, List<dynamic> args) {
    if (args.length < 2) return;
    final id = args[0] as String? ?? '';
    final s = args[1] as String? ?? '';
    switch (name) {
      case 'onEditSave': onEditSave?.call(id, s);
    }
  }

  void _dispatchIdIntPair(String name, List<dynamic> args) {
    if (args.length < 2) return;
    final id = args[0] as String? ?? '';
    final dir = args[1] is int
        ? args[1] as int
        : int.tryParse('${args[1]}') ?? 0;
    if (id.isEmpty || dir == 0) return;
    switch (name) {
      case 'onChangeGreeting': onChangeGreeting?.call(id, dir);
    }
  }

  void _dispatchIdBoolPair(String name, List<dynamic> args) {
    if (args.length < 2) return;
    final id = args[0] as String? ?? '';
    final v = args[1] == true;
    switch (name) {
      case 'onEditFocusChange': onEditFocusChange?.call(id, v);
    }
  }

  void _dispatchIdStringStringPair(String name, List<dynamic> args) {
    if (args.length < 2) return;
    final id = args[0] as String? ?? '';
    final s = args[1] as String? ?? '';
    switch (name) {
      case 'onGuidedSwipe': onGuidedSwipe?.call(id, s);
    }
  }

  void _dispatchImageAction(String name, HandlerSpec spec, List<dynamic> args) {
    if (args.length < 2) return;
    final instr = args[0] as String? ?? '';
    final msgId = args[1] as String? ?? '';
    if (spec.debugPrint != null) {
      debugPrint(spec.debugPrint!.replaceAll('\$args', args.toString()));
    }
    switch (name) {
      case 'onImgRetry': onImgRetry?.call(instr, msgId);
      case 'onImgFind': onImgFind?.call(instr, msgId);
      case 'onImgRegen': onImgRegen?.call(instr, msgId);
    }
  }

  void _dispatchIdList(String name, List<dynamic> args) {
    if (args.isEmpty) return;
    try {
      final list = jsonDecode(args[0] as String) as List;
      switch (name) {
        case 'onSelectionChange': onSelectionChange?.call(list.cast<String>());
      }
    } catch (_) {}
  }

  // ── Outgoing-command facade. These methods exist so existing callers
  // in chat_webview_widget.dart (and elsewhere) can keep using
  // _bridge!.setMessages(...), _bridge!.applyTheme(...) without knowing
  // about the new group structure. Each call delegates to the
  // corresponding group instance. They are intentionally one-liners
  // so the host stays a thin facade; new code should prefer the
  // group property directly: _bridge.messages.setMessages(...).

  // Messages
  Future<void> setMessages(List<ChatMessage> m, {int visibleStartIndex = 0}) =>
      messages.setMessages(m, visibleStartIndex: visibleStartIndex);
  Future<void> appendMessage(ChatMessage m) => messages.appendMessage(m);
  Future<void> appendMessages(List<ChatMessage> m, {int startIndex = 0}) =>
      messages.appendMessages(m, startIndex: startIndex);
  Future<void> prependMessages(List<ChatMessage> m, {int visibleStartIndex = 0}) =>
      messages.prependMessages(m, visibleStartIndex: visibleStartIndex);
  Future<void> updateMessage(ChatMessage m, {bool isStreamingUpdate = false}) =>
      messages.updateMessage(m, isStreamingUpdate: isStreamingUpdate);
  Future<void> updateMessageContent(String id, String text, bool isUser) =>
      messages.updateMessageContent(id, text, isUser);
  Future<void> removeMessage(String id) => messages.removeMessage(id);
  Future<void> setLastMessage(String? id) => messages.setLastMessage(id);
  Future<void> clearAll() => messages.clearAll();
  Future<void> scrollToBottom() => messages.scrollToBottom();
  Future<void> scrollToMessage(String id) => messages.scrollToMessage(id);

  // Theme
  Future<void> setBackgroundNoise(double opacity, double intensity) =>
      theme.setBackgroundNoise(opacity, intensity);
  Future<void> setBackgroundImage(String? src, int blur, double opacity) =>
      theme.setBackgroundImage(src, blur, opacity);
  Future<void> setChatFont({
    String? fontName,
    String? fontDataUrl,
    required double fontSize,
    required double letterSpacing,
  }) =>
      theme.setChatFont(
        fontName: fontName,
        fontDataUrl: fontDataUrl,
        fontSize: fontSize,
        letterSpacing: letterSpacing,
      );
  Future<void> applyTheme(Map<String, String> t) => theme.applyTheme(t);
  Future<void> setPerformanceMode(bool enabled) =>
      theme.setPerformanceMode(enabled);

  // Identity
  Future<void> setIdentity({
    String? charName,
    String? charColor,
    String? personaName,
    String? layout,
    String? charAvatarPath,
    String? personaAvatarPath,
    int? greetingTotal,
  }) =>
      identity.setIdentity(
        charName: charName,
        charColor: charColor,
        personaName: personaName,
        layout: layout,
        charAvatarPath: charAvatarPath,
        personaAvatarPath: personaAvatarPath,
        greetingTotal: greetingTotal,
      );
  Future<void> applyLayout(String l) => identity.applyLayout(l);

  // Layout
  Future<void> setSearch({required String query, int activeIndex = -1}) =>
      layout.setSearch(query: query, activeIndex: activeIndex);
  Future<void> setBottomPadding(double px) => layout.setBottomPadding(px);
  Future<void> setTopPadding(double px) => layout.setTopPadding(px);
  Future<void> startEdit(String id) => layout.startEdit(id);
  Future<void> stopEdit(String id) => layout.stopEdit(id);
  Future<void> setMessageSettings({
    required bool batterySaver,
    required bool hideMessageId,
    required bool hideGenerationTime,
    required bool hideTokenCount,
    required bool disableSwipeRegeneration,
  }) =>
      layout.setMessageSettings(
        batterySaver: batterySaver,
        hideMessageId: hideMessageId,
        hideGenerationTime: hideGenerationTime,
        hideTokenCount: hideTokenCount,
        disableSwipeRegeneration: disableSwipeRegeneration,
      );
  Future<void> setSelectionMode(bool enabled) =>
      layout.setSelectionMode(enabled);
  Future<void> toggleMessageSelection(String id) =>
      layout.toggleMessageSelection(id);

  // Memory
  void updateMemoryBookData({
    required List<Map<String, dynamic>> entries,
    required List<Map<String, dynamic>> pendingDrafts,
  }) =>
      memory.updateMemoryBookData(
        entries: entries,
        pendingDrafts: pendingDrafts,
      );
}
