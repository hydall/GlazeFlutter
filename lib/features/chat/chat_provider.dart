import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/chat_message.dart';
import '../../core/models/persona.dart';
import '../../core/services/generation_notification_service.dart';
import '../../core/state/active_selection_provider.dart';
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
    if (sessions.isNotEmpty) return ChatState(session: sessions.first);

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
      id: _generateId(),
      role: 'user',
      content: text,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    final updatedMessages = [...current.messages, userMsg];
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final updatedSession = current.session!.copyWith(
      messages: updatedMessages,
      updatedAt: now,
    );

    await ref.read(chatRepoProvider).put(updatedSession);
    _invalidateHistory();
    state = AsyncData(ChatState(session: updatedSession, isGenerating: true));

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

    final charRepo = ref.read(characterRepoProvider);
    final character = await charRepo.getById(arg);
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
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
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
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
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
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
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
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
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
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
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
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
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

    final updated = msg.copyWith(
      swipeId: swipeId,
      content: msg.swipes[swipeId],
    );

    final newMessages = List<ChatMessage>.from(current.messages);
    newMessages[messageIndex] = updated;

    final newSession = current.session!.copyWith(
      messages: newMessages,
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
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
      state = AsyncData(ChatState(session: target));
    }
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
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );

    await repo.put(newSession);
    _invalidateHistory();
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
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );

    await repo.put(newSession);
    _invalidateHistory();
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

  String _generateId() => DateTime.now().millisecondsSinceEpoch.toRadixString(36);

  void _invalidateHistory() => ref.invalidate(chatHistoryProvider);

  void abortGeneration() {
    _cancelToken?.cancel();
    _cancelToken = null;

    GenerationNotificationService.instance.onGenerationAborted();

    final current = state.value;
    if (current == null) return;

    if (current.streamingText.isNotEmpty) {
      final assistantMsg = ChatMessage(
        id: _generateId(),
        role: 'assistant',
        content: current.streamingText,
        reasoning: current.streamingReasoning,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
      final finalMessages = [...current.messages, assistantMsg];
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final finalSession = current.session!.copyWith(messages: finalMessages, updatedAt: now);
      ref.read(chatRepoProvider).put(finalSession);
      _invalidateHistory();
      state = AsyncData(ChatState(session: finalSession));
    } else {
      state = AsyncData(current.copyWith(isGenerating: false));
    }
  }
}
