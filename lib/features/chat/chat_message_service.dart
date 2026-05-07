import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/chat_message.dart';
import '../../core/utils/time_helpers.dart';
import '../../core/state/db_provider.dart';

class ChatMessageService {
  final Ref _ref;

  ChatMessageService(this._ref);

  ChatSession editMessage(ChatSession session, int index, String newContent) {
    if (index < 0 || index >= session.messages.length) return session;
    final newMessages = List<ChatMessage>.from(session.messages);
    newMessages[index] = session.messages[index].content != newContent
        ? session.messages[index].copyWith(content: newContent)
        : session.messages[index];
    return _persist(session, newMessages);
  }

  ChatSession moveMessage(ChatSession session, int fromIndex, int toIndex) {
    final msgs = session.messages;
    if (fromIndex < 0 || fromIndex >= msgs.length) return session;
    if (toIndex < 0 || toIndex >= msgs.length) return session;
    if (fromIndex == toIndex) return session;
    final newMessages = List<ChatMessage>.from(msgs);
    final moved = newMessages.removeAt(fromIndex);
    newMessages.insert(toIndex, moved);
    return _persist(session, newMessages);
  }

  ChatSession deleteMessage(ChatSession session, int index) {
    if (index < 0 || index >= session.messages.length) return session;
    final newMessages = List<ChatMessage>.from(session.messages)..removeAt(index);
    return _persist(session, newMessages);
  }

  ChatSession toggleMessageHidden(ChatSession session, int index) {
    if (index < 0 || index >= session.messages.length) return session;
    final newMessages = List<ChatMessage>.from(session.messages);
    newMessages[index] = newMessages[index].copyWith(isHidden: !newMessages[index].isHidden);
    return _persist(session, newMessages);
  }

  ChatSession unhideAllMessages(ChatSession session) {
    bool changed = false;
    final newMessages = session.messages.map((m) {
      if (m.isHidden) {
        changed = true;
        return m.copyWith(isHidden: false);
      }
      return m;
    }).toList();
    if (!changed) return session;
    return _persist(session, newMessages);
  }

  ChatSession hideTopMessages(ChatSession session, int count) {
    final visibleIndices = <int>[];
    for (int i = 0; i < session.messages.length; i++) {
      if (!session.messages[i].isHidden) visibleIndices.add(i);
    }
    final toHide = visibleIndices.take(count).toList();
    if (toHide.isEmpty) return session;
    final newMessages = List<ChatMessage>.from(session.messages);
    for (final idx in toHide) {
      newMessages[idx] = newMessages[idx].copyWith(isHidden: true);
    }
    return _persist(session, newMessages);
  }

  ChatSession setSwipe(ChatSession session, int messageIndex, int swipeId) {
    if (messageIndex < 0 || messageIndex >= session.messages.length) return session;
    final msg = session.messages[messageIndex];
    if (msg.swipes.isEmpty || swipeId < 0 || swipeId >= msg.swipes.length) return session;

    final meta = swipeId < msg.swipesMeta.length ? msg.swipesMeta[swipeId] : null;
    final updated = msg.copyWith(
      swipeId: swipeId,
      content: msg.swipes[swipeId],
      reasoning: meta?['reasoning'] as String?,
      genTime: meta?['genTime'] as String?,
      tokens: meta?['tokens'] as int?,
    );
    final newMessages = List<ChatMessage>.from(session.messages);
    newMessages[messageIndex] = updated;
    return _persist(session, newMessages);
  }

  ChatSession _persist(ChatSession session, List<ChatMessage> newMessages) {
    final updated = session.copyWith(
      messages: newMessages,
      updatedAt: currentTimestampSeconds(),
    );
    _ref.read(chatRepoProvider).put(updated);
    return updated;
  }
}
