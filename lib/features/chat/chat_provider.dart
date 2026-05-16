import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/chat_message.dart';
import '../../core/services/generation_notification_service.dart';
import '../../core/utils/id_generator.dart';
import '../../core/utils/time_helpers.dart';
import '../../core/state/db_provider.dart';
import '../cloud_sync/sync_provider.dart';
import '../chat_history/chat_history_provider.dart';
import 'chat_generation_service.dart';
import 'chat_message_service.dart';
import 'chat_session_service.dart';
import 'chat_state.dart';
import 'initial_message_builder.dart';

final chatProvider =
    AsyncNotifierProvider.family<ChatNotifier, ChatState, String>(
      ChatNotifier.new,
    );

final streamingStateProvider =
    StateProvider.family<StreamingState, String>(
      (ref, _) => const StreamingState(),
    );

class ChatNotifier extends FamilyAsyncNotifier<ChatState, String> {
  CancelToken? _cancelToken;
  ChatMessage? _restorationMessage;
  int _activeGenId = 0;
  Completer<void>? _activeGenCompleter;

  void setCancelToken(CancelToken token) => _cancelToken = token;

  ChatSessionService get _sessionSvc => ChatSessionService(ref);
  ChatMessageService get _messageSvc => ChatMessageService(ref);

  @override
  Future<ChatState> build(String arg) async {
    final existing = await _sessionSvc.findExistingSession(arg);
    if (existing != null) return ChatState(session: existing);
    final session = await _sessionSvc.createInitialSession(arg);
    return ChatState(session: session);
  }

  Future<void> sendMessage(String text, {String? guidanceText}) async {
    final current = state.value;
    if (current == null || current.isGenerating) return;

    final userMsg = ChatMessage(
      id: generateId(),
      role: 'user',
      content: text,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    final updatedMessages = [...current.messages, userMsg];
    final updatedSession = current.session!.copyWith(
      messages: updatedMessages,
      updatedAt: currentTimestampSeconds(),
    );

    await ref.read(chatRepoProvider).put(updatedSession);
    _invalidateHistory();
    state = AsyncData(ChatState(session: updatedSession, isGenerating: true, generationStartTime: DateTime.now()));

    final charRepo = ref.read(characterRepoProvider);
    final character = await charRepo.getById(arg);
    if (character != null) {
      final talkativeness = character.extensions['talkativeness'];
      if (talkativeness is num && talkativeness < 1.0) {
        final roll = DateTime.now().microsecond % 100 / 100.0;
        if (roll > talkativeness) {
          _clearStreaming();
          state = AsyncData(ChatState(session: updatedSession));
          return;
        }
      }
    }

    await _runGeneration(updatedSession, current, guidanceText: guidanceText);
  }

  Future<void> regenerateLastAssistant({String? guidanceText}) async {
    if (_activeGenCompleter != null && !_activeGenCompleter!.isCompleted) {
      await _abortAndWait();
    }
    final current = state.value;
    if (current == null || current.session == null || current.isGenerating) return;

    final lastIdx = current.messages.length - 1;
    if (lastIdx < 0) return;

    final lastMsg = current.messages[lastIdx];
    ChatMessage? prevAssistant;
    List<ChatMessage> baseMessages;

    debugPrint('[regen] lastMsg.role=${lastMsg.role} isError=${lastMsg.isError} '
        'swipes=${lastMsg.swipes.length} swipeId=${lastMsg.swipeId} '
        'totalMessages=${current.messages.length}');

    if (lastMsg.role == 'assistant') {
      prevAssistant = lastMsg;
      baseMessages = current.messages.sublist(0, lastIdx);
    } else {
      baseMessages = List<ChatMessage>.from(current.messages);
    }

    final trimmedSession = current.session!.copyWith(
      messages: baseMessages,
      updatedAt: currentTimestampSeconds(),
    );
    await ref.read(chatRepoProvider).put(trimmedSession);
    _invalidateHistory();
    state = AsyncData(ChatState(session: trimmedSession, isGenerating: true, generationStartTime: DateTime.now()));
    _restorationMessage = prevAssistant;

    await _runGeneration(
      trimmedSession, current,
      guidanceText: guidanceText,
      previousSwipes: prevAssistant != null
          ? (prevAssistant.swipes.isNotEmpty ? prevAssistant.swipes : [prevAssistant.content])
          : null,
      previousSwipeId: prevAssistant?.swipeId ?? 0,
      previousReasoning: prevAssistant?.reasoning,
      previousGenTime: prevAssistant?.genTime,
      previousTokens: prevAssistant?.tokens,
      previousSwipesMeta: prevAssistant?.swipesMeta.isNotEmpty == true
          ? prevAssistant!.swipesMeta
          : null,
    );
  }

  Future<void> continueMessage() async {
    final current = state.value;
    if (current == null || current.session == null || current.isGenerating) return;

    final lastIdx = current.messages.length - 1;
    if (lastIdx < 0) return;
    final lastMsg = current.messages[lastIdx];
    if (lastMsg.role != 'assistant') return;

    final genId = ++_activeGenId;
    state = AsyncData(ChatState(session: current.session, isGenerating: true, generationStartTime: DateTime.now()));

    final notifService = GenerationNotificationService.instance;
    await notifService.onGenerationStarted();

    final service = ChatGenerationService(ref);
    final result = await service.generate(
      session: current.session!,
      charId: arg,
      currentState: current,
      onStateUpdate: (s) { if (_activeGenId == genId) state = AsyncData(s); },
      isAborted: () => _activeGenId != genId,
    );

    if (_activeGenId != genId) return;

    final generatedMsg = result.messages.isNotEmpty ? result.messages.last : null;
    if (generatedMsg != null && generatedMsg.role == 'assistant') {
      final appendedContent = '${lastMsg.content}${generatedMsg.content}';
      final appendedMsg = generatedMsg.copyWith(content: appendedContent);
      final updatedMessages = [...result.messages.sublist(0, result.messages.length - 1), appendedMsg];
      final finalSession = result.session!.copyWith(
        messages: updatedMessages,
        updatedAt: currentTimestampSeconds(),
      );
      await ref.read(chatRepoProvider).put(finalSession);
      _invalidateHistory();
      state = AsyncData(ChatState(session: finalSession));
    } else {
      state = AsyncData(result);
    }

    final charRepo = ref.read(characterRepoProvider);
    final character = await charRepo.getById(arg);
    await notifService.onGenerationCompleted(character?.name ?? 'Unknown', arg);
  }

  Future<void> clearChat() async {
    final current = state.value;
    if (current == null || current.session == null) return;
    final cleared = await _sessionSvc.clearChat(arg, current.session!);
    _invalidateHistory();
    state = AsyncData(ChatState(session: cleared));
  }

  Future<void> editMessage(int index, String newContent) async {
    final current = state.value;
    if (current == null || current.session == null) return;
    final updated = _messageSvc.editMessage(current.session!, index, newContent);
    _invalidateHistory();
    state = AsyncData(ChatState(session: updated));
  }

  Future<void> moveMessage(int fromIndex, int toIndex) async {
    final current = state.value;
    if (current == null || current.session == null) return;
    final updated = _messageSvc.moveMessage(current.session!, fromIndex, toIndex);
    _invalidateHistory();
    state = AsyncData(ChatState(session: updated));
  }

  Future<void> deleteMessage(int index) async {
    final current = state.value;
    if (current == null || current.session == null) return;
    final updated = _messageSvc.deleteMessage(current.session!, index);
    _invalidateHistory();
    state = AsyncData(ChatState(session: updated));
  }

  Future<void> toggleMessageHidden(int index) async {
    final current = state.value;
    if (current == null || current.session == null) return;
    final updated = _messageSvc.toggleMessageHidden(current.session!, index);
    _invalidateHistory();
    state = AsyncData(ChatState(session: updated));
  }

  Future<void> unhideAllMessages() async {
    final current = state.value;
    if (current == null || current.session == null) return;
    final updated = _messageSvc.unhideAllMessages(current.session!);
    _invalidateHistory();
    state = AsyncData(ChatState(session: updated));
  }

  Future<void> hideTopMessages(int count) async {
    final current = state.value;
    if (current == null || current.session == null) return;
    final updated = _messageSvc.hideTopMessages(current.session!, count);
    _invalidateHistory();
    state = AsyncData(ChatState(session: updated));
  }

  void setSwipe(int messageIndex, int swipeId) {
    final current = state.value;
    if (current == null || current.session == null) return;
    final updated = _messageSvc.setSwipe(current.session!, messageIndex, swipeId);
    _invalidateHistory();
    state = AsyncData(ChatState(session: updated));
  }

  Future<void> setGreeting(int messageIndex, int direction) async {
    final current = state.value;
    if (current == null || current.session == null || current.isGenerating) return;
    if (messageIndex != 0) return;
    if (messageIndex >= current.messages.length) return;
    final msg = current.messages[messageIndex];
    if (msg.role != 'assistant') return;

    final character = await ref.read(characterRepoProvider).getById(arg);
    if (character == null) return;
    final persona = await _sessionSvc.resolvePersona(arg);
    final greetings = InitialMessageBuilder.resolveGreetings(
      character: character,
      persona: persona,
      sessionId: current.session!.id,
    );
    if (greetings.length <= 1) return;

    final currentIdx = msg.greetingIndex ?? 0;
    final updated = _messageSvc.setGreeting(
      current.session!,
      messageIndex,
      currentIdx + direction,
      greetings,
    );
    _invalidateHistory();
    state = AsyncData(ChatState(session: updated));
  }

  Future<void> switchSession(int sessionIndex) async {
    _activeGenId++;
    _restorationMessage = null;
    _clearStreaming();
    final session = await _sessionSvc.switchToSession(arg, sessionIndex);
    if (session != null) {
      state = AsyncData(ChatState(session: session));
    }
  }

  Future<void> createNewSession() async {
    _activeGenId++;
    _restorationMessage = null;
    _clearStreaming();
    final session = await _sessionSvc.createNewSession(arg);
    _invalidateHistory();
    state = AsyncData(ChatState(session: session));
  }

  Future<List<ChatSession>> getSessions() => _sessionSvc.getSessions(arg);

  Future<void> branchSession(int index) async {
    final current = state.value;
    if (current == null || current.session == null) return;
    if (index < 0 || index >= current.messages.length) return;
    _activeGenId++;
    _restorationMessage = null;
    _clearStreaming();
    final session = await _sessionSvc.branchSession(arg, current.session!, index);
    _invalidateHistory();
    state = AsyncData(ChatState(session: session));
  }

  Future<void> newSession() async {
    _activeGenId++;
    _restorationMessage = null;
    _clearStreaming();
    final session = await _sessionSvc.createNewSession(arg);
    _invalidateHistory();
    state = AsyncData(ChatState(session: session));
  }

  void abortGeneration() {
    _activeGenId++; // invalidate any in-flight onStateUpdate / final writes
    _cancelToken?.cancel();
    _cancelToken = null;
    _clearStreaming();

    // Immediately clear isGenerating and restore the previous assistant message
    // if we aborted a regeneration mid-flight.  The genId guard blocks any
    // in-flight onError/onComplete from writing isGenerating: false on their own.
    final current = state.value;
    if (current != null && current.isGenerating) {
      final restoration = _restorationMessage;
      if (restoration != null) {
        final restoredMessages = <ChatMessage>[...(current.session?.messages ?? const <ChatMessage>[]), restoration];
        final restoredSession = current.session?.copyWith(
          messages: restoredMessages,
          updatedAt: currentTimestampSeconds(),
        );
        if (restoredSession != null) {
          ref.read(chatRepoProvider).put(restoredSession);
        }
        state = AsyncData(ChatState(
          session: restoredSession ?? current.session,
          isGenerating: false,
        ));
      } else {
        state = AsyncData(ChatState(session: current.session, isGenerating: false));
      }
    }
    _restorationMessage = null;

    GenerationNotificationService.instance.onGenerationAborted();
  }

  /// Aborts any active generation and waits for the SSE stream to fully close
  /// before returning. This prevents the race condition where a new generation
  /// starts before the old stream's onError/onComplete callbacks have fired.
  Future<void> _abortAndWait() async {
    final completer = _activeGenCompleter;
    if (completer == null || completer.isCompleted) return;
    abortGeneration();
    await completer.future;
  }

  void _invalidateHistory() => ref.invalidate(chatHistoryProvider);

  void _clearStreaming() {
    ref.read(streamingStateProvider(arg).notifier).state = const StreamingState();
  }

  Future<void> _runGeneration(
    ChatSession session,
    ChatState current, {
    String? guidanceText,
    List<String>? previousSwipes,
    int previousSwipeId = 0,
    String? previousReasoning,
    String? previousGenTime,
    int? previousTokens,
    List<Map<String, dynamic>>? previousSwipesMeta,
  }) async {
    final genId = ++_activeGenId;
    final completer = Completer<void>();
    _activeGenCompleter = completer;
    _clearStreaming();

    final notifService = GenerationNotificationService.instance;
    await notifService.onGenerationStarted();

    final service = ChatGenerationService(ref);
    final result = await service.generate(
      session: session,
      charId: arg,
      currentState: current,
      onStateUpdate: (s) { if (_activeGenId == genId) state = AsyncData(s); },
      isAborted: () => _activeGenId != genId,
      previousSwipes: previousSwipes,
      previousSwipeId: previousSwipeId,
      previousReasoning: previousReasoning,
      previousGenTime: previousGenTime,
      previousTokens: previousTokens,
      previousSwipesMeta: previousSwipesMeta,
      guidanceText: guidanceText,
    );

    // A newer generation started while we were awaiting — discard this result.
    if (_activeGenId != genId) {
      if (!completer.isCompleted) completer.complete();
      return;
    }

    if (result.session?.messages.length == session.messages.length) {
      // No new message was saved (cancelled or failed)
      if (_restorationMessage != null) {
        final restoredMessages = [...session.messages, _restorationMessage!];
        final restoredSession = session.copyWith(
          messages: restoredMessages,
          updatedAt: currentTimestampSeconds(),
        );
        await ref.read(chatRepoProvider).put(restoredSession);
        _invalidateHistory();
        state = AsyncData(ChatState(
          session: restoredSession,
          isGenerating: false,
          error: result.error,
        ));
      } else {
        state = AsyncData(result);
      }
    } else {
      state = AsyncData(result);
    }
    _restorationMessage = null;
    _clearStreaming();

    await service.processImageTags(
      currentState: result,
      charId: arg,
      onStateUpdate: (s) { if (_activeGenId == genId) state = AsyncData(s); },
    );

    if (_activeGenId != genId) {
      if (!completer.isCompleted) completer.complete();
      return;
    }

    notifySyncMessageGenerated(ref);

    final charRepo = ref.read(characterRepoProvider);
    final character = await charRepo.getById(arg);
    await notifService.onGenerationCompleted(character?.name ?? 'Unknown', arg);

    if (!completer.isCompleted) completer.complete();
  }
}
