import 'package:flutter_test/flutter_test.dart';

import 'package:glaze_flutter/core/models/chat_message.dart';
import 'package:glaze_flutter/features/chat/bridge/chat_bridge_controller.dart';
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
  });
}

ChatMessage _assistant(String id) =>
    ChatMessage(id: id, role: 'assistant', content: 'assistant', timestamp: 1);

ChatMessage _user(String id) =>
    ChatMessage(id: id, role: 'user', content: 'user', timestamp: 1);

ChatWebViewWidgetFields _fields({
  required bool isGenerating,
  required List<ChatMessage> messages,
}) => ChatWebViewWidgetFields(
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
  memoryEntries: const [],
  memoryDrafts: const [],
  sessionId: 's1',
  isGenerating: isGenerating,
  isGeneratingImage: false,
  isPostGenRunning: false,
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
  Future<void> evalJs(String _) async {}

  @override
  Future<void> setLastMessage(String? _) async {}

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
