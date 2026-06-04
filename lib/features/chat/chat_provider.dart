import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/llm/tokenizer.dart';
import '../../core/models/chat_message.dart';
import '../../core/services/generation_notification_service.dart';
import '../../core/utils/id_generator.dart';
import '../../core/utils/time_helpers.dart';
import '../../core/state/db_provider.dart';
import '../chat_history/chat_history_provider.dart';
import 'abort_handler.dart';
import 'chat_generation_service.dart';
import 'chat_session_service.dart';
import 'chat_state.dart';
import 'image_recovery_service.dart';
import 'controllers/chat_message_ops_controller.dart';
import 'controllers/chat_swipe_controller.dart';
import 'controllers/chat_session_controller.dart';
import 'controllers/chat_draft_controller.dart';
import 'services/generation_pipeline.dart';
import 'utils/message_preview.dart';

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

  void _persistSession(ChatSession session) {
    ref.read(chatRepoProvider).put(session).catchError((Object e) {
      debugPrint('[ChatNotifier] failed to persist session: $e');
    });
  }

  @override
  Future<ChatState> build(String arg) async {
    ref.keepAlive();
    _buildComplete = false;
    final existing = await _sessionSvc.findExistingSession(arg);
    if (_buildComplete) {
      return state.value ?? ChatState(session: existing);
    }
    if (existing != null) {
      final fixed = _fixupSwipesWithImageResults(existing);
      if (!identical(fixed, existing)) {
        await ref.read(chatRepoProvider).put(fixed);
      }
      final start = fixed.messages.length > ChatState.initialPageSize
          ? fixed.messages.length - ChatState.initialPageSize
          : 0;
      final result = ChatState(session: fixed, visibleStartIndex: start);
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
      isLoadingOlder: false,
    ));
  }

  late final AbortHandler _abortHandler = AbortHandler(
    ref: ref,
    charId: arg,
    setState: (s) { state = s; },
    getState: () => state,
    persistSession: _persistSession,
  );

  void setCancelToken(CancelToken token, {required int genId}) =>
      _abortHandler.setCancelToken(token, genId: genId);

  bool get isGeneratingImage => _abortHandler.isGeneratingImage;

  ChatSession _fixupSwipesWithImageResults(ChatSession session) =>
      ImageRecoveryService.fixupSwipesWithImageResults(session);

  void abortImageGeneration() => _abortHandler.abortImageGeneration();
  void abortGeneration() => _abortHandler.abortGeneration();
  void cancelImageGeneration() => _abortHandler.cancelImageGeneration();
  Future<void> retryImageGeneration() async =>
      _imageRecoverySvc.retryImageGeneration();
  Future<void> findImageOnDisk(String messageId, String instruction) async =>
      _imageRecoverySvc.findImageOnDisk(messageId, instruction);
  Future<void> retryImageGenerationForMessage(int messageIndex) async =>
      _imageRecoverySvc.retryImageGenerationForMessage(messageIndex);

  ChatSessionService get _sessionSvc => ChatSessionService(ref);
  ImageRecoveryService get _imageRecoverySvc => ImageRecoveryService(
    ref: ref,
    charId: arg,
    setImgGenCancelToken: (t) { _abortHandler.imgGenCancelToken = t; },
    setState: (s) { state = s; },
    getState: () => state,
  );

  // Controllers
  late final _messageOpsCtrl = ChatMessageOpsController(
    ref: ref,
    charId: arg,
    setState: (s) { state = s; },
    getState: () => state,
    invalidateHistory: _invalidateHistory,
  );

  late final _swipeCtrl = ChatSwipeController(
    ref: ref,
    charId: arg,
    setState: (s) { state = s; },
    getState: () => state,
    invalidateHistory: _invalidateHistory,
  );

  late final _sessionCtrl = ChatSessionController(
    ref: ref,
    charId: arg,
    setState: (s) { state = s; },
    getState: () => state,
    invalidateHistory: _invalidateHistory,
    fixupSwipesWithImageResults: _fixupSwipesWithImageResults,
  );

  late final _draftCtrl = ChatDraftController(
    ref: ref,
    setState: (s) { state = s; },
    getState: () => state,
  );

  void _invalidateHistory() => ref.invalidate(chatHistoryProvider);

  // Delegate methods to controllers
  Future<void> editMessage(int index, String newContent, {String? tagStart, String? tagEnd}) =>
      _messageOpsCtrl.editMessage(index, newContent, tagStart: tagStart, tagEnd: tagEnd);

  Future<void> moveMessage(int fromIndex, int toIndex) =>
      _messageOpsCtrl.moveMessage(fromIndex, toIndex);

  Future<void> deleteMessage(int index) =>
      _messageOpsCtrl.deleteMessage(index);

  Future<void> toggleMessageHidden(int index) =>
      _messageOpsCtrl.toggleMessageHidden(index);

  Future<void> unhideAllMessages() =>
      _messageOpsCtrl.unhideAllMessages();

  Future<void> hideTopMessages(int count) =>
      _messageOpsCtrl.hideTopMessages(count);

  Future<void> clearChat() =>
      _messageOpsCtrl.clearChat();

  void setSwipe(int messageIndex, int swipeId) =>
      _swipeCtrl.setSwipe(messageIndex, swipeId);

  Future<void> changeSwipe(int messageIndex, int dir, {bool fromSwipe = false}) =>
      _swipeCtrl.changeSwipe(messageIndex, dir, fromSwipe: fromSwipe);

  Future<void> setGreeting(int messageIndex, int direction) =>
      _swipeCtrl.setGreeting(messageIndex, direction);

  Future<void> switchSession(int sessionIndex) =>
      _sessionCtrl.switchSession(sessionIndex);

  Future<void> createNewSession() =>
      _sessionCtrl.createNewSession();

  Future<List<ChatSession>> getSessions() =>
      _sessionCtrl.getSessions();

  Future<void> branchSession(int index) =>
      _sessionCtrl.branchSession(index);

  Future<void> newSession() =>
      _sessionCtrl.createNewSession();

  Future<void> saveDraft(String draftText) =>
      _draftCtrl.saveDraft(draftText);

  Future<void> sendMessage(String text, {String? guidanceText, String? imageDataUrl}) async {
    final current = state.value;
    if (current == null || current.isGenerating) return;

    final userMsg = ChatMessage(
      id: generateId(),
      role: 'user',
      content: text,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      tokens: estimateTokens(text),
      imagePath: imageDataUrl,
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
    state = AsyncData(current.copyWith(session: updatedSession, isGenerating: true, generationStartTime: DateTime.now()));

    final charRepo = ref.read(characterRepoProvider);
    final character = await charRepo.getById(arg);
    if (character != null) {
      final talkativeness = character.extensions['talkativeness'];
      if (talkativeness is num && talkativeness < 1.0) {
        final roll = DateTime.now().microsecond % 100 / 100.0;
        if (roll > talkativeness) {
          _abortHandler.clearStreaming();
          state = AsyncData(current.copyWith(session: updatedSession, isGenerating: false));
          return;
        }
      }
    }

    await _runGeneration(updatedSession, current, guidanceText: guidanceText);
  }

  Future<void> regenerateLastAssistant({String? guidanceText}) async {
    if (state.value?.isGenerating == true) {
      abortGeneration();
    }
    final current = state.value;
    if (current == null || current.session == null || current.isGenerating) return;

    final lastIdx = current.messages.length - 1;
    if (lastIdx < 0) return;

    final lastMsg = current.messages[lastIdx];

    if (lastMsg.role == 'user') {
      state = AsyncData(current.copyWith(isGenerating: true, generationStartTime: DateTime.now()));
      final promptSession = current.session!.copyWith(
        messages: current.messages,
        updatedAt: currentTimestampSeconds(),
      );
      await _runGeneration(promptSession, current, saveSession: current.session!, guidanceText: guidanceText);
      return;
    }

    final prevAssistant = lastMsg;
    final regenTargetId = prevAssistant.id;
    _abortHandler.restorationMessage = prevAssistant;

    final clearedMsg = prevAssistant.copyWith(
      content: '',
      reasoning: null,
      isTyping: true,
      genTime: null,
      tokens: null,
      isError: false,
    );
    final clearedMessages = [...current.messages];
    clearedMessages[lastIdx] = clearedMsg;
    final clearedSession = current.session!.copyWith(
      messages: clearedMessages,
      updatedAt: currentTimestampSeconds(),
    );

    state = AsyncData(ChatState(
      session: clearedSession,
      isGenerating: true,
      generationStartTime: DateTime.now(),
      regenTargetId: regenTargetId,
      visibleStartIndex: current.visibleStartIndex,
    ));

    final promptMessages = [...current.messages];
    promptMessages.removeAt(lastIdx);
    final promptSession = current.session!.copyWith(
      messages: promptMessages,
      updatedAt: currentTimestampSeconds(),
    );

    await _runGeneration(
      promptSession, current,
      saveSession: current.session!,
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

    final genId = _abortHandler.nextGenId();
    state = AsyncData(current.copyWith(isGenerating: true, generationStartTime: DateTime.now()));

    final notifService = GenerationNotificationService.instance;
    final charRepo = ref.read(characterRepoProvider);
    final character = await charRepo.getById(arg);
    await notifService.onGenerationStarted(character?.name ?? 'Unknown');

    final service = ref.read(chatGenerationServiceProvider);
    final result = await service.generate(
      session: current.session!,
      charId: arg,
      genId: genId,
      currentState: current,
      onStateUpdate: (s) { if (_abortHandler.isCurrentGen(genId)) state = AsyncData(s); },
      isAborted: () => !_abortHandler.isCurrentGen(genId),
    );

    if (!_abortHandler.isCurrentGen(genId)) return;

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
      state = AsyncData(current.copyWith(session: finalSession));
    } else {
      state = AsyncData(result);
    }

    final preview = buildMessagePreview(result.messages);
    await notifService.onGenerationCompleted(
      character?.name ?? 'Unknown', arg,
      messagePreview: preview,
      sessionId: result.session?.id,
      msgId: result.messages.isNotEmpty ? result.messages.last.id : null,
      avatarPath: character?.avatarPath,
    );
  }

  Future<void> _runGeneration(
    ChatSession session,
    ChatState current, {
    ChatSession? saveSession,
    String? guidanceText,
    List<String>? previousSwipes,
    int previousSwipeId = 0,
    String? previousReasoning,
    String? previousGenTime,
    int? previousTokens,
    List<Map<String, dynamic>>? previousSwipesMeta,
    String? regenTargetId,
  }) {
    final genId = _abortHandler.nextGenId();
    final pipeline = GenerationPipeline(
      ref: ref,
      charId: arg,
      abortHandler: _abortHandler,
      setState: (s) { state = s; },
      getState: () => state,
    );
    return pipeline.run(
      genId: genId,
      session: session,
      saveSession: saveSession,
      guidanceText: guidanceText,
      previousSwipes: previousSwipes,
      previousSwipeId: previousSwipeId,
      previousReasoning: previousReasoning,
      previousGenTime: previousGenTime,
      previousTokens: previousTokens,
      previousSwipesMeta: previousSwipesMeta,
      regenTargetId: regenTargetId,
    );
  }
}
