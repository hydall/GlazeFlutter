import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/chat_message.dart';
import '../../core/models/persona.dart';
import '../../core/state/active_selection_provider.dart';
import '../../core/state/db_provider.dart';
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

  Future<void> sendMessage(String text) async {
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
    state = AsyncData(ChatState(session: updatedSession, isGenerating: true));

    final service = ChatGenerationService(ref);
    final result = await service.generate(
      session: updatedSession,
      charId: arg,
      currentState: current,
      onStateUpdate: (s) => state = AsyncData(s),
    );
    state = AsyncData(result);
  }

  Future<void> regenerateLastAssistant() async {
    final current = state.value;
    if (current == null || current.session == null || current.isGenerating) return;

    final trimmed = List<ChatMessage>.from(current.messages);
    if (trimmed.last.role == 'assistant') trimmed.removeLast();

    final trimmedSession = current.session!.copyWith(
      messages: trimmed,
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
    await ref.read(chatRepoProvider).put(trimmedSession);
    state = AsyncData(ChatState(session: trimmedSession, isGenerating: true));

    final service = ChatGenerationService(ref);
    final result = await service.generate(
      session: trimmedSession,
      charId: arg,
      currentState: current,
      onStateUpdate: (s) => state = AsyncData(s),
    );
    state = AsyncData(result);
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
    state = AsyncData(ChatState(session: newSession));
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
    state = AsyncData(ChatState(session: newSession));
  }

  Future<Persona?> _resolvePersona() async {
    final personaRepo = ref.read(personaRepoProvider);
    final personas = await personaRepo.getAll();
    final activePersonaId = ref.read(activePersonaIdProvider);
    return activePersonaId != null
        ? personas.where((p) => p.id == activePersonaId).firstOrNull
        : (personas.isNotEmpty ? personas.first : null);
  }

  String _generateId() => DateTime.now().millisecondsSinceEpoch.toRadixString(36);

  void abortGeneration() {
    _cancelToken?.cancel();
    _cancelToken = null;

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
      state = AsyncData(ChatState(session: finalSession));
    } else {
      state = AsyncData(current.copyWith(isGenerating: false));
    }
  }
}
