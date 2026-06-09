import 'package:collection/collection.dart';

import '../../../core/models/chat_message.dart';
import '../bridge/chat_bridge_controller.dart';

/// Pure diff between the previous and current [ChatMessage] list and
/// the dispatch of the right [ChatBridgeController] method.
///
/// Extracted from `chat_webview_widget._syncMessages` so the widget
/// can stay focused on the build / lifecycle delegation. The sync
/// contract is preserved exactly:
///   * No-op when a session switch is in progress (defer to caller).
///   * First load (old empty) → `setMessages`.
///   * Cleared (new empty) → `clearAll`.
///   * Head prepend → `prependMessages` for the prefix.
///   * Tail append (skipping the streaming placeholder) → `appendMessages`.
///   * Head truncation → `removeMessage` per removed id.
///   * Tail truncation → `removeMessage` for trimmed ids.
///   * Same length with at least one swap → `clearAll` + `setMessages`.
///   * Same length, per-index change → `updateMessage` if the
///     content / swipe / hidden / typing / error / guidance / greeting
///     fields differ.
class ChatMessageSync {
  const ChatMessageSync();

  /// Apply the diff between [oldMsgs] and [newMsgs] using the given
  /// [bridge]. [streamingSkipLast] is set when the last message is a
  /// streaming placeholder that should be excluded from the tail append
  /// (the bridge keeps it in place from the previous frame).
  /// [visibleStartIndex] is forwarded to `setMessages` / `prependMessages`
  /// for the scrollback window.
  /// [isGenerating] controls whether `setLastMessage` is called after
  /// a tail append (only when generation has settled).
  /// [sessionSwitching] short-circuits the diff entirely so a session
  /// switch can complete its full reset.
  void sync({
    required ChatBridgeController? bridge,
    required List<ChatMessage> oldMsgs,
    required List<ChatMessage> newMsgs,
    required int visibleStartIndex,
    required bool streamingSkipLast,
    required bool isGenerating,
    required bool sessionSwitching,
  }) {
    if (sessionSwitching) return;
    if (bridge == null) return;

    final oldIds = oldMsgs.map((m) => m.id).toList();
    final newIds = newMsgs.map((m) => m.id).toList();
    final newLen = newIds.length - (streamingSkipLast ? 1 : 0);

    if (oldIds.isEmpty) {
      bridge.setMessages(newMsgs, visibleStartIndex: visibleStartIndex);
      if (!isGenerating) {
        bridge.setLastMessage(_lastUserId(newMsgs));
      }
      return;
    }

    if (newIds.isEmpty) {
      bridge.clearAll();
      return;
    }

    if (newIds.length > oldIds.length) {
      final oldFirstId = oldIds.first;
      final newIdx = newIds.indexOf(oldFirstId);
      if (newIdx > 0) {
        bridge.prependMessages(
          newMsgs.sublist(0, newIdx),
          visibleStartIndex: visibleStartIndex,
        );
        return;
      }
      if (newLen > oldIds.length) {
        final appends = newMsgs.sublist(oldIds.length, newLen);
        bridge.appendMessages(
          appends,
          startIndex: visibleStartIndex + oldIds.length,
        );
        if (appends.isNotEmpty && !isGenerating) {
          bridge.setLastMessage(
            _lastUserId(appends) ?? newMsgs.lastOrNull?.id,
          );
        }
        return;
      }
    }

    if (newIds.length < oldIds.length) {
      final newFirstId = newIds.first;
      final oldIdx = oldIds.indexOf(newFirstId);
      if (oldIdx > 0) {
        for (int i = 0; i < oldIdx; i++) {
          bridge.removeMessage(oldIds[i]);
        }
        return;
      }
      final newLastId = newIds.last;
      final oldLastIdx = oldIds.indexOf(newLastId);
      if (oldLastIdx >= 0 && newIds.length == oldLastIdx + 1) {
        for (int i = oldIds.length - 1; i > oldLastIdx; i--) {
          bridge.removeMessage(oldIds[i]);
        }
        if (!isGenerating) {
          bridge.setLastMessage(_lastUserId(newMsgs));
        }
        return;
      }
      bridge.clearAll();
      bridge.setMessages(newMsgs, visibleStartIndex: visibleStartIndex);
      if (!isGenerating) {
        bridge.setLastMessage(_lastUserId(newMsgs));
      }
      return;
    }

    final minLen = newLen < oldIds.length ? newLen : oldIds.length;
    var anyUpdated = false;
    for (int i = 0; i < minLen; i++) {
      if (i >= newIds.length) break;
      if (newIds[i] != oldIds[i]) {
        bridge.clearAll();
        bridge.setMessages(newMsgs, visibleStartIndex: visibleStartIndex);
        if (!isGenerating) {
          bridge.setLastMessage(_lastUserId(newMsgs));
        }
        return;
      }
      final o = oldMsgs[i];
      final n = newMsgs[i];

      final contentChanged = o.content != n.content;
      final swipeChanged = o.swipeId != n.swipeId;
      final swipeTotalChanged = o.swipes.length != n.swipes.length;
      final hiddenChanged = o.isHidden != n.isHidden;
      final typingChanged = o.isTyping != n.isTyping;
      final errorChanged = o.isError != n.isError;
      final guidanceChanged = o.guidanceText != n.guidanceText;
      final greetingChanged = o.greetingIndex != n.greetingIndex;

      final needsUpdate =
          contentChanged ||
          swipeChanged ||
          hiddenChanged ||
          swipeTotalChanged ||
          typingChanged ||
          errorChanged ||
          guidanceChanged ||
          greetingChanged;

      if (needsUpdate) {
        bridge.updateMessage(n);
        anyUpdated = true;
      }
    }
    // Same-length per-index edits (e.g. user editMessage while the
    // last message is still a user message) need a fresh setLastMessage
    // because the WebView footer/regen controls are not re-rendered by
    // `updateMessage`. The previous dispatcher call relied on a
    // changing isGenerating flag, which does not move on edit.
    if (anyUpdated && !isGenerating) {
      bridge.setLastMessage(_lastUserId(newMsgs));
    }
  }
}

/// Returns the id of the last user-authored message in [msgs] (or
/// null if the list contains no user messages). The WebView needs
/// this id to inject the Regenerate button under the last user
/// message — the renderer only sets `data-is-last` for char messages.
String? _lastUserId(List<ChatMessage> msgs) {
  for (int i = msgs.length - 1; i >= 0; i--) {
    if (msgs[i].role == 'user') return msgs[i].id;
  }
  return null;
}

/// Returns `true` when both [a] and [b] contain the same object
/// references in the same order. Used by [ChatWebViewWidget] to
/// detect no-op parent rebuilds so the message sync is not even
/// invoked.
bool chatMessageListsIdentical(List<ChatMessage> a, List<ChatMessage> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (!identical(a[i], b[i])) return false;
  }
  return true;
}
