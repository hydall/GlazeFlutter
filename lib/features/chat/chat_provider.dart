import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/models/chat_message.dart';
import '../../core/services/generation_notification_service.dart';
import '../../core/utils/id_generator.dart';
import '../../core/utils/time_helpers.dart';
import '../../core/state/db_provider.dart';
import '../cloud_sync/sync_provider.dart' show notifySyncMessageGenerated;
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
      final fixed = _fixupSwipesWithImageResults(existing);
      if (!identical(fixed, existing)) {
        // Persist the cleanup so stuck [IMG:GEN] tags don't reappear after restart
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

  CancelToken? _cancelToken;
  CancelToken? _imgGenCancelToken;
  ChatMessage? _restorationMessage;
  int _activeGenId = 0;

  /// Called by [ChatGenerationService] to register the active SSE cancel token.
  /// Guarded by [genId]: if the calling generation is no longer current, the
  /// token is immediately cancelled so its SSE stream never fires onComplete.
  void setCancelToken(CancelToken token, {required int genId}) {
    if (_activeGenId != genId) {
      token.cancel();
      return;
    }
    _cancelToken = token;
  }

  bool get isGeneratingImage => _imgGenCancelToken != null && !(_imgGenCancelToken!.isCancelled);

  static final _imgGenRegex = RegExp(r'\[IMG:GEN(?::(.*?))?\]');
  static final _imgHtmlRegex = RegExp(r"<img\s[^>]*?data-iig-instruction\s*=\s*'([^']*)'[^>]*>", caseSensitive: false, dotAll: true);
  static final _imgHtmlDoubleRegex = RegExp(r'''<img\s[^>]*?data-iig-instruction\s*=\s*"([^"]*)"[^>]*>''', caseSensitive: false, dotAll: true);
  // Matches <img ... src="[IMG:GEN...]" ...> (any variant, with or without instruction)
  static final _imgSrcGenRegex = RegExp(r'''<img\b[^>]*?\bsrc\s*=\s*["']\[IMG:GEN[^\]]*\]["'][^>]*>''', caseSensitive: false, dotAll: true);

  ChatSession _fixupSwipesWithImageResults(ChatSession session) {
    bool changed = false;
    final messages = List<ChatMessage>.from(session.messages);
    for (int i = 0; i < messages.length; i++) {
      final msg = messages[i];
      var currentMsg = msg;

      if (msg.swipes.isNotEmpty) {
        final swipeIdx = msg.swipeId;
        if (swipeIdx >= 0 && swipeIdx < msg.swipes.length && msg.content != msg.swipes[swipeIdx]) {
          final fixedSwipes = List<String>.from(msg.swipes);
          fixedSwipes[swipeIdx] = msg.content;
          currentMsg = msg.copyWith(swipes: fixedSwipes);
          changed = true;
        }
      }

      final cleanedContent = _cleanStuckImgGenTags(currentMsg.content);
      if (cleanedContent != currentMsg.content) {
        currentMsg = currentMsg.copyWith(content: cleanedContent);
        changed = true;
      }

      if (currentMsg.swipes.isNotEmpty) {
        final fixedSwipes = List<String>.from(currentMsg.swipes);
        bool swipesChanged = false;
        for (int s = 0; s < fixedSwipes.length; s++) {
          final cleaned = _cleanStuckImgGenTags(fixedSwipes[s]);
          if (cleaned != fixedSwipes[s]) {
            fixedSwipes[s] = cleaned;
            swipesChanged = true;
          }
        }
        if (swipesChanged) {
          currentMsg = currentMsg.copyWith(swipes: fixedSwipes);
          changed = true;
        }
      }

      messages[i] = currentMsg;
    }
    if (!changed) return session;
    return session.copyWith(messages: messages);
  }

  String _cleanStuckImgGenTags(String text) {
    if (!_imgGenRegex.hasMatch(text) && !_imgHtmlRegex.hasMatch(text) && !_imgHtmlDoubleRegex.hasMatch(text) && !_imgSrcGenRegex.hasMatch(text)) return text;
    var result = text;
    // Remove <img src="[IMG:GEN...]" ...> entirely — these have no instruction to recover
    result = result.replaceAll(_imgSrcGenRegex, '[IMG:ERROR:${jsonEncode({'error': 'Generation interrupted'})}]');
    result = result.replaceAllMapped(_imgHtmlRegex, (m) {
      final instruction = m.group(1) ?? '';
      final errorJson = jsonEncode({'error': 'Generation interrupted', 'instruction': instruction});
      return '[IMG:ERROR:$errorJson]';
    });
    result = result.replaceAllMapped(_imgHtmlDoubleRegex, (m) {
      final instruction = m.group(1) ?? '';
      final errorJson = jsonEncode({'error': 'Generation interrupted', 'instruction': instruction});
      return '[IMG:ERROR:$errorJson]';
    });
    result = result.replaceAllMapped(_imgGenRegex, (m) {
      final instruction = m.group(1) ?? '';
      final errorJson = instruction.isNotEmpty
          ? jsonEncode({'error': 'Generation interrupted', 'instruction': instruction})
          : jsonEncode({'error': 'Generation interrupted'});
      return '[IMG:ERROR:$errorJson]';
    });
    return result;
  }

  void abortImageGeneration() {
    _imgGenCancelToken?.cancel();
    _imgGenCancelToken = null;
    final current = state.value;
    if (current != null && current.isGeneratingImage) {
      state = AsyncData(current.copyWith(isGeneratingImage: false));
    }
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
    final swipeIdx = lastMsg.swipeId;
    final updatedSwipes = lastMsg.swipes.isNotEmpty && swipeIdx >= 0 && swipeIdx < lastMsg.swipes.length
        ? (List<String>.from(lastMsg.swipes)..[swipeIdx] = resetContent)
        : lastMsg.swipes;
    newMessages[lastIdx] = lastMsg.copyWith(content: resetContent, swipes: updatedSwipes);
    final resetSession = session.copyWith(
      messages: newMessages,
      updatedAt: currentTimestampSeconds(),
    );
    state = AsyncData(current.copyWith(session: resetSession, isGeneratingImage: true));

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
    state = AsyncData(current.copyWith(session: updatedSession, isGenerating: true, generationStartTime: DateTime.now()));

    final charRepo = ref.read(characterRepoProvider);
    final character = await charRepo.getById(arg);
    if (character != null) {
      final talkativeness = character.extensions['talkativeness'];
      if (talkativeness is num && talkativeness < 1.0) {
        final roll = DateTime.now().microsecond % 100 / 100.0;
        if (roll > talkativeness) {
          _clearStreaming();
          state = AsyncData(current.copyWith(session: updatedSession, isGenerating: false));
          return;
        }
      }
    }

    await _runGeneration(updatedSession, current, guidanceText: guidanceText);
  }

  Future<void> regenerateLastAssistant({String? guidanceText}) async {
    // Abort any in-flight generation immediately (does not await) — correctness
    // is guaranteed by the isAborted() closure and setCancelToken genId guard,
    // so we don't need to wait for the old stream to fully close before starting.
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
      await _runGeneration(promptSession, current, saveSession: current.session!);
      return;
    }

    // Last message is assistant → swipe (new variant)
    final prevAssistant = lastMsg;
    final regenTargetId = prevAssistant.id;
    _restorationMessage = prevAssistant;

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

    final genId = ++_activeGenId;
    state = AsyncData(current.copyWith(isGenerating: true, generationStartTime: DateTime.now()));

    final notifService = GenerationNotificationService.instance;
    final charRepo = ref.read(characterRepoProvider);
    final character = await charRepo.getById(arg);
    await notifService.onGenerationStarted(character?.name ?? 'Unknown');

    final service = ChatGenerationService(ref);
    final result = await service.generate(
      session: current.session!,
      charId: arg,
      genId: genId,
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
      state = AsyncData(current.copyWith(session: finalSession));
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
    state = AsyncData(current.copyWith(session: updated));
  }

  Future<void> moveMessage(int fromIndex, int toIndex) async {
    final current = state.value;
    if (current == null || current.session == null) return;
    final updated = _messageSvc.moveMessage(current.session!, fromIndex, toIndex);
    _invalidateHistory();
    state = AsyncData(current.copyWith(session: updated));
  }

  Future<void> deleteMessage(int index) async {
    final current = state.value;
    if (current == null || current.session == null) return;
    final updated = _messageSvc.deleteMessage(current.session!, index);
    _invalidateHistory();
    state = AsyncData(current.copyWith(session: updated));
  }

  Future<void> toggleMessageHidden(int index) async {
    final current = state.value;
    if (current == null || current.session == null) return;
    final updated = _messageSvc.toggleMessageHidden(current.session!, index);
    _invalidateHistory();
    state = AsyncData(current.copyWith(session: updated));
  }

  Future<void> unhideAllMessages() async {
    final current = state.value;
    if (current == null || current.session == null) return;
    final updated = _messageSvc.unhideAllMessages(current.session!);
    _invalidateHistory();
    state = AsyncData(current.copyWith(session: updated));
  }

  Future<void> hideTopMessages(int count) async {
    final current = state.value;
    if (current == null || current.session == null) return;
    final updated = _messageSvc.hideTopMessages(current.session!, count);
    _invalidateHistory();
    state = AsyncData(current.copyWith(session: updated));
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
    state = AsyncData(current.copyWith(session: updated));
  }

  /// Ported from useSwipeNavigation.js `changeSwipe`:
  /// - blocks while generating
  /// - removes the current swipe if it's an error (with siblings) and slides to a neighbor
  /// - triggers `regenerateLastAssistant` when stepping past the right edge on the last message
  /// - clears `isError` on switch
  Future<void> changeSwipe(int messageIndex, int dir, {bool fromSwipe = false}) async {
    final current = state.value;
    if (current == null || current.session == null || current.isGenerating) return;
    if (messageIndex < 0 || messageIndex >= current.messages.length) return;

    final isLast = messageIndex == current.messages.length - 1;
    final result = _messageSvc.changeSwipe(
      current.session!,
      messageIndex,
      dir,
      fromSwipe: fromSwipe,
      isLastMessage: isLast,
    );

    if (result.needsRegen) {
      await regenerateLastAssistant();
      return;
    }
    if (result.isUpdated) {
      _invalidateHistory();
      state = AsyncData(current.copyWith(session: result.session));
    }
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
    state = AsyncData(current.copyWith(session: updated));
  }

  Future<void> switchSession(int sessionIndex) async {
    _activeGenId++;
    _restorationMessage = null;
    _clearStreaming();
    try {
      final raw = await _sessionSvc.switchToSession(arg, sessionIndex);
      final session = _fixupSwipesWithImageResults(raw);
      if (!identical(session, raw)) {
        await ref.read(chatRepoProvider).put(session);
        ChatSessionService.updateCache(session);
      }
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
    final partialStreaming = ref.read(streamingStateProvider(arg));
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
          final partialText = partialStreaming.text;
          final keptSwipes = List<String>.from(restoration.swipes.isNotEmpty ? restoration.swipes : [restoration.content]);
          final keptSwipesMeta = List<Map<String, dynamic>>.from(restoration.swipesMeta.isNotEmpty ? restoration.swipesMeta : [<String, dynamic>{'genTime': restoration.genTime, 'reasoning': restoration.reasoning, 'tokens': restoration.tokens}]);
          if (partialText.isNotEmpty) {
            keptSwipes.add(partialText);
            keptSwipesMeta.add(<String, dynamic>{});
          }
          final newSwipeId = keptSwipes.length - 1;
          final updated = current.messages[idx].copyWith(
            content: partialText.isNotEmpty ? partialText : restoration.content,
            swipeId: partialText.isNotEmpty ? newSwipeId : restoration.swipeId,
            swipes: keptSwipes,
            swipesMeta: keptSwipesMeta,
            reasoning: partialText.isNotEmpty ? partialStreaming.reasoning : restoration.reasoning,
            genTime: partialText.isNotEmpty ? null : restoration.genTime,
            tokens: partialText.isNotEmpty ? null : restoration.tokens,
            isTyping: false,
            isError: false,
            swipeDirection: partialText.isNotEmpty ? 'right' : restoration.swipeDirection,
          );
          final updatedMessages = [...current.messages];
          updatedMessages[idx] = updated;
          final updatedSession = current.session?.copyWith(
            messages: updatedMessages,
            updatedAt: currentTimestampSeconds(),
          );
          if (updatedSession != null) {
            ref.read(chatRepoProvider).put(updatedSession);
            ChatSessionService.updateCache(updatedSession);
          }
          state = AsyncData(ChatState(
            session: updatedSession ?? current.session,
            isGenerating: false,
            isGeneratingImage: false,
            regenTargetId: null,
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
        state = AsyncData(current.copyWith(
          session: restoredSession ?? current.session,
          isGenerating: false,
          isGeneratingImage: false,
        ));
      } else {
        // Fresh generation (sendMessage). Never remove user messages.
        // If partial streaming content arrived, save it as an assistant message.
        // If the last message in state is an assistant that is absolutely empty
        // (no content and no reasoning), remove it. Otherwise keep everything.
        final partialText = partialStreaming.text;
        final partialReasoning = partialStreaming.reasoning;
        final hasPartial = partialText.isNotEmpty || (partialReasoning != null && partialReasoning.isNotEmpty);

        final currentMessages = current.session?.messages ?? const <ChatMessage>[];
        final lastMsg = currentMessages.isNotEmpty ? currentMessages.last : null;
        final lastIsEmptyAssistant = lastMsg != null &&
            lastMsg.role == 'assistant' &&
            lastMsg.content.isEmpty &&
            (lastMsg.reasoning == null || lastMsg.reasoning!.isEmpty);

        if (hasPartial) {
          // Save partial content as a new assistant message
          final partialMsg = ChatMessage(
            id: generateId(),
            role: 'assistant',
            content: partialText,
            reasoning: partialReasoning,
            isTyping: false,
            timestamp: DateTime.now().millisecondsSinceEpoch,
            swipes: [partialText],
            swipeId: 0,
            swipesMeta: [<String, dynamic>{}],
          );
          final baseMessages = lastIsEmptyAssistant
              ? currentMessages.sublist(0, currentMessages.length - 1)
              : currentMessages;
          final updatedMessages = [...baseMessages, partialMsg];
          final updatedSession = current.session?.copyWith(
            messages: updatedMessages,
            updatedAt: currentTimestampSeconds(),
          );
          if (updatedSession != null) {
            ref.read(chatRepoProvider).put(updatedSession);
            ChatSessionService.updateCache(updatedSession);
          }
          state = AsyncData(current.copyWith(
            session: updatedSession ?? current.session,
            isGenerating: false,
            isGeneratingImage: false,
          ));
        } else if (lastIsEmptyAssistant) {
          // Drop the empty assistant placeholder, keep everything else (incl. user msg)
          final trimmedMessages = currentMessages.sublist(0, currentMessages.length - 1);
          final trimmedSession = current.session?.copyWith(
            messages: trimmedMessages,
            updatedAt: currentTimestampSeconds(),
          );
          if (trimmedSession != null) {
            ref.read(chatRepoProvider).put(trimmedSession);
            ChatSessionService.updateCache(trimmedSession);
          }
          state = AsyncData(current.copyWith(
            session: trimmedSession ?? current.session,
            isGenerating: false,
            isGeneratingImage: false,
          ));
        } else {
          state = AsyncData(current.copyWith(isGenerating: false, isGeneratingImage: false));
        }
      }
    } else if (current != null && current.isGeneratingImage) {
      state = AsyncData(current.copyWith(isGeneratingImage: false));
    }
    _restorationMessage = null;

    GenerationNotificationService.instance.onGenerationAborted();
  }

  void _invalidateHistory() => ref.invalidate(chatHistoryProvider);

  void _clearStreaming() {
    ref.read(streamingStateProvider(arg).notifier).state = const StreamingState();
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
  }) async {
    final genId = ++_activeGenId;
    final completer = Completer<void>();
    _clearStreaming();

    final notifService = GenerationNotificationService.instance;
    final charRepo = ref.read(characterRepoProvider);
    final character = await charRepo.getById(arg);
    await notifService.onGenerationStarted(character?.name ?? 'Unknown');

    try {
    final service = ChatGenerationService(ref);
    final result = await service.generate(
      session: session,
      saveSession: saveSession,
      charId: arg,
      genId: genId,
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

    if (result.session != null) {
      await ref.read(chatRepoProvider).put(result.session!);
      ChatSessionService.updateCache(result.session!);
      _invalidateHistory();
    }

    if (regenTargetId != null) {
      if (result.regenTargetId == regenTargetId) {
        final finalState = result.copyWith(isGenerating: false, regenTargetId: null);
        state = AsyncData(finalState);
      } else if (_restorationMessage != null) {
        final originalMsg = _restorationMessage!;
        final rollbackSwipes = originalMsg.swipes.isNotEmpty ? originalMsg.swipes : [originalMsg.content];
        final rollbackSwipesMeta = originalMsg.swipesMeta.isNotEmpty ? originalMsg.swipesMeta : [<String, dynamic>{'genTime': originalMsg.genTime, 'reasoning': originalMsg.reasoning, 'tokens': originalMsg.tokens}];
        final restoreSession = saveSession ?? session;
        final idx = restoreSession.messages.indexWhere((m) => m.id == regenTargetId);
        if (idx >= 0) {
          final restored = restoreSession.messages[idx].copyWith(
            content: originalMsg.content,
            swipeId: originalMsg.swipeId,
            swipes: rollbackSwipes,
            reasoning: originalMsg.reasoning,
            genTime: originalMsg.genTime,
            tokens: originalMsg.tokens,
            swipesMeta: rollbackSwipesMeta,
            swipeDirection: originalMsg.swipeDirection,
            isTyping: false,
            isError: false,
          );
          final restoredMessages = [...restoreSession.messages];
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
            regenTargetId: null,
          ));
        } else {
          state = AsyncData(result.copyWith(isGenerating: false, regenTargetId: null));
        }
      } else {
        state = AsyncData(result.copyWith(isGenerating: false, regenTargetId: null));
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
            state = AsyncData(current.copyWith(session: restored ?? current.session, isGenerating: false, error: e.toString()));
          } else {
            state = AsyncData(current.copyWith(isGenerating: false, error: e.toString()));
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

  static final _imgErrorRegex = RegExp(r'\[IMG:ERROR:(.*?)\]');
  static final _imgResultPathRegex = RegExp(r'\[IMG:RESULT:(.*?)\]');
  static final _imgGenHtmlRegex = RegExp(r"""<img\s[^>]*?data-iig-instruction\s*=\s*'([^']*)'[^>]*?src="\[IMG:GEN\]"[^>]*>""", caseSensitive: false, dotAll: true);

  Future<void> findImageOnDisk(String messageId, String instruction) async {
    final current = state.value;
    if (current == null || current.session == null) return;

    final msgIdx = current.messages.indexWhere((m) => m.id == messageId);
    if (msgIdx < 0) return;

    final imageStorage = await ref.read(imageStorageProvider.future);
    final generatedDir = Directory(p.join(imageStorage.baseDir, 'generated'));
    if (!await generatedDir.exists()) return;

    final files = await generatedDir.list()
        .where((f) => f is File && p.extension(f.path).toLowerCase() == '.png')
        .cast<File>()
        .toList();

    if (files.isEmpty) return;

    final msg = current.messages[msgIdx];
    final Set<String> claimedPaths = {};
    for (final m in current.messages) {
      for (final match in _imgResultPathRegex.allMatches(m.content)) {
        claimedPaths.add(match.group(1) ?? '');
      }
      for (final s in m.swipes) {
        for (final match in _imgResultPathRegex.allMatches(s)) {
          claimedPaths.add(match.group(1) ?? '');
        }
      }
    }

    final unclaimed = files.where((f) => !claimedPaths.contains(f.path)).toList()
      ..sort((a, b) => b.lastAccessedSync().compareTo(a.lastAccessedSync()));

    final candidates = unclaimed.length > 20 ? unclaimed.sublist(0, 20) : unclaimed;

    if (candidates.isEmpty) return;

    final msgTimestamp = msg.timestamp ?? 0;
    File? bestMatch;
    int bestDiff = 0x7FFFFFFFFFFFFFFF;
    for (final f in candidates) {
      final stat = await f.stat();
      final fileMs = stat.modified.millisecondsSinceEpoch;
      final diff = (fileMs - msgTimestamp * 1000).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        bestMatch = f;
      }
    }

    if (bestMatch == null) return;

    final foundPath = bestMatch.path;

    var updatedContent = msg.content;
    updatedContent = _replaceFirstImgErrorOrGen(updatedContent, foundPath);

    if (updatedContent == msg.content) return;

    final updatedSwipes = List<String>.from(msg.swipes);
    final swipeIdx = msg.swipeId;
    if (swipeIdx >= 0 && swipeIdx < updatedSwipes.length) {
      updatedSwipes[swipeIdx] = updatedContent;
    }

    final newMessages = List<ChatMessage>.from(current.messages);
    newMessages[msgIdx] = msg.copyWith(content: updatedContent, swipes: updatedSwipes);
    final updatedSession = current.session!.copyWith(
      messages: newMessages,
      updatedAt: currentTimestampSeconds(),
    );
    await ref.read(chatRepoProvider).put(updatedSession);
    state = AsyncData(current.copyWith(session: updatedSession));
  }

  String _replaceFirstImgErrorOrGen(String text, String resultPath) {
    if (_imgErrorRegex.hasMatch(text)) {
      return text.replaceFirst(_imgErrorRegex, '[IMG:RESULT:$resultPath]');
    }
    if (_imgGenHtmlRegex.hasMatch(text)) {
      return text.replaceFirst(_imgGenHtmlRegex, '[IMG:RESULT:$resultPath]');
    }
    if (text.contains('[IMG:GEN]')) {
      return text.replaceFirst('[IMG:GEN]', '[IMG:RESULT:$resultPath]');
    }
    final genJsonRegex = RegExp(r'\[IMG:GEN:(.*?)\]');
    if (genJsonRegex.hasMatch(text)) {
      return text.replaceFirst(genJsonRegex, '[IMG:RESULT:$resultPath]');
    }
    return text;
  }

  Future<void> retryImageGenerationForMessage(int messageIndex) async {
    final current = state.value;
    if (current == null || current.session == null || current.isGenerating || current.isGeneratingImage) {
      return;
    }
    if (messageIndex < 0 || messageIndex >= current.messages.length) return;

    final msg = current.messages[messageIndex];
    if (msg.role != 'assistant') return;

    var resetContent = _resetImgTagsToGen(msg.content);
    if (resetContent == msg.content) return;

    final swipeIdx = msg.swipeId;
    final updatedSwipes = List<String>.from(msg.swipes);
    if (swipeIdx >= 0 && swipeIdx < updatedSwipes.length) {
      updatedSwipes[swipeIdx] = resetContent;
    }

    final newMessages = List<ChatMessage>.from(current.messages);
    newMessages[messageIndex] = msg.copyWith(content: resetContent, swipes: updatedSwipes);
    final resetSession = current.session!.copyWith(
      messages: newMessages,
      updatedAt: currentTimestampSeconds(),
    );

    state = AsyncData(current.copyWith(session: resetSession, isGeneratingImage: true));

    final imgCancelToken = CancelToken();
    _imgGenCancelToken = imgCancelToken;

    final genService = ChatGenerationService(ref);
    await genService.processImageTags(
      currentState: state.value!,
      charId: arg,
      cancelToken: imgCancelToken,
      onStateUpdate: (updatedState) {
        state = AsyncData(updatedState);
      },
    );

    _imgGenCancelToken = null;
    final finalState = state.value;
    if (finalState != null) {
      state = AsyncData(finalState.copyWith(isGeneratingImage: false));
    }
  }

  void cancelImageGeneration() {
    _imgGenCancelToken?.cancel();
    _imgGenCancelToken = null;
    final current = state.value;
    if (current != null && current.isGeneratingImage) {
      state = AsyncData(current.copyWith(isGeneratingImage: false));
    }
  }

  String _resetImgTagsToGen(String text) {
    var result = text;
    result = result.replaceAllMapped(_imgErrorRegex, (m) {
      final data = m.group(1) ?? '';
      String instruction = '';
      try {
        final parsed = jsonDecode(data);
        instruction = (parsed['instruction'] ?? '') as String;
      } catch (_) {}
      if (instruction.isNotEmpty) {
        return '[IMG:GEN:$instruction]';
      }
      return '[IMG:GEN]';
    });
    result = result.replaceAllMapped(_imgResultPathRegex, (m) {
      final raw = m.group(1) ?? '';
      final pipeIdx = raw.indexOf('|');
      final instr = pipeIdx != -1 ? raw.substring(pipeIdx + 1) : '';
      if (instr.isNotEmpty) {
        return '[IMG:GEN:$instr]';
      }
      return '[IMG:GEN]';
    });
    return result;
  }
}
