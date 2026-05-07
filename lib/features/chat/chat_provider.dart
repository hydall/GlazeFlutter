import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/chat_message.dart';
import '../../core/models/persona.dart';
import '../../core/services/generation_notification_service.dart';
import '../../core/state/active_selection_provider.dart';
import '../../core/utils/id_generator.dart';
import '../../core/utils/time_helpers.dart';
import '../../core/state/db_provider.dart';
import '../cloud_sync/sync_provider.dart';
import '../chat_history/chat_history_screen.dart' show chatHistoryProvider;
import 'chat_generation_service.dart';
import 'chat_state.dart';
import 'initial_message_builder.dart';

final chatProvider =
    AsyncNotifierProvider.family<ChatNotifier, ChatState, String>(
      ChatNotifier.new,
    );

class ChatNotifier extends FamilyAsyncNotifier<ChatState, String> {
  CancelToken? _cancelToken;

  void setCancelToken(CancelToken token) => _cancelToken = token;

  @override
  Future<ChatState> build(String arg) async {
    final repo = ref.read(chatRepoProvider);
    final sessions = await repo.getByCharacterId(arg);

    if (sessions.isNotEmpty) {
      final charRepo = ref.read(characterRepoProvider);
      final character = await charRepo.getById(arg);
      final currentIdx = character?.currentSessionIndex ?? 0;
      final target = sessions.where((s) => s.sessionIndex == currentIdx).firstOrNull ?? sessions.first;
      return ChatState(session: target);
    }

    final charRepo = ref.read(characterRepoProvider);
    final character = await charRepo.getById(arg);

    final persona = await _resolvePersona();

    final initialMessages = InitialMessageBuilder.build(
      character: character,
      persona: persona,
      sessionId: '${arg}_0',
    );

    final newSession = ChatSession(
      id: '${arg}_0',
      characterId: arg,
      sessionIndex: 0,
      messages: initialMessages,
    );
    await repo.put(newSession);
    return ChatState(session: newSession);
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
    final now = currentTimestampSeconds();
    final updatedSession = current.session!.copyWith(
      messages: updatedMessages,
      updatedAt: now,
    );

    await ref.read(chatRepoProvider).put(updatedSession);
    _invalidateHistory();
    state = AsyncData(ChatState(session: updatedSession, isGenerating: true));

    final charRepo = ref.read(characterRepoProvider);
    final character = await charRepo.getById(arg);
    if (character != null) {
      final talkativeness = character.extensions['talkativeness'];
      if (talkativeness is num && talkativeness < 1.0) {
        final roll = DateTime.now().microsecond % 100 / 100.0;
        if (roll > talkativeness) {
          state = AsyncData(ChatState(session: updatedSession));
          return;
        }
      }
    }

    final notifService = GenerationNotificationService.instance;
    await notifService.onGenerationStarted();

    final service = ChatGenerationService(ref);
    final result = await service.generate(
      session: updatedSession,
      charId: arg,
      currentState: current,
      onStateUpdate: (s) => state = AsyncData(s),
      guidanceText: guidanceText,
    );
    state = AsyncData(result);

    await service.processImageTags(
      currentState: result,
      charId: arg,
      onStateUpdate: (s) => state = AsyncData(s),
    );
    notifySyncMessageGenerated(ref);

    await notifService.onGenerationCompleted(character?.name ?? 'Unknown', arg);
  }

  Future<void> regenerateLastAssistant({String? guidanceText}) async {
    final current = state.value;
    if (current == null || current.session == null || current.isGenerating) return;

    final lastIdx = current.messages.length - 1;
    if (lastIdx < 0) return;

    final lastMsg = current.messages[lastIdx];
    List<ChatMessage> baseMessages;
    ChatMessage? prevAssistant;

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
    state = AsyncData(ChatState(session: trimmedSession, isGenerating: true));

    final notifService = GenerationNotificationService.instance;
    await notifService.onGenerationStarted();

    final service = ChatGenerationService(ref);
    final result = await service.generate(
      session: trimmedSession,
      charId: arg,
      currentState: current,
      onStateUpdate: (s) => state = AsyncData(s),
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
      guidanceText: guidanceText,
    );
    state = AsyncData(result);

    await service.processImageTags(
      currentState: result,
      charId: arg,
      onStateUpdate: (s) => state = AsyncData(s),
    );
    notifySyncMessageGenerated(ref);

    final charRepo = ref.read(characterRepoProvider);
    final character = await charRepo.getById(arg);
    await notifService.onGenerationCompleted(character?.name ?? 'Unknown', arg);
  }

  Future<void> continueMessage() async {
    final current = state.value;
    if (current == null || current.session == null || current.isGenerating) return;

    final lastIdx = current.messages.length - 1;
    if (lastIdx < 0) return;
    final lastMsg = current.messages[lastIdx];
    if (lastMsg.role != 'assistant') return;

    state = AsyncData(ChatState(session: current.session, isGenerating: true));

    final notifService = GenerationNotificationService.instance;
    await notifService.onGenerationStarted();

    final service = ChatGenerationService(ref);
    final result = await service.generate(
      session: current.session!,
      charId: arg,
      currentState: current,
      onStateUpdate: (s) => state = AsyncData(s),
    );

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

    final charRepo = ref.read(characterRepoProvider);
    final character = await charRepo.getById(arg);
    final persona = await _resolvePersona();

    final initialMessages = InitialMessageBuilder.build(
      character: character,
      persona: persona,
      sessionId: current.session!.id,
    );

    final clearedSession = current.session!.copyWith(messages: initialMessages);
    await ref.read(chatRepoProvider).put(clearedSession);
    _invalidateHistory();
    state = AsyncData(ChatState(session: clearedSession));
  }

  Future<void> editMessage(int index, String newContent) async {
    final current = state.value;
    if (current == null || current.session == null) return;
    if (index < 0 || index >= current.messages.length) return;

    final newMessages = List<ChatMessage>.from(current.messages);
    newMessages[index] = current.messages[index].content != newContent
        ? current.messages[index].copyWith(content: newContent)
        : current.messages[index];

    final newSession = current.session!.copyWith(
      messages: newMessages,
      updatedAt: currentTimestampSeconds(),
    );
    await ref.read(chatRepoProvider).put(newSession);
    _invalidateHistory();
    state = AsyncData(ChatState(session: newSession));
  }

  Future<void> moveMessage(int fromIndex, int toIndex) async {
    final current = state.value;
    if (current == null || current.session == null) return;
    final msgs = current.messages;
    if (fromIndex < 0 || fromIndex >= msgs.length) return;
    if (toIndex < 0 || toIndex >= msgs.length) return;
    if (fromIndex == toIndex) return;

    final newMessages = List<ChatMessage>.from(msgs);
    final moved = newMessages.removeAt(fromIndex);
    newMessages.insert(toIndex, moved);

    final newSession = current.session!.copyWith(
      messages: newMessages,
      updatedAt: currentTimestampSeconds(),
    );
    await ref.read(chatRepoProvider).put(newSession);
    _invalidateHistory();
    state = AsyncData(ChatState(session: newSession));
  }

  Future<void> deleteMessage(int index) async {
    final current = state.value;
    if (current == null || current.session == null) return;
    if (index < 0 || index >= current.messages.length) return;

    final newMessages = List<ChatMessage>.from(current.messages)..removeAt(index);
    final newSession = current.session!.copyWith(
      messages: newMessages,
      updatedAt: currentTimestampSeconds(),
    );
    await ref.read(chatRepoProvider).put(newSession);
    _invalidateHistory();
    state = AsyncData(ChatState(session: newSession));
  }

  Future<void> toggleMessageHidden(int index) async {
    final current = state.value;
    if (current == null || current.session == null) return;
    if (index < 0 || index >= current.messages.length) return;

    final newMessages = List<ChatMessage>.from(current.messages);
    newMessages[index] = newMessages[index].copyWith(isHidden: !newMessages[index].isHidden);

    final newSession = current.session!.copyWith(
      messages: newMessages,
      updatedAt: currentTimestampSeconds(),
    );
    await ref.read(chatRepoProvider).put(newSession);
    _invalidateHistory();
    state = AsyncData(ChatState(session: newSession));
  }

  Future<void> unhideAllMessages() async {
    final current = state.value;
    if (current == null || current.session == null) return;

    bool changed = false;
    final newMessages = current.messages.map((m) {
      if (m.isHidden) { changed = true; return m.copyWith(isHidden: false); }
      return m;
    }).toList();

    if (!changed) return;

    final newSession = current.session!.copyWith(
      messages: newMessages,
      updatedAt: currentTimestampSeconds(),
    );
    await ref.read(chatRepoProvider).put(newSession);
    _invalidateHistory();
    state = AsyncData(ChatState(session: newSession));
  }

  Future<void> hideTopMessages(int count) async {
    final current = state.value;
    if (current == null || current.session == null) return;

    final visibleIndices = <int>[];
    for (int i = 0; i < current.messages.length; i++) {
      if (!current.messages[i].isHidden) visibleIndices.add(i);
    }

    final toHide = visibleIndices.take(count).toList();
    if (toHide.isEmpty) return;

    final newMessages = List<ChatMessage>.from(current.messages);
    for (final idx in toHide) {
      newMessages[idx] = newMessages[idx].copyWith(isHidden: true);
    }

    final newSession = current.session!.copyWith(
      messages: newMessages,
      updatedAt: currentTimestampSeconds(),
    );
    await ref.read(chatRepoProvider).put(newSession);
    _invalidateHistory();
    state = AsyncData(ChatState(session: newSession));
  }

  void setSwipe(int messageIndex, int swipeId) {
    final current = state.value;
    if (current == null || current.session == null) return;
    if (messageIndex < 0 || messageIndex >= current.messages.length) return;

    final msg = current.messages[messageIndex];
    if (msg.swipes.isEmpty || swipeId < 0 || swipeId >= msg.swipes.length) return;

    final meta = swipeId < msg.swipesMeta.length ? msg.swipesMeta[swipeId] : null;

    final updated = msg.copyWith(
      swipeId: swipeId,
      content: msg.swipes[swipeId],
      reasoning: meta?['reasoning'] as String?,
      genTime: meta?['genTime'] as String?,
      tokens: meta?['tokens'] as int?,
    );

    final newMessages = List<ChatMessage>.from(current.messages);
    newMessages[messageIndex] = updated;

    final newSession = current.session!.copyWith(
      messages: newMessages,
      updatedAt: currentTimestampSeconds(),
    );
    ref.read(chatRepoProvider).put(newSession);
    _invalidateHistory();
    state = AsyncData(ChatState(session: newSession));
  }

  Future<void> switchSession(int sessionIndex) async {
    final repo = ref.read(chatRepoProvider);
    final sessions = await repo.getByCharacterId(arg);
    final target = sessions.where((s) => s.sessionIndex == sessionIndex).firstOrNull;
    if (target != null) {
      await _saveCurrentSessionIndex(sessionIndex);
      state = AsyncData(ChatState(session: target));
    }
  }

  Future<void> createNewSession() async {
    final repo = ref.read(chatRepoProvider);
    final sessions = await repo.getByCharacterId(arg);
    final nextIndex = sessions.isEmpty ? 0 : (sessions.map((s) => s.sessionIndex).reduce((a, b) => a > b ? a : b) + 1);
    final charRepo = ref.read(characterRepoProvider);
    final character = await charRepo.getById(arg);
    final persona = await _resolvePersona();
    final sessionId = '${arg}_$nextIndex';
    final initialMessages = InitialMessageBuilder.build(
      character: character,
      persona: persona,
      sessionId: sessionId,
    );
    final newSession = ChatSession(
      id: sessionId,
      characterId: arg,
      sessionIndex: nextIndex,
      messages: initialMessages,
    );
    await repo.put(newSession);
    _invalidateHistory();
    await _saveCurrentSessionIndex(nextIndex);
    state = AsyncData(ChatState(session: newSession));
  }

  Future<List<ChatSession>> getSessions() async {
    final repo = ref.read(chatRepoProvider);
    return repo.getByCharacterId(arg);
  }

  Future<void> branchSession(int index) async {
    final current = state.value;
    if (current == null || current.session == null) return;
    if (index < 0 || index >= current.messages.length) return;

    final repo = ref.read(chatRepoProvider);
    final sessions = await repo.getByCharacterId(arg);

    int maxIdx = 0;
    for (final s in sessions) {
      if (s.sessionIndex > maxIdx) maxIdx = s.sessionIndex;
    }

    final newSession = ChatSession(
      id: '${arg}_${maxIdx + 1}',
      characterId: arg,
      sessionIndex: maxIdx + 1,
      messages: current.messages.sublist(0, index + 1),
      sessionVars: current.session!.sessionVars,
      updatedAt: currentTimestampSeconds(),
    );

    await repo.put(newSession);
    _invalidateHistory();
    await _saveCurrentSessionIndex(maxIdx + 1);
    state = AsyncData(ChatState(session: newSession));
  }

  Future<void> newSession() async {
    final repo = ref.read(chatRepoProvider);
    final sessions = await repo.getByCharacterId(arg);

    int maxIdx = 0;
    for (final s in sessions) {
      if (s.sessionIndex > maxIdx) maxIdx = s.sessionIndex;
    }

    final charRepo = ref.read(characterRepoProvider);
    final character = await charRepo.getById(arg);
    final persona = await _resolvePersona();

    final newIdx = maxIdx + 1;
    final sessionId = '${arg}_$newIdx';
    final initialMessages = InitialMessageBuilder.build(
      character: character,
      persona: persona,
      sessionId: sessionId,
    );

    final newSession = ChatSession(
      id: sessionId,
      characterId: arg,
      sessionIndex: newIdx,
      messages: initialMessages,
      updatedAt: currentTimestampSeconds(),
    );

    await repo.put(newSession);
    _invalidateHistory();
    await _saveCurrentSessionIndex(newIdx);
    state = AsyncData(ChatState(session: newSession));
  }

  Future<Persona?> _resolvePersona() async {
    final personaRepo = ref.read(personaRepoProvider);
    final personas = await personaRepo.getAll();
    final activePersonaId = ref.read(activePersonaIdProvider);
    final connections = ref.read(personaConnectionsProvider);
    return getEffectivePersona(
      personas, arg, null, activePersonaId, connections,
    );
  }

  Future<void> _saveCurrentSessionIndex(int index) async {
    final charRepo = ref.read(characterRepoProvider);
    final character = await charRepo.getById(arg);
    if (character != null) {
      await charRepo.put(character.copyWith(currentSessionIndex: index));
    }
  }

  void _invalidateHistory() => ref.invalidate(chatHistoryProvider);

  void abortGeneration() {
    _cancelToken?.cancel();
    _cancelToken = null;

    GenerationNotificationService.instance.onGenerationAborted();

    final current = state.value;
    if (current == null) return;

    if (current.streamingText.isNotEmpty) {
      final assistantMsg = ChatMessage(
        id: generateId(),
        role: 'assistant',
        content: current.streamingText,
        reasoning: current.streamingReasoning,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
      final finalMessages = [...current.messages, assistantMsg];
      final now = currentTimestampSeconds();
      final finalSession = current.session!.copyWith(messages: finalMessages, updatedAt: now);
      ref.read(chatRepoProvider).put(finalSession);
      _invalidateHistory();
      state = AsyncData(ChatState(session: finalSession));
    } else {
      state = AsyncData(current.copyWith(isGenerating: false));
    }
  }
}
