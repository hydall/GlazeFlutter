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
import '../image_gen/image_gen_provider.dart';
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
  bool _buildComplete = false;

  @override
  Future<ChatState> build(String arg) async {
    ref.keepAlive();
    _buildComplete = false;
    final existing = await _sessionSvc.findExistingSession(arg);
    if (_buildComplete) {
      return state.value ?? ChatState(session: existing);
    }
    if (existing != null) {
      final start = existing.messages.length > ChatState.initialPageSize
          ? existing.messages.length - ChatState.initialPageSize
          : 0;
      final result = ChatState(session: existing, visibleStartIndex: start);
      _buildComplete = true;
      return result;
    }
    final session = await _sessionSvc.createInitialSession(arg);
    _buildComplete = true;
    return ChatState(session: session);
  }

  void loadOlderMessages() {
    final current = state.value;
    if (current == null || !current.hasMoreOlder || current.isLoadingOlder) return;

    final newStart = current.visibleStartIndex > ChatState.olderPageSize
        ? current.visibleStartIndex - ChatState.olderPageSize
        : 0;
    state = AsyncData(current.copyWith(
      visibleStartIndex: newStart,
      isLoadingOlder: true,
    ));
    Future.delayed(const Duration(milliseconds: 500), () {
      final s = state.value;
      if (s != null) {
        state = AsyncData(s.copyWith(isLoadingOlder: false));
      }
    });
  }

  CancelToken? _cancelToken;
  CancelToken? _imgGenCancelToken;
  ChatMessage? _restorationMessage;
  int _activeGenId = 0;
  Completer<void>? _activeGenCompleter;

  void setCancelToken(CancelToken token) => _cancelToken = token;

  bool get isGeneratingImage => _imgGenCancelToken != null && !(_imgGenCancelToken!.isCancelled);

  void abortImageGeneration() {
    _imgGenCancelToken?.cancel();
    _imgGenCancelToken = null;
  }

  Future<void> retryImageGeneration() async {
    if (isGeneratingImage) return;
    final current = state.value;
    if (current == null || current.session == null) return;

    final session = current.session!;
    final lastIdx = session.messages.length - 1;
    if (lastIdx < 0) return;
    final lastMsg = session.messages[lastIdx];
    if (lastMsg.role != 'assistant') return;

    final notifier = ref.read(imageGenSettingsProvider.notifier);
    final service = await notifier.getServiceAsync();

    final hasRetryableContent = service.hasImageGenTags(lastMsg.content)
        || lastMsg.content.contains('[IMG:ERROR:')
        || lastMsg.content.contains('[IMG:RESULT:');
    if (!hasRetryableContent) return;

    final resetContent = service.resetErrorTags(lastMsg.content);
    if (resetContent == lastMsg.content && !service.hasImageGenTags(resetContent)) return;

    final newMessages = List<ChatMessage>.from(session.messages);
    newMessages[lastIdx] = lastMsg.copyWith(content: resetContent);
    final resetSession = session.copyWith(
      messages: newMessages,
      updatedAt: currentTimestampSeconds(),
    );
    state = AsyncData(ChatState(session: resetSession, isGeneratingImage: true));

    final imgCancelToken = CancelToken();
    _imgGenCancelToken = imgCancelToken;

    final genService = ChatGenerationService(ref);
    await genService.processImageTags(
      currentState: state.value!,
      charId: arg,
      cancelToken: imgCancelToken,
      onStateUpdate: (s) { state = AsyncData(s); },
    );

    _imgGenCancelToken = null;
  }

  ChatSessionService get _sessionSvc => ChatSessionService(ref);
  ChatMessageService get _messageSvc => ChatMessageService(ref);

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
      draft: '',
      updatedAt: currentTimestampSeconds(),
    );

    await ref.read(chatRepoProvider).put(updatedSession);
    ChatSessionService.updateCache(updatedSession);
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

    debugPrint('[regen] lastMsg.role=${lastMsg.role} isError=${lastMsg.isError} '
        'swipes=${lastMsg.swipes.length} swipeId=${lastMsg.swipeId} '
        'totalMessages=${current.messages.length}');

    if (lastMsg.role == 'assistant') {
      prevAssistant = lastMsg;
    }

    if (prevAssistant == null) return;

    final regenTargetId = prevAssistant.id;
    _restorationMessage = prevAssistant;

    state = AsyncData(ChatState(
      session: current.session,
      isGenerating: true,
      generationStartTime: DateTime.now(),
      regenTargetId: regenTargetId,
    ));

    await _runGeneration(
      current.session!, current,
      guidanceText: guidanceText,
      regenTargetId: regenTargetId,
      previousSwipes: prevAssistant.swipes.isNotEmpty
          ? prevAssistant.swipes
          : [prevAssistant.content],
      previousSwipeId: prevAssistant.swipeId,
      previousReasoning: prevAssistant.reasoning,
      previousGenTime: prevAssistant.genTime,
      previousTokens: prevAssistant.tokens,
      previousSwipesMeta: prevAssistant.swipesMeta.isNotEmpty
          ? prevAssistant.swipesMeta
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
    final charRepo = ref.read(characterRepoProvider);
    final character = await charRepo.getById(arg);
    await notifService.onGenerationStarted(character?.name ?? 'Unknown');

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
      ChatSessionService.updateCache(finalSession);
      _invalidateHistory();
      state = AsyncData(ChatState(session: finalSession));
    } else {
      state = AsyncData(result);
    }

    final preview = _messagePreview(result.messages);
    await notifService.onGenerationCompleted(
      character?.name ?? 'Unknown', arg,
      messagePreview: preview,
    );
  }

  Future<void> clearChat() async {
    final current = state.value;
    if (current == null || current.session == null) return;
    final cleared = await _sessionSvc.clearChat(arg, current.session!);
    _invalidateHistory();
    state = AsyncData(ChatState(session: cleared));
  }

  Future<void> editMessage(int index, String newContent, {String? tagStart, String? tagEnd}) async {
    final current = state.value;
    if (current == null || current.session == null) return;
    final updated = _messageSvc.editMessage(current.session!, index, newContent, tagStart: tagStart, tagEnd: tagEnd);
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

  Future<void> saveDraft(String draftText) async {
    final current = state.value;
    if (current == null || current.session == null) return;
    if (current.session!.draft == draftText) return;
    
    final updatedSession = current.session!.copyWith(draft: draftText);
    await ref.read(chatRepoProvider).put(updatedSession);
    ChatSessionService.updateCache(updatedSession);
    state = AsyncData(ChatState(
      session: updatedSession,
      isGenerating: current.isGenerating,
      generationStartTime: current.generationStartTime,
      error: current.error,
    ));
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
    try {
      final session = await _sessionSvc.switchToSession(arg, sessionIndex);
      _buildComplete = true;
      final start = session.messages.length > ChatState.initialPageSize
          ? session.messages.length - ChatState.initialPageSize
          : 0;
      state = AsyncData(ChatState(session: session, visibleStartIndex: start));
    } catch (_) {
      final current = state.value;
      if (current != null) {
        state = AsyncData(current);
      }
    }
  }

  Future<void> createNewSession() async {
    _activeGenId++;
    _restorationMessage = null;
    _clearStreaming();
    final session = await _sessionSvc.createNewSession(arg);
    _buildComplete = true;
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
    final start = session.messages.length > ChatState.initialPageSize
        ? session.messages.length - ChatState.initialPageSize
        : 0;
    state = AsyncData(ChatState(session: session, visibleStartIndex: start));
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
    _activeGenId++;
    _cancelToken?.cancel();
    _cancelToken = null;
    _imgGenCancelToken?.cancel();
    _imgGenCancelToken = null;
    _clearStreaming();

    final current = state.value;
    if (current != null && current.isGenerating) {
      final restoration = _restorationMessage;
      final regenId = current.regenTargetId;

      if (regenId != null && restoration != null) {
        final idx = current.messages.indexWhere((m) => m.id == regenId);
        if (idx >= 0) {
          final restored = current.messages[idx].copyWith(
            content: restoration.content,
            swipeId: restoration.swipeId,
            swipes: restoration.swipes,
            reasoning: restoration.reasoning,
            genTime: restoration.genTime,
            tokens: restoration.tokens,
            swipesMeta: restoration.swipesMeta,
            swipeDirection: restoration.swipeDirection,
          );
          final restoredMessages = [...current.messages];
          restoredMessages[idx] = restored;
          final restoredSession = current.session?.copyWith(
            messages: restoredMessages,
            updatedAt: currentTimestampSeconds(),
          );
          if (restoredSession != null) {
            ref.read(chatRepoProvider).put(restoredSession);
            ChatSessionService.updateCache(restoredSession);
          }
          state = AsyncData(ChatState(
            session: restoredSession ?? current.session,
            isGenerating: false,
            isGeneratingImage: false,
          ));
        } else {
          state = AsyncData(ChatState(
            session: current.session,
            isGenerating: false,
            isGeneratingImage: false,
            regenTargetId: null,
          ));
        }
      } else if (restoration != null) {
        final restoredMessages = <ChatMessage>[...(current.session?.messages ?? const <ChatMessage>[]), restoration];
        final restoredSession = current.session?.copyWith(
          messages: restoredMessages,
          updatedAt: currentTimestampSeconds(),
        );
        if (restoredSession != null) {
          ref.read(chatRepoProvider).put(restoredSession);
          ChatSessionService.updateCache(restoredSession);
        }
        state = AsyncData(ChatState(
          session: restoredSession ?? current.session,
          isGenerating: false,
          isGeneratingImage: false,
        ));
      } else {
        state = AsyncData(ChatState(session: current.session, isGenerating: false, isGeneratingImage: false));
      }
    } else if (current != null && current.isGeneratingImage) {
      state = AsyncData(ChatState(session: current.session, isGeneratingImage: false));
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
    String? regenTargetId,
  }) async {
    final genId = ++_activeGenId;
    final completer = Completer<void>();
    _activeGenCompleter = completer;
    _clearStreaming();

    final notifService = GenerationNotificationService.instance;
    final charRepo = ref.read(characterRepoProvider);
    final character = await charRepo.getById(arg);
    await notifService.onGenerationStarted(character?.name ?? 'Unknown');

    try {
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
      regenTargetId: regenTargetId,
    );

    // A newer generation started while we were awaiting — discard this result.
    if (_activeGenId != genId) {
      if (!completer.isCompleted) completer.complete();
      return;
    }

    if (regenTargetId != null) {
      if (result.regenTargetId == regenTargetId) {
        final finalState = result.copyWith(isGenerating: false, regenTargetId: null);
        state = AsyncData(finalState);
      } else {
        final idx = session.messages.indexWhere((m) => m.id == regenTargetId);
        if (idx >= 0 && _restorationMessage != null) {
          final restored = session.messages[idx].copyWith(
            content: _restorationMessage!.content,
            swipeId: _restorationMessage!.swipeId,
            swipes: _restorationMessage!.swipes,
            reasoning: _restorationMessage!.reasoning,
            genTime: _restorationMessage!.genTime,
            tokens: _restorationMessage!.tokens,
            swipesMeta: _restorationMessage!.swipesMeta,
            swipeDirection: _restorationMessage!.swipeDirection,
          );
          final restoredMessages = [...session.messages];
          restoredMessages[idx] = restored;
          final restoredSession = session.copyWith(
            messages: restoredMessages,
            updatedAt: currentTimestampSeconds(),
          );
          await ref.read(chatRepoProvider).put(restoredSession);
          ChatSessionService.updateCache(restoredSession);
          _invalidateHistory();
          state = AsyncData(ChatState(
            session: restoredSession,
            isGenerating: false,
            error: result.error,
          ));
        } else {
          state = AsyncData(result.copyWith(isGenerating: false, regenTargetId: null));
        }
      }
    } else if (result.session?.messages.length == session.messages.length) {
      // No new message was saved (cancelled or failed)
      if (_restorationMessage != null) {
        final restoredMessages = [...session.messages, _restorationMessage!];
        final restoredSession = session.copyWith(
          messages: restoredMessages,
          updatedAt: currentTimestampSeconds(),
        );
        await ref.read(chatRepoProvider).put(restoredSession);
        ChatSessionService.updateCache(restoredSession);
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

    final imgCancelToken = CancelToken();
    _imgGenCancelToken = imgCancelToken;

    await service.processImageTags(
      currentState: result,
      charId: arg,
      cancelToken: imgCancelToken,
      onStateUpdate: (s) { if (_activeGenId == genId) state = AsyncData(s); },
    );

    _imgGenCancelToken = null;

    if (_activeGenId != genId) {
      if (!completer.isCompleted) completer.complete();
      return;
    }

    notifySyncMessageGenerated(ref);

    final preview = _messagePreview(result.session?.messages ?? []);
    await notifService.onGenerationCompleted(
      character?.name ?? 'Unknown', arg,
      messagePreview: preview,
    );

    if (!completer.isCompleted) completer.complete();
    } catch (e) {
      if (_activeGenId == genId) {
        final current = state.value;
        if (current != null && current.isGenerating) {
          final restoration = _restorationMessage;
          if (restoration != null) {
            final msgs = <ChatMessage>[...(current.session?.messages ?? []), restoration];
            final restored = current.session?.copyWith(messages: msgs, updatedAt: currentTimestampSeconds());
            if (restored != null) {
              ref.read(chatRepoProvider).put(restored);
              ChatSessionService.updateCache(restored);
            }
            state = AsyncData(ChatState(session: restored ?? current.session, isGenerating: false, error: e.toString()));
          } else {
            state = AsyncData(ChatState(session: current.session, isGenerating: false, error: e.toString()));
          }
          _restorationMessage = null;
        }
      }
      if (!completer.isCompleted) completer.complete();
    }
  }

  String? _messagePreview(List messages) {
    try {
      for (final m in messages.reversed) {
        final content = (m as dynamic).content as String?;
        if (content != null && content.isNotEmpty) {
          final text = content
              .replaceAll(RegExp(r'\*\*[^*]+\*\*'), '')
              .replaceAll(RegExp(r'\*[^*]+\*'), '')
              .replaceAll(RegExp(r'==[^=]+=='), '')
              .replaceAll(RegExp(r'<[^>]+>'), '')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
          if (text.isNotEmpty) {
            return text.length > 80 ? '${text.substring(0, 80)}...' : text;
          }
        }
      }
    } catch (_) {}
    return null;
  }
}
