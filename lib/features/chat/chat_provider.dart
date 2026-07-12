import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../core/llm/tokenizer.dart';
import '../../core/models/chat_message.dart';
import '../../core/services/generation_notification_service.dart';
import '../../core/utils/id_generator.dart';
import '../../core/utils/time_helpers.dart';
import '../../core/state/db_provider.dart';
import '../chat_history/chat_history_provider.dart';
import '../memory/state/memory_active_drafts_provider.dart';
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
import '../extensions/services/extension_post_gen_service.dart';

final chatProvider =
    AsyncNotifierProvider.family<ChatNotifier, ChatState, String>(
      ChatNotifier.new,
    );

final streamingStateProvider = StateProvider.family<StreamingState, String>(
  (ref, _) => const StreamingState(),
);

class ChatNotifier extends AsyncNotifier<ChatState> {
  ChatNotifier(this.arg);

  final String arg;
  bool _buildComplete = false;

  void _persistSession(ChatSession session) {
    ref.read(chatRepoProvider).put(session).catchError((Object e) {
      debugPrint('[ChatNotifier] failed to persist session: $e');
    });
    ChatSessionService.updateCache(session);
  }

  @override
  Future<ChatState> build() async {
    ref.keepAlive();
    _buildComplete = false;
    final existing = await _sessionSvc.findExistingSession(arg);
    if (!ref.mounted) return const ChatState();
    if (_buildComplete) {
      return state.value ?? ChatState(session: existing);
    }
    if (existing != null) {
      final fixed = _fixupSwipesWithImageResults(existing);
      if (!identical(fixed, existing)) {
        await ref.read(chatRepoProvider).put(fixed);
        ChatSessionService.updateCache(fixed);
        if (!ref.mounted) return const ChatState();
      }
      final start = fixed.messages.length > ChatState.initialPageSize
          ? fixed.messages.length - ChatState.initialPageSize
          : 0;
      final result = ChatState(session: fixed, visibleStartIndex: start);
      _buildComplete = true;
      return result;
    }
    final session = await _sessionSvc.createInitialSession(arg);
    if (!ref.mounted) return const ChatState();
    _buildComplete = true;
    return ChatState(session: session);
  }

  void loadOlderMessages() {
    final current = state.value;
    if (current == null || !current.hasMoreOlder || current.isLoadingOlder) {
      return;
    }

    final newStart = current.visibleStartIndex > ChatState.olderPageSize
        ? current.visibleStartIndex - ChatState.olderPageSize
        : 0;
    state = AsyncData(
      current.copyWith(visibleStartIndex: newStart, isLoadingOlder: false),
    );
  }

  late final AbortHandler _abortHandler = AbortHandler(
    ref: ref,
    charId: arg,
    setState: (s) {
      state = s;
    },
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
    setImgGenCancelToken: (t) {
      _abortHandler.imgGenCancelToken = t;
    },
    getImgGenCancelToken: () => _abortHandler.imgGenCancelToken,
    startImageOperation: _abortHandler.nextGenId,
    isCurrentGeneration: _abortHandler.isCurrentGen,
    setState: (s) {
      state = s;
    },
    getState: () => state,
  );

  // Controllers
  late final _messageOpsCtrl = ChatMessageOpsController(
    ref: ref,
    charId: arg,
    setState: (s) {
      state = s;
    },
    getState: () => state,
    invalidateHistory: _invalidateHistory,
  );

  late final _swipeCtrl = ChatSwipeController(
    ref: ref,
    charId: arg,
    setState: (s) {
      state = s;
    },
    getState: () => state,
    invalidateHistory: _invalidateHistory,
  );

  late final _sessionCtrl = ChatSessionController(
    ref: ref,
    charId: arg,
    setState: (s) {
      state = s;
    },
    getState: () => state,
    invalidateHistory: _invalidateHistory,
    fixupSwipesWithImageResults: _fixupSwipesWithImageResults,
  );

  late final _draftCtrl = ChatDraftController(
    ref: ref,
    setState: (s) {
      state = s;
    },
    getState: () => state,
  );

  void _invalidateHistory() => ref.invalidate(chatHistoryProvider);

  // Delegate methods to controllers
  Future<void> editMessage(
    int index,
    String newContent, {
    String? tagStart,
    String? tagEnd,
  }) => _messageOpsCtrl.editMessage(
    index,
    newContent,
    tagStart: tagStart,
    tagEnd: tagEnd,
  );

  Future<void> moveMessage(int fromIndex, int toIndex) =>
      _messageOpsCtrl.moveMessage(fromIndex, toIndex);

  Future<void> deleteMessage(int index) => _messageOpsCtrl.deleteMessage(index);

  Future<void> toggleMessageHidden(int index) =>
      _messageOpsCtrl.toggleMessageHidden(index);

  Future<void> unhideAllMessages() => _messageOpsCtrl.unhideAllMessages();

  Future<void> hideTopMessages(int count) =>
      _messageOpsCtrl.hideTopMessages(count);

  Future<void> clearChat() => _messageOpsCtrl.clearChat();

  void setSwipe(int messageIndex, int swipeId) =>
      _swipeCtrl.setSwipe(messageIndex, swipeId);

  Future<void> changeSwipe(
    int messageIndex,
    int dir, {
    bool fromSwipe = false,
  }) => _swipeCtrl.changeSwipe(messageIndex, dir, fromSwipe: fromSwipe);

  Future<void> changeAgentSwipe(
    int messageIndex,
    int dir, {
    bool fromSwipe = false,
  }) => _swipeCtrl.changeAgentSwipe(messageIndex, dir, fromSwipe: fromSwipe);

  Future<void> setGreeting(int messageIndex, int direction) =>
      _swipeCtrl.setGreeting(messageIndex, direction);

  Future<void> switchSession(int sessionIndex) =>
      _sessionCtrl.switchSession(sessionIndex);

  Future<void> createNewSession() => _sessionCtrl.createNewSession();

  Future<List<ChatSession>> getSessions() => _sessionCtrl.getSessions();

  Future<void> branchSession(int index) => _sessionCtrl.branchSession(index);

  Future<void> newSession() => _sessionCtrl.createNewSession();

  Future<void> saveDraft(String draftText) => _draftCtrl.saveDraft(draftText);

  Future<void> sendMessage(
    String text, {
    String? guidanceText,
    String? imageDataUrl,
  }) async {
    if (!ref.mounted) return;
    final current = state.value;
    if (current == null || current.isGenerating || current.isPostGenRunning) {
      return;
    }
    if (_isMemoryDraftActive(current)) return;

    final userMsg = ChatMessage(
      id: generateId(),
      role: 'user',
      content: text,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      tokens: estimateTokens(text),
      imagePath: imageDataUrl,
    );

    final updatedSession = await ref
        .read(chatRepoProvider)
        .appendUserMessageAndClearDraft(
          sessionId: current.session!.id,
          message: userMsg,
          updatedAt: currentTimestampSeconds(),
        );
    if (updatedSession == null) return;
    // Mark the latest tracker snapshot as committed — the user has moved on
    // from the previous assistant turn by sending a follow-up. This separates
    // accepted state (committed=1, used by getLatestCommitted) from
    // tentative/regen state (committed=0).
    final committedSnapshot = await ref
        .read(trackerSnapshotRepoProvider)
        .commitLatest(current.session!.id);
    if (committedSnapshot != null) {
      await ref
          .read(characterKnowledgeFactRepoProvider)
          .activateAnchor(
            sessionId: current.session!.id,
            messageId: committedSnapshot.messageId,
            swipeId: committedSnapshot.swipeId,
            agentSwipeId: committedSnapshot.agentSwipeId,
          );
    }
    if (!ref.mounted) return;
    ChatSessionService.updateCache(updatedSession);
    _invalidateHistory();
    state = AsyncData(
      current.copyWith(
        session: updatedSession,
        isGenerating: true,
        generationStartTime: DateTime.now(),
      ),
    );

    // Dispatch `afterUser` extension blocks. This is fire-and-forget — the
    // generation pipeline starts immediately, the post-gen service runs
    // the chain in the background and persists its own InfoBlocks.
    unawaited(_dispatchAfterUserBlocks(updatedSession));

    try {
      final charRepo = ref.read(characterRepoProvider);
      final character = await charRepo.getById(arg);
      if (!ref.mounted) return;
      if (character != null) {
        final talkativeness = character.extensions['talkativeness'];
        if (talkativeness is num && talkativeness < 1.0) {
          final roll = DateTime.now().microsecond % 100 / 100.0;
          if (roll > talkativeness) {
            _abortHandler.clearStreaming();
            state = AsyncData(
              current.copyWith(session: updatedSession, isGenerating: false),
            );
            return;
          }
        }
      }

      await _runGeneration(updatedSession, current, guidanceText: guidanceText);
    } catch (e, st) {
      debugPrint('[ChatNotifier] send setup failed: $e\n$st');
      if (!ref.mounted) return;
      final latest = state.value;
      if (latest?.session?.id == updatedSession.id) {
        state = AsyncData(
          latest!.copyWith(
            isGenerating: false,
            isGeneratingImage: false,
            isPostGenRunning: false,
            error: e.toString(),
          ),
        );
      }
    }
  }

  Future<void> _dispatchAfterUserBlocks(ChatSession session) async {
    try {
      if (!ref.mounted) return;
      final charRepo = ref.read(characterRepoProvider);
      final character = await charRepo.getById(arg);
      if (!ref.mounted) return;
      if (character == null) return;
      final post = ref.read(extensionPostGenServiceProvider);
      await post.runAfterUserBlocks(
        charId: arg,
        session: session,
        character: character,
        persona: null,
      );
    } catch (e) {
      debugPrint('[ChatNotifier] afterUser dispatch failed: $e');
    }
  }

  Future<void> regenerateLastAssistant({String? guidanceText}) async {
    if (!ref.mounted) return;
    if (state.value?.isGenerating == true ||
        state.value?.isPostGenRunning == true) {
      abortGeneration();
    }
    final current = state.value;
    if (current == null ||
        current.session == null ||
        current.isGenerating ||
        current.isPostGenRunning) {
      return;
    }
    if (_isMemoryDraftActive(current)) return;

    final lastIdx = current.messages.length - 1;
    if (lastIdx < 0) return;

    final lastMsg = current.messages[lastIdx];

    if (lastMsg.role == 'user') {
      state = AsyncData(
        current.copyWith(
          isGenerating: true,
          generationStartTime: DateTime.now(),
        ),
      );
      final promptSession = current.session!.copyWith(
        messages: current.messages,
        updatedAt: currentTimestampSeconds(),
      );
      await _runGeneration(
        promptSession,
        current,
        saveSession: current.session!,
        guidanceText: guidanceText,
      );
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

    state = AsyncData(
      ChatState(
        session: clearedSession,
        isGenerating: true,
        generationStartTime: DateTime.now(),
        regenTargetId: regenTargetId,
        visibleStartIndex: current.visibleStartIndex,
      ),
    );

    final promptMessages = [...current.messages];
    promptMessages.removeAt(lastIdx);
    final promptSession = current.session!.copyWith(
      messages: promptMessages,
      updatedAt: currentTimestampSeconds(),
    );

    await _runGeneration(
      promptSession,
      current,
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
      previousSwipesMeta: _previousSwipesMetaForRegen(prevAssistant),
    );
  }

  List<Map<String, dynamic>>? _previousSwipesMetaForRegen(ChatMessage message) {
    if (message.swipesMeta.isNotEmpty) return message.swipesMeta;
    final swipes = message.swipes.isNotEmpty
        ? message.swipes
        : [message.content];
    return List<Map<String, dynamic>>.generate(
      swipes.length,
      (i) => i == message.swipeId
          ? <String, dynamic>{
              'genTime': message.genTime,
              'reasoning': message.reasoning,
              'tokens': message.tokens,
            }
          : <String, dynamic>{},
    );
  }

  Future<void> continueMessage() async {
    if (!ref.mounted) return;
    final current = state.value;
    if (current == null ||
        current.session == null ||
        current.isGenerating ||
        current.isPostGenRunning) {
      return;
    }
    if (_isMemoryDraftActive(current)) return;

    final lastIdx = current.messages.length - 1;
    if (lastIdx < 0) return;
    final lastMsg = current.messages[lastIdx];
    if (lastMsg.role != 'assistant') return;

    final genId = _abortHandler.nextGenId();
    state = AsyncData(
      current.copyWith(isGenerating: true, generationStartTime: DateTime.now()),
    );

    final notifService = GenerationNotificationService.instance;
    final charRepo = ref.read(characterRepoProvider);
    final character = await charRepo.getById(arg);
    if (!ref.mounted || !_abortHandler.isCurrentGen(genId)) return;
    await notifService.onGenerationStarted(character?.name ?? 'Unknown');
    if (!ref.mounted || !_abortHandler.isCurrentGen(genId)) return;

    final service = ref.read(chatGenerationServiceProvider);
    final result = await service.generate(
      session: current.session!,
      charId: arg,
      genId: genId,
      currentState: current,
      onStateUpdate: (s) {
        if (_abortHandler.isCurrentGen(genId)) state = AsyncData(s);
      },
      isAborted: () => !_abortHandler.isCurrentGen(genId),
    );

    if (!ref.mounted || !_abortHandler.isCurrentGen(genId)) return;

    final generatedMsg = result.messages.isNotEmpty
        ? result.messages.last
        : null;
    if (generatedMsg != null && generatedMsg.role == 'assistant') {
      final appendedContent = '${lastMsg.content}${generatedMsg.content}';
      final appendedMsg = generatedMsg.copyWith(content: appendedContent);
      final updatedMessages = [
        ...result.messages.sublist(0, result.messages.length - 1),
        appendedMsg,
      ];
      final finalSession = result.session!.copyWith(
        messages: updatedMessages,
        updatedAt: currentTimestampSeconds(),
      );
      await ref.read(chatRepoProvider).put(finalSession);
      if (!ref.mounted || !_abortHandler.isCurrentGen(genId)) return;
      ChatSessionService.updateCache(finalSession);
      _invalidateHistory();
      state = AsyncData(
        current.copyWith(
          session: finalSession,
          isGenerating: false,
          isGeneratingImage: false,
          isPostGenRunning: false,
        ),
      );
    } else {
      state = AsyncData(result);
    }

    final preview = buildMessagePreview(result.messages);
    await notifService.onGenerationCompleted(
      character?.name ?? 'Unknown',
      arg,
      messagePreview: preview,
      sessionId: result.session?.id,
      msgId: result.messages.isNotEmpty ? result.messages.last.id : null,
      avatarPath: character?.avatarPath,
    );
  }

  bool _isMemoryDraftActive(ChatState current) {
    final sessionId = current.session?.id;
    if (sessionId == null) return false;
    return ref.read(memoryActiveDraftsProvider).contains(sessionId);
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
      setState: (s) {
        state = s;
      },
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

  /// Re-run POST-cleaner on an existing assistant message. Triggers a new
  /// 'cleaned' blue sub-swipe appended to the target message, cleaning the
  /// final (agentSwipes[0]) text. See [GenerationPipeline.rerunCleaner].
  Future<void> rerunCleaner(String messageId) async {
    if (!ref.mounted) return;
    final current = state.value;
    if (current == null || current.isGenerating || current.isPostGenRunning) {
      return;
    }
    final sessionId = current.session?.id;
    if (sessionId == null) return;
    final pipeline = GenerationPipeline(
      ref: ref,
      charId: arg,
      abortHandler: _abortHandler,
      setState: (s) {
        state = s;
      },
      getState: () => state,
    );
    await pipeline.rerunCleaner(sessionId: sessionId, messageId: messageId);
  }
}
