import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/llm/tokenizer.dart';
import '../../core/models/chat_message.dart';
import '../../core/utils/time_helpers.dart';
import '../../core/state/db_provider.dart';

class ChatMessageService {
  final Ref _ref;

  ChatMessageService(this._ref);

  ChatSession editMessage(
    ChatSession session,
    int index,
    String newContent, {
    String? tagStart,
    String? tagEnd,
  }) {
    if (index < 0 || index >= session.messages.length) return session;
    final msg = session.messages[index];

    var text = newContent;
    String? newReasoning = msg.reasoning;
    bool isAllReasoning = msg.isAllReasoning;

    if (tagStart != null && tagEnd != null && text.contains(tagStart)) {
      final startIdx = text.indexOf(tagStart);
      final endIdx = text.indexOf(tagEnd, startIdx + tagStart.length);
      if (endIdx != -1) {
        newReasoning = text.substring(startIdx + tagStart.length, endIdx).trim();
        text = (text.substring(0, startIdx) + text.substring(endIdx + tagEnd.length)).trim();
        isAllReasoning = text.isEmpty && newReasoning.isNotEmpty;
      }
    }

    if (msg.content == text && msg.reasoning == newReasoning) return session;
    final newMessages = List<ChatMessage>.from(session.messages);
    final swipeIdx = msg.swipeId;
    final updatedSwipes = msg.swipes.isNotEmpty && swipeIdx >= 0 && swipeIdx < msg.swipes.length
        ? (List<String>.from(msg.swipes)..[swipeIdx] = text)
        : msg.swipes;
    final updatedSwipesMeta = List<Map<String, dynamic>>.from(msg.swipesMeta);
    if (swipeIdx >= 0 && swipeIdx < updatedSwipesMeta.length) {
      updatedSwipesMeta[swipeIdx] = {...updatedSwipesMeta[swipeIdx], 'reasoning': newReasoning};
    }
    newMessages[index] = msg.copyWith(
      content: text,
      reasoning: newReasoning,
      isAllReasoning: isAllReasoning,
      swipes: updatedSwipes,
      swipesMeta: updatedSwipesMeta,
    );
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

  ChatSession setGreeting(
    ChatSession session,
    int messageIndex,
    int newGreetingIndex,
    List<String> resolvedGreetings,
  ) {
    if (messageIndex < 0 || messageIndex >= session.messages.length) return session;
    if (resolvedGreetings.length <= 1) return session;
    var idx = newGreetingIndex;
    if (idx < 0) idx = resolvedGreetings.length - 1;
    if (idx >= resolvedGreetings.length) idx = 0;

    final msg = session.messages[messageIndex];
    final newText = resolvedGreetings[idx];
    final updated = msg.copyWith(
      greetingIndex: idx,
      content: newText,
      swipes: [newText],
      swipeId: 0,
      swipesMeta: const [],
      reasoning: null,
      isError: false,
      tokens: estimateTokens(newText),
      genTime: null,
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
