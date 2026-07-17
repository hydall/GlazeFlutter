import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/llm/tokenizer.dart';
import '../../core/models/chat_message.dart';
import '../../core/utils/time_helpers.dart';
import '../../core/state/db_provider.dart';
import '../../shared/widgets/glaze_toast.dart';
import 'chat_session_service.dart';

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

    if (tagStart != null && tagEnd != null) {
      if (text.contains(tagStart)) {
        final startIdx = text.indexOf(tagStart);
        final endIdx = text.indexOf(tagEnd, startIdx + tagStart.length);
        if (endIdx != -1) {
          newReasoning = text
              .substring(startIdx + tagStart.length, endIdx)
              .trim();
          text =
              (text.substring(0, startIdx) +
                      text.substring(endIdx + tagEnd.length))
                  .trim();
          if (newReasoning.isEmpty) newReasoning = null;
        } else {
          newReasoning = text.substring(startIdx + tagStart.length).trim();
          text = '';
        }
        isAllReasoning =
            text.isEmpty && (newReasoning != null && newReasoning.isNotEmpty);
      } else {
        newReasoning = null;
        isAllReasoning = false;
      }
    }

    if (msg.content == text && msg.reasoning == newReasoning) return session;
    final newMessages = List<ChatMessage>.from(session.messages);
    final swipeIdx = msg.swipeId;
    final updatedSwipes =
        msg.swipes.isNotEmpty && swipeIdx >= 0 && swipeIdx < msg.swipes.length
        ? (List<String>.from(msg.swipes)..[swipeIdx] = text)
        : msg.swipes;
    final updatedSwipesMeta = List<Map<String, dynamic>>.from(msg.swipesMeta);
    if (swipeIdx >= 0 && swipeIdx < updatedSwipesMeta.length) {
      updatedSwipesMeta[swipeIdx] = {
        ...updatedSwipesMeta[swipeIdx],
        'reasoning': newReasoning,
      };
    }
    newMessages[index] = msg.copyWith(
      content: text,
      reasoning: newReasoning,
      isAllReasoning: isAllReasoning,
      swipes: updatedSwipes,
      swipesMeta: updatedSwipesMeta,
      tokens: estimateTokens(text),
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

  Future<ChatSession> deleteMessage(ChatSession session, int index) {
    return deleteMessages(session, {index});
  }

  /// Deletes multiple messages with one session write and one cleanup pass.
  Future<ChatSession> deleteMessages(
    ChatSession session,
    Set<int> indices,
  ) async {
    final validIndices = indices
        .where((index) => index >= 0 && index < session.messages.length)
        .toSet();
    if (validIndices.isEmpty) return session;

    final messageIds = validIndices
        .map((index) => session.messages[index].id)
        .where((id) => id.isNotEmpty)
        .toSet();
    final newMessages = <ChatMessage>[
      for (var i = 0; i < session.messages.length; i++)
        if (!validIndices.contains(i)) session.messages[i],
    ];

    final snapshotRepo = _ref.read(trackerSnapshotRepoProvider);
    final trackerRepo = _ref.read(trackerRepoProvider);
    final memoryBookRepo = _ref.read(memoryBookRepoProvider);

    await Future.wait([
      memoryBookRepo.deleteForMessages(session.id, messageIds),
      _ref
          .read(characterKnowledgeFactRepoProvider)
          .retractForMessages(session.id, messageIds),
      snapshotRepo.deleteForMessages(session.id, messageIds),
    ]).catchError((Object e) {
      debugPrint('[ChatMessageService] failed to clean deleted messages: $e');
      return <void>[];
    });

    try {
      final snapshot = await snapshotRepo.getLatestCommitted(session.id);
      if (snapshot == null) {
        await trackerRepo.clearForSession(session.id);
      } else {
        await trackerRepo.replaceForSession(session.id, snapshot.trackers);
      }
    } catch (e) {
      debugPrint('[ChatMessageService] failed to roll back trackers: $e');
    }

    // Current chunk indices no longer map to the same message ranges. Drop the
    // session index now; post-generation indexing will rebuild current chunks.
    try {
      await _ref
          .read(embeddingRepoProvider)
          .deleteBySource('chat_message', session.id);
    } catch (e) {
      debugPrint('[ChatMessageService] failed to clear message index: $e');
    }

    return _persistAndWait(session, newMessages);
  }

  ChatSession toggleMessageHidden(ChatSession session, int index) {
    if (index < 0 || index >= session.messages.length) return session;
    final newMessages = List<ChatMessage>.from(session.messages);
    newMessages[index] = newMessages[index].copyWith(
      isHidden: !newMessages[index].isHidden,
    );
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
    if (messageIndex < 0 || messageIndex >= session.messages.length) {
      return session;
    }
    final msg = session.messages[messageIndex];
    if (msg.swipes.isEmpty || swipeId < 0 || swipeId >= msg.swipes.length) {
      return session;
    }

    final meta = swipeId < msg.swipesMeta.length
        ? msg.swipesMeta[swipeId]
        : null;

    final swipesMeta = List<Map<String, dynamic>>.from(msg.swipesMeta);
    // Ensure swipesMeta is long enough.
    while (swipesMeta.length < msg.swipes.length) {
      swipesMeta.add(<String, dynamic>{});
    }
    // Nested swipes: persist current agentSwipes into the outgoing green
    // swipe's meta, then load (or seed) agentSwipes for the incoming swipe.
    // Save outgoing agentSwipes.
    if (msg.agentSwipes.isNotEmpty && msg.swipeId < swipesMeta.length) {
      swipesMeta[msg.swipeId] = {
        ...swipesMeta[msg.swipeId],
        'agentSwipes': msg.agentSwipes.map((e) => e.toJson()).toList(),
        'agentSwipeId': msg.agentSwipeId,
      };
    }
    // Load incoming agentSwipes.
    List<AgentSwipe> nextAgentSwipes;
    int nextAgentSwipeId;
    final storedAgentSwipes = _agentSwipesFromMeta(meta);
    if (storedAgentSwipes != null && storedAgentSwipes.isNotEmpty) {
      nextAgentSwipes = storedAgentSwipes;
      nextAgentSwipeId = (meta?['agentSwipeId'] as int?) ?? 0;
    } else {
      // Seed a single 'final' from the green swipe content.
      nextAgentSwipes = [
        AgentSwipe(
          content: msg.swipes[swipeId],
          kind: 'final',
          reasoning: meta?['reasoning'] as String?,
          genTime: meta?['genTime'] as String?,
          tokens: meta?['tokens'] as int?,
          studioOutputs: _studioOutputsFromMeta(meta),
        ),
      ];
      nextAgentSwipeId = 0;
    }

    // The active content is the active blue swipe (if any), else the green.
    final activeContent = nextAgentSwipes.isNotEmpty
        ? nextAgentSwipes[nextAgentSwipeId.clamp(0, nextAgentSwipes.length - 1)]
              .content
        : msg.swipes[swipeId];

    final updated = msg.copyWith(
      swipeId: swipeId,
      content: activeContent,
      // Error state is tracked per-swipe (swipesMeta[i]['isError']) so the
      // error styling follows the active variation only. Navigating to a
      // healthy swipe clears the error window; navigating back restores it.
      isError: meta?['isError'] == true,
      reasoning: nextAgentSwipes.isNotEmpty
          ? nextAgentSwipes[nextAgentSwipeId.clamp(
                  0,
                  nextAgentSwipes.length - 1,
                )]
                .reasoning
          : meta?['reasoning'] as String?,
      genTime: nextAgentSwipes.isNotEmpty
          ? nextAgentSwipes[nextAgentSwipeId.clamp(
                  0,
                  nextAgentSwipes.length - 1,
                )]
                .genTime
          : meta?['genTime'] as String?,
      tokens: nextAgentSwipes.isNotEmpty
          ? nextAgentSwipes[nextAgentSwipeId.clamp(
                  0,
                  nextAgentSwipes.length - 1,
                )]
                .tokens
          : meta?['tokens'] as int?,
      triggeredLorebooks: _triggeredFromMeta(meta, 'triggeredLorebooks'),
      triggeredMemories: _triggeredFromMeta(meta, 'triggeredMemories'),
      studioOutputs: nextAgentSwipes.isNotEmpty
          ? nextAgentSwipes[nextAgentSwipeId.clamp(
                  0,
                  nextAgentSwipes.length - 1,
                )]
                .studioOutputs
          : _studioOutputsFromMeta(meta),
      swipesMeta: swipesMeta,
      agentSwipes: nextAgentSwipes,
      agentSwipeId: nextAgentSwipeId,
    );
    final newMessages = List<ChatMessage>.from(session.messages);
    newMessages[messageIndex] = updated;
    return _persist(session, newMessages);
  }

  /// Parse agentSwipes stored in [swipesMeta] meta. Returns null if absent.
  static List<AgentSwipe>? _agentSwipesFromMeta(Map<String, dynamic>? meta) {
    final raw = meta?['agentSwipes'];
    if (raw is! List) return null;
    final swipes = raw
        .whereType<Map<dynamic, dynamic>>()
        .map((m) => AgentSwipe.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    // Lazy migration: older 'cleaned' swipes were saved with empty
    // studioOutputs (before appendAgentSwipe started inheriting them from
    // the parent 'final'). Backfill so that switching to a cleaned blue
    // swipe keeps the Studio regen button visible.
    for (var i = 0; i < swipes.length; i++) {
      if (swipes[i].kind == 'cleaned' &&
          swipes[i].studioOutputs.isEmpty &&
          swipes[i].parentSwipeId != null &&
          swipes[i].parentSwipeId! < swipes.length) {
        final parent = swipes[swipes[i].parentSwipeId!];
        if (parent.studioOutputs.isNotEmpty) {
          swipes[i] = swipes[i].copyWith(studioOutputs: parent.studioOutputs);
        }
      }
    }
    return swipes;
  }

  /// Set the active blue sub-swipe (agentSwipeId) for a message without
  /// changing the green swipe. The message content/reasoning/tokens are
  /// restored from the selected AgentSwipe.
  ChatSession setAgentSwipe(
    ChatSession session,
    int messageIndex,
    int agentSwipeId,
  ) {
    if (messageIndex < 0 || messageIndex >= session.messages.length) {
      return session;
    }
    final msg = session.messages[messageIndex];
    if (msg.agentSwipes.isEmpty ||
        agentSwipeId < 0 ||
        agentSwipeId >= msg.agentSwipes.length) {
      return session;
    }
    final swipe = msg.agentSwipes[agentSwipeId];
    final swipesMeta = _syncAgentSwipesToMeta(
      msg.swipesMeta,
      msg.swipeId,
      msg.agentSwipes,
      agentSwipeId,
    );
    final updated = msg.copyWith(
      agentSwipeId: agentSwipeId,
      content: swipe.content,
      reasoning: swipe.reasoning,
      genTime: swipe.genTime,
      tokens: swipe.tokens,
      studioOutputs: swipe.studioOutputs,
      swipesMeta: swipesMeta,
    );
    final newMessages = List<ChatMessage>.from(session.messages);
    newMessages[messageIndex] = updated;
    return _persist(session, newMessages);
  }

  /// Sync agentSwipes + agentSwipeId into swipesMeta[swipeId].
  static List<Map<String, dynamic>> _syncAgentSwipesToMeta(
    List<Map<String, dynamic>> swipesMeta,
    int swipeId,
    List<AgentSwipe> agentSwipes,
    int agentSwipeId,
  ) {
    if (swipeId < 0 || agentSwipes.isEmpty) return swipesMeta;
    final meta = List<Map<String, dynamic>>.from(swipesMeta);
    while (meta.length <= swipeId) {
      meta.add(<String, dynamic>{});
    }
    meta[swipeId] = {
      ...meta[swipeId],
      'agentSwipes': agentSwipes.map((e) => e.toJson()).toList(),
      'agentSwipeId': agentSwipeId,
    };
    return meta;
  }

  /// Parse the per-swipe triggered entries stored in [swipesMeta]. Each
  /// variation persists its own lorebook/memory activations so the chat UI
  /// (native sheet + webview) shows them per swipe instead of leaking the
  /// last-generated swipe's entries onto every variation.
  static List<TriggeredEntry> _triggeredFromMeta(
    Map<String, dynamic>? meta,
    String key,
  ) {
    final raw = meta?[key];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<dynamic, dynamic>>()
        .map((m) => TriggeredEntry.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  static List<Map<String, dynamic>> _studioOutputsFromMeta(
    Map<String, dynamic>? meta,
  ) {
    final raw = meta?['studioOutputs'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<dynamic, dynamic>>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  /// Mirrors Glaze/src/composables/chat/useSwipeNavigation.js → `changeSwipe`.
  /// `dir`: +1 forward, -1 back. `fromSwipe`: animation hint (slide vs fade).
  /// Returns a [ChangeSwipeResult] describing whether the session was updated,
  /// whether the caller should regenerate a new variant, and whether nothing
  /// happened (out of bounds / single swipe / generating).
  ChangeSwipeResult changeSwipe(
    ChatSession session,
    int messageIndex,
    int dir, {
    bool fromSwipe = false,
    bool isLastMessage = false,
  }) {
    if (messageIndex < 0 || messageIndex >= session.messages.length) {
      return const ChangeSwipeResult.noop();
    }
    final msg = session.messages[messageIndex];
    final animDir = fromSwipe
        ? (dir > 0 ? 'slide-next' : 'slide-prev')
        : 'fade';

    if (msg.swipes.length <= 1) return const ChangeSwipeResult.noop();

    final newIndex = msg.swipeId + dir;

    // Right-edge on the last message → caller should kick off a new variant.
    if (dir > 0 && newIndex >= msg.swipes.length && isLastMessage) {
      return const ChangeSwipeResult.needsRegen();
    }
    if (newIndex < 0 || newIndex >= msg.swipes.length) {
      return const ChangeSwipeResult.noop();
    }

    // Delegate to setSwipe for the heavy lifting (agentSwipes save/load,
    // content/reasoning/meta restoration + per-swipe isError). Then patch
    // swipeDirection for the slide animation. Error variants are kept as
    // navigable swipes; the error styling is derived per-swipe in setSwipe.
    final swapped = setSwipe(session, messageIndex, newIndex);
    final swappedMsg = swapped.messages[messageIndex];
    final patched = swappedMsg.copyWith(swipeDirection: animDir);
    final patchedMessages = List<ChatMessage>.from(swapped.messages)
      ..[messageIndex] = patched;
    return ChangeSwipeResult.updated(_persist(session, patchedMessages));
  }

  /// Change the active blue sub-swipe (agentSwipeId) by [dir].
  ///
  /// Mirrors the green-swipe navigation but operates on `agentSwipes[]`.
  /// Right-edge on the last message → [ChangeSwipeResult.needsRegen] so the
  /// caller can kick off a full regeneration (new green swipe).
  ChangeSwipeResult changeAgentSwipe(
    ChatSession session,
    int messageIndex,
    int dir, {
    bool fromSwipe = false,
    bool isLastMessage = false,
  }) {
    if (messageIndex < 0 || messageIndex >= session.messages.length) {
      return const ChangeSwipeResult.noop();
    }
    final msg = session.messages[messageIndex];
    if (msg.agentSwipes.length <= 1) return const ChangeSwipeResult.noop();

    final animDir = fromSwipe
        ? (dir > 0 ? 'slide-next' : 'slide-prev')
        : 'fade';

    var newIndex = msg.agentSwipeId + dir;

    // Wrap-around: index < 0 → last; index >= length → 0.
    if (newIndex < 0) {
      newIndex = msg.agentSwipes.length - 1;
    } else if (newIndex >= msg.agentSwipes.length) {
      // Right-edge on the last message → full regen (new green swipe).
      if (isLastMessage) {
        return const ChangeSwipeResult.needsRegen();
      }
      newIndex = 0;
    }

    final swipe = msg.agentSwipes[newIndex];
    final swipesMeta = _syncAgentSwipesToMeta(
      msg.swipesMeta,
      msg.swipeId,
      msg.agentSwipes,
      newIndex,
    );
    final updated = msg.copyWith(
      agentSwipeId: newIndex,
      content: swipe.content,
      reasoning: swipe.reasoning,
      genTime: swipe.genTime,
      tokens: swipe.tokens,
      studioOutputs: swipe.studioOutputs,
      swipeDirection: animDir,
      swipesMeta: swipesMeta,
    );
    final newMessages = List<ChatMessage>.from(session.messages)
      ..[messageIndex] = updated;
    return ChangeSwipeResult.updated(_persist(session, newMessages));
  }

  ChatSession setGreeting(
    ChatSession session,
    int messageIndex,
    int newGreetingIndex,
    List<String> resolvedGreetings,
  ) {
    if (messageIndex < 0 || messageIndex >= session.messages.length) {
      return session;
    }
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
      studioOutputs: const [],
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
    if (!_ref.mounted) return updated;
    _ref.read(chatRepoProvider).put(updated).catchError((Object e) {
      debugPrint('[ChatMessageService] failed to persist session: $e');
      GlazeToast.showWithoutContext(
        'Failed to save changes: $e',
        isError: true,
        duration: 5000,
      );
    });
    ChatSessionService.updateCache(updated);
    return updated;
  }

  Future<ChatSession> _persistAndWait(
    ChatSession session,
    List<ChatMessage> newMessages,
  ) async {
    final updated = session.copyWith(
      messages: newMessages,
      updatedAt: currentTimestampSeconds(),
    );
    if (!_ref.mounted) return updated;
    try {
      await _ref.read(chatRepoProvider).put(updated);
    } catch (e) {
      debugPrint('[ChatMessageService] failed to persist session: $e');
      GlazeToast.showWithoutContext(
        'Failed to save changes: $e',
        isError: true,
        duration: 5000,
      );
    }
    ChatSessionService.updateCache(updated);
    return updated;
  }
}

/// Result of [ChatMessageService.changeSwipe].
/// - `updated`: session was modified, use [session].
/// - `needsRegen`: caller should kick off a new variant via regenerate.
/// - `noop`: nothing happened (out of bounds / single swipe / etc).
class ChangeSwipeResult {
  final ChatSession? session;
  final bool needsRegen;

  const ChangeSwipeResult._(this.session, this.needsRegen);
  const ChangeSwipeResult.updated(ChatSession s) : this._(s, false);
  const ChangeSwipeResult.needsRegen() : this._(null, true);
  const ChangeSwipeResult.noop() : this._(null, false);

  bool get isUpdated => session != null;
  bool get isNoop => session == null && !needsRegen;
}
