import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:glaze_flutter/core/models/chat_message.dart';
import 'package:glaze_flutter/features/chat/bridge/chat_bridge_controller.dart';
import 'package:glaze_flutter/features/chat/bridge/chat_overlay_blur_region.dart';
import 'package:glaze_flutter/features/chat/widgets/chat_webview_sync_dispatcher.dart';

void main() {
  group('ChatWebViewSyncDispatcher', () {
    test(
      'does not skip just-sent user message after stale streaming flag',
      () async {
        final syncState = ChatWebViewSyncState()
          ..wasGenerating = false
          ..streamingSent = true;
        final dispatcher = ChatWebViewSyncDispatcher(state: syncState);

        final result = dispatcher.dispatch(
          bridge: _FakeBridge(),
          old: _fields(isGenerating: false, messages: [_assistant('a1')]),
          current: _fields(
            isGenerating: true,
            messages: [_assistant('a1'), _user('u1')],
          ),
          oldMessages: [_assistant('a1')],
          newMessages: [_assistant('a1'), _user('u1')],
          streamingId: '__streaming__',
          onSyncExtBlockPanels: () async {},
          appendMessage: (_) async {},
          buildStreamingPlaceholder: () => _assistant('__streaming__'),
        );

        expect(result.runMessageSync, isTrue);
        expect(result.appendPlaceholder, isTrue);
        expect(syncState.streamingSent, isFalse);
      },
    );

    test(
      'refreshes last assistant controls on stream-to-post-gen transition',
      () {
        final bridge = _FakeBridge()..isGenerating = true;
        final message = _assistant('a1');
        final dispatcher = ChatWebViewSyncDispatcher(
          state: ChatWebViewSyncState()..wasGenerating = true,
        );

        dispatcher.dispatch(
          bridge: bridge,
          old: _fields(isGenerating: true, messages: [message]),
          current: _fields(
            isGenerating: false,
            isPostGenRunning: true,
            messages: [message],
          ),
          oldMessages: [message],
          newMessages: [message],
          streamingId: '__streaming__',
          onSyncExtBlockPanels: () async {},
          appendMessage: (_) async {},
          buildStreamingPlaceholder: () => _assistant('__streaming__'),
        );

        expect(bridge.isGenerating, isFalse);
        expect(bridge.isPostGenRunning, isTrue);
        expect(bridge.updatedMessages, [message]);
        expect(bridge.updatedIsLast, [true]);
        expect(bridge.lastMessageIds, ['a1']);
        expect(bridge.evalCalls.single, contains('setGenerating(false)'));
        expect(bridge.evalCalls.single, contains('setPostGenRunning(true)'));
      },
    );

    test('refreshes last assistant controls when post-gen settles', () {
      final bridge = _FakeBridge()..isPostGenRunning = true;
      final message = _assistant('a1');
      final dispatcher = ChatWebViewSyncDispatcher(
        state: ChatWebViewSyncState(),
      );

      dispatcher.dispatch(
        bridge: bridge,
        old: _fields(
          isGenerating: false,
          isPostGenRunning: true,
          messages: [message],
        ),
        current: _fields(isGenerating: false, messages: [message]),
        oldMessages: [message],
        newMessages: [message],
        streamingId: '__streaming__',
        onSyncExtBlockPanels: () async {},
        appendMessage: (_) async {},
        buildStreamingPlaceholder: () => _assistant('__streaming__'),
      );

      expect(bridge.isPostGenRunning, isFalse);
      expect(bridge.updatedMessages, [message]);
      expect(bridge.updatedIsLast, [true]);
      expect(bridge.lastMessageIds, ['a1']);
      expect(bridge.evalCalls.single, contains('setPostGenRunning(false)'));
    });

    test(
      'does not flag a non-trailing assistant as last when a user message '
      'trails after a cancelled generation',
      () {
        // Reproduces the cancel+regen stuck-Regenerate-button bug: after Stop
        // trims the empty assistant placeholder, the trailing message is the
        // user turn. The falling edge must NOT stamp data-is-last on the
        // earlier char bubble (greeting), otherwise two sections carry the flag
        // and setLastMessage (single querySelector) can never clear the
        // user-message Regenerate button on the next generation.
        final bridge = _FakeBridge()..isGenerating = true;
        final greeting = _assistant('greeting');
        final user = _user('u1');
        final dispatcher = ChatWebViewSyncDispatcher(
          state: ChatWebViewSyncState()..wasGenerating = true,
        );

        dispatcher.dispatch(
          bridge: bridge,
          old: _fields(isGenerating: true, messages: [greeting, user]),
          current: _fields(isGenerating: false, messages: [greeting, user]),
          oldMessages: [greeting, user],
          newMessages: [greeting, user],
          streamingId: '__streaming__',
          onSyncExtBlockPanels: () async {},
          appendMessage: (_) async {},
          buildStreamingPlaceholder: () => _assistant('__streaming__'),
        );

        // The trailing message is the user turn → the last assistant bubble is
        // not last and must be refreshed with isLast=false.
        expect(bridge.updatedMessages, [greeting]);
        expect(bridge.updatedIsLast, [false]);
        // setLastMessage targets the trailing user message (which injects and
        // owns the sole data-is-last / Regenerate button).
        expect(bridge.lastMessageIds, ['u1']);
        expect(bridge.evalCalls.single, contains('setGenerating(false)'));
      },
    );

    test('syncs overlay blur regions only when they change', () {
      final dispatcher = ChatWebViewSyncDispatcher(
        state: ChatWebViewSyncState(),
      );
      final bridge = _FakeBridge();
      List<ChatOverlayBlurRegion> regions() => [
        ChatOverlayBlurRegion(
          id: 'header',
          rect: const Rect.fromLTWH(16, 40, 300, 56),
          radius: 20,
        ),
      ];
      void dispatch(
        ChatWebViewWidgetFields old,
        ChatWebViewWidgetFields current,
      ) {
        dispatcher.dispatch(
          bridge: bridge,
          old: old,
          current: current,
          oldMessages: const [],
          newMessages: const [],
          streamingId: '__streaming__',
          onSyncExtBlockPanels: () async {},
          appendMessage: (_) async {},
          buildStreamingPlaceholder: () => _assistant('__streaming__'),
        );
      }

      // Equal-but-not-identical lists must NOT re-send.
      dispatch(
        _fields(isGenerating: false, messages: [], blurRegions: regions()),
        _fields(isGenerating: false, messages: [], blurRegions: regions()),
      );
      expect(bridge.overlayBlurCalls, isEmpty);

      // A moved region re-sends exactly once.
      final moved = [
        ChatOverlayBlurRegion(
          id: 'header',
          rect: const Rect.fromLTWH(16, 40, 300, 72),
          radius: 20,
        ),
      ];
      dispatch(
        _fields(isGenerating: false, messages: [], blurRegions: regions()),
        _fields(isGenerating: false, messages: [], blurRegions: moved),
      );
      expect(bridge.overlayBlurCalls, hasLength(1));
      expect(bridge.overlayBlurCalls.single, moved);
    });
  });
}

ChatMessage _assistant(String id) =>
    ChatMessage(id: id, role: 'assistant', content: 'assistant', timestamp: 1);

ChatMessage _user(String id) =>
    ChatMessage(id: id, role: 'user', content: 'user', timestamp: 1);

ChatWebViewWidgetFields _fields({
  required bool isGenerating,
  required List<ChatMessage> messages,
  bool isPostGenRunning = false,
  List<ChatOverlayBlurRegion> blurRegions = const [],
}) => ChatWebViewWidgetFields(
  blurRegions: blurRegions,
  charId: 'c1',
  charName: 'Character',
  charColor: null,
  personaName: null,
  charAvatarPath: null,
  personaAvatarPath: null,
  bgImagePath: null,
  bgBlur: 0,
  bgOpacity: 1,
  bgDim: 0,
  bgNoiseOpacity: 0,
  bgNoiseIntensity: 0,
  bottomInset: 0,
  topInset: 0,
  searchQuery: null,
  searchCurrentIndex: -1,
  chatLayout: 'default',
  themeSyncKey: 'theme',
  elementOpacity: 1,
  elementBlur: 0,
  uiFontWeight: 400,
  userMessageFontWeight: 400,
  charMessageFontWeight: 400,
  userBubbleRadius: 18,
  charBubbleRadius: 18,
  showUserAvatar: true,
  showCharAvatar: true,
  showUserName: true,
  showCharName: true,
  chatFontName: null,
  chatFontDataUrl: null,
  chatFontSize: 16,
  chatLetterSpacing: 0,
  isSelectionMode: false,
  batterySaver: false,
  hideMessageId: false,
  hideGenerationTime: false,
  hideTokenCount: false,
  disableSwipeRegeneration: false,
  studioEnabled: false,
  memoryEntries: const [],
  memoryDrafts: const [],
  sessionId: 's1',
  isGenerating: isGenerating,
  isGeneratingImage: false,
  isPostGenRunning: isPostGenRunning,
  regenTargetId: null,
  greetingTotal: 0,
  messages: messages,
  buildThemeMap: () => const {},
);

class _FakeBridge implements ChatBridgeController {
  @override
  bool isGenerating = false;

  @override
  bool isGeneratingImage = false;

  @override
  bool isPostGenRunning = false;

  final List<List<ChatOverlayBlurRegion>> overlayBlurCalls = [];
  final List<String> evalCalls = [];
  final List<ChatMessage> updatedMessages = [];
  final List<bool> updatedIsLast = [];
  final List<String?> lastMessageIds = [];

  @override
  Future<void> setOverlayBlurRegions(
    List<ChatOverlayBlurRegion> regions,
  ) async {
    overlayBlurCalls.add(regions);
  }

  @override
  Future<void> evalJs(String source) async {
    evalCalls.add(source);
  }

  @override
  Future<void> removeMessage(String _) async {}

  @override
  Future<void> updateMessage(
    ChatMessage message, {
    bool isStreamingUpdate = false,
    bool isLast = false,
  }) async {
    updatedMessages.add(message);
    updatedIsLast.add(isLast);
  }

  @override
  Future<void> setLastMessage(String? messageId) async {
    lastMessageIds.add(messageId);
  }

  @override
  Future<void> setIdentity({
    String? charName,
    String? charColor,
    String? personaName,
    String? layout,
    String? charAvatarPath,
    String? personaAvatarPath,
    int? greetingTotal,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
