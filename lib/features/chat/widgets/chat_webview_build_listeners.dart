import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/chat_message.dart';
import '../../../core/models/preset.dart';
import '../../../core/state/active_regex_provider.dart';
import '../../../core/state/character_provider.dart';
import '../../../core/state/persona_resolution.dart';
import '../../extensions/models/info_block.dart';
import '../../extensions/providers/extension_presets_provider.dart';
import '../../extensions/providers/extensions_settings_provider.dart';
import '../../extensions/providers/info_blocks_provider.dart';
import '../bridge/chat_bridge_controller.dart';
import '../chat_provider.dart';
import '../chat_state.dart';
import '../editing_message_provider.dart';
import 'chat_message_sync.dart';
import 'chat_webview_sync_dispatcher.dart';

/// Wires the `build()`-side `ref.listen` plumbing for the chat
/// WebView: display regexes, editing message, streaming state,
/// ext-block DB rows, and the ext-settings / ext-presets broadcasts.
///
/// Extracted from `chat_webview_widget.dart` so the widget's build
/// method only calls [attach] once per frame. The class does not
/// own any state — it forwards the [ref.listen] callbacks to the
/// existing bridge / refresher / sync state.
class ChatWebViewBuildListeners {
  ChatWebViewBuildListeners({
    required this.ref,
    required this.bridge,
    required this.ready,
    required this.syncState,
    required this.streamingId,
    required this.charId,
    required this.sessionId,
    required this.messages,
    required this.regenTargetId,
    required this.visibleStartIndex,
    required this.onRefreshExtBlocksPanel,
    required this.onSyncExtBlockPanels,
  });

  final WidgetRef ref;
  final ChatBridgeController? bridge;
  final bool Function() ready;
  final ChatWebViewSyncState syncState;
  final String streamingId;
  final String charId;
  final String? sessionId;
  final List<ChatMessage> messages;
  final String? regenTargetId;
  final int visibleStartIndex;
  final Future<void> Function(String sessionId, String messageId)
  onRefreshExtBlocksPanel;
  final Future<void> Function() onSyncExtBlockPanels;

  /// Attach all `ref.listen` callbacks for the current build. Call
  /// from the top of `State.build` after the `ref.watch` reads.
  void attach() {
    _listenDisplayRegexes();
    _listenEditingMessage();
    _listenStreaming();
    _listenInfoBlocks();
    _listenExtSettingsAndPresets();
  }

  void _listenDisplayRegexes() {
    ref.listen<AsyncValue<List<PresetRegex>>>(displayRegexesProvider, (
      prev,
      next,
    ) {
      final b = bridge;
      if (b == null || !ready()) return;
      final oldList = prev?.value ?? const <PresetRegex>[];
      final newList = next.value ?? const <PresetRegex>[];
      if (_regexListChanged(oldList, newList)) {
        final character = ref.read(characterByIdProvider(charId));
        final effectivePersona = ref.read(
          effectivePersonaForChatProvider((
            charId: charId,
            sessionId: sessionId,
          )),
        );
        b.setRegexContext(newList, character, effectivePersona);
        b.setMessages(messages, visibleStartIndex: visibleStartIndex);
      }
    });
  }

  void _listenEditingMessage() {
    ref.listen<String?>(editingMessageIdProvider(charId), (prev, next) {
      final b = bridge;
      if (b == null || !ready()) return;
      if (prev != null && prev != next) {
        // Await stopEdit before re-injecting Regenerate. The old path
        // also called updateMessage() without awaiting stopEdit; that
        // raced in the JS update batcher, cleared footer controls while
        // `editing` was still set, and left the last-user Regenerate
        // missing on save/cancel. Message content sync runs separately
        // when editMessage updates the provider.
        unawaited(() async {
          await b.stopEdit(prev);
          final lastUserId = lastUserMessageId(messages);
          if (lastUserId != null && lastUserId == prev) {
            await b.setLastMessage(lastUserId);
          }
        }());
      }
      if (next != null) {
        b.startEdit(next);
      }
    });
  }

  void _listenStreaming() {
    ref.listen<StreamingState>(streamingStateProvider(charId), (prev, next) {
      final b = bridge;
      if (b == null || !ready()) return;
      if (next.text.isEmpty && next.reasoning == null) return;

      final regenId = regenTargetId;
      if (regenId != null) {
        final idx = messages.indexWhere((m) => m.id == regenId);
        if (idx >= 0) {
          final original = messages[idx];
          final updated = original.copyWith(
            content: next.text,
            reasoning: next.reasoning ?? original.reasoning,
            isTyping: true,
          );
          b.updateMessage(updated);
          syncState.regenStreamingSent = true;
        }
        return;
      }

      final msg = ChatMessage(
        id: streamingId,
        role: 'assistant',
        content: next.text,
        reasoning: next.reasoning,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        isTyping: true,
      );

      if (!syncState.streamingSent) {
        b.appendMessage(msg);
        syncState.streamingSent = true;
      } else {
        b.updateMessage(msg);
      }
    });
  }

  void _listenInfoBlocks() {
    final sid = sessionId;
    if (sid == null || sid.isEmpty) return;
    ref.listen<List<InfoBlock>>(infoBlocksProvider(sid), (prev, next) {
      if (bridge == null || !ready()) return;
      final allIds = <String>{
        for (final b in prev ?? const <InfoBlock>[]) b.messageId,
        for (final b in next) b.messageId,
        for (final m in messages)
          if (m.role == 'assistant' || m.role == 'character') m.id,
      };
      for (final msgId in allIds) {
        unawaited(onRefreshExtBlocksPanel(sid, msgId));
      }
    });
  }

  void _listenExtSettingsAndPresets() {
    ref.listen(extensionsSettingsProvider, (_, _) {
      if (bridge != null && ready()) {
        unawaited(onSyncExtBlockPanels());
      }
    });
    ref.listen(extensionPresetsProvider, (_, _) {
      if (bridge != null && ready()) {
        unawaited(onSyncExtBlockPanels());
      }
    });
  }

  static bool _regexListChanged(List<PresetRegex> a, List<PresetRegex> b) {
    if (a.length != b.length) return true;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].disabled != b[i].disabled) return true;
    }
    return false;
  }
}
