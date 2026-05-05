import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/llm/macro_engine.dart';
import '../../core/llm/prompt_builder.dart';
import '../../core/llm/prompt_isolate.dart';
import '../../core/llm/sse_client.dart';
import '../../core/llm/stream_accumulator.dart';
import '../../core/models/chat_message.dart';
import '../../core/state/active_selection_provider.dart';
import '../../core/state/db_provider.dart';
import '../../core/state/lorebook_provider.dart';

final chatProvider =
    AsyncNotifierProvider.family<ChatNotifier, ChatState, String>(
      ChatNotifier.new,
    );

class ChatState {
  final ChatSession? session;
  final bool isGenerating;
  final String streamingText;
  final String? streamingReasoning;
  final String? error;

  const ChatState({
    this.session,
    this.isGenerating = false,
    this.streamingText = '',
    this.streamingReasoning,
    this.error,
  });

  ChatState copyWith({
    ChatSession? session,
    bool? isGenerating,
    String? streamingText,
    String? streamingReasoning,
    String? error,
  }) {
    return ChatState(
      session: session ?? this.session,
      isGenerating: isGenerating ?? this.isGenerating,
      streamingText: streamingText ?? this.streamingText,
      streamingReasoning: streamingReasoning ?? this.streamingReasoning,
      error: error,
    );
  }

  List<ChatMessage> get messages => session?.messages ?? [];
}

class ChatNotifier extends FamilyAsyncNotifier<ChatState, String> {
  CancelToken? _cancelToken;
  Map<String, String>? _pendingSessionVars;

  @override
  Future<ChatState> build(String arg) async {
    final repo = ref.read(chatRepoProvider);
    final sessions = await repo.getByCharacterId(arg);
    if (sessions.isNotEmpty) {
      return ChatState(session: sessions.first);
    }

    final charRepo = ref.read(characterRepoProvider);
    final character = await charRepo.getById(arg);

    final personaRepo = ref.read(personaRepoProvider);
    final personas = await personaRepo.getAll();
    final activePersonaId = ref.read(activePersonaIdProvider);
    final persona = activePersonaId != null
        ? personas.where((p) => p.id == activePersonaId).firstOrNull
        : (personas.isNotEmpty ? personas.first : null);

    final initialMessages = <ChatMessage>[];
    if (character?.firstMes != null && character!.firstMes!.isNotEmpty) {
      final macroCtx = MacroContext(
        charName: character.name,
        charDescription: character.description,
        charScenario: character.scenario,
        charPersonality: character.personality,
        charMesExample: character.mesExample,
        userName: persona?.name ?? 'User',
        personaPrompt: persona?.prompt,
        charId: character.id,
        sessionId: '${arg}_0',
      );
      final resolved = replaceMacros(character.firstMes!, macroCtx);
      initialMessages.add(
        ChatMessage(
          id: _generateId(),
          role: 'assistant',
          content: resolved.text,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }

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

    await _generate(updatedSession);
  }

  Future<void> _generate(ChatSession session) async {
    try {
      final charRepo = ref.read(characterRepoProvider);
      final presetRepo = ref.read(presetRepoProvider);
      final personaRepo = ref.read(personaRepoProvider);
      final apiConfigRepo = ref.read(apiConfigRepoProvider);

      final character = await charRepo.getById(arg);
      if (character == null) {
        state = AsyncData(
          ChatState(
            session: session,
            isGenerating: false,
            error: 'Character not found',
          ),
        );
        return;
      }

      final apiConfigs = await apiConfigRepo.getAll();
      if (apiConfigs.isEmpty) {
        state = AsyncData(
          ChatState(
            session: session,
            isGenerating: false,
            error: 'No API config',
          ),
        );
        return;
      }
      final apiConfig = apiConfigs.first;

      final activePresetId = ref.read(activePresetIdProvider);
      final activePersonaId = ref.read(activePersonaIdProvider);

      final presets = await presetRepo.getAll();
      final preset = activePresetId != null
          ? presets.where((p) => p.id == activePresetId).firstOrNull
          : (presets.isNotEmpty ? presets.first : null);

      if (preset != null) {
        final hasChatHistory = preset.blocks.any(
          (b) => b.id == 'chat_history' || b.id == 'chatHistory',
        );
        debugPrint(
          'CHAT: preset "${preset.name}" loaded, blocks=${preset.blocks.length}, hasChatHistory=$hasChatHistory',
        );
        if (!hasChatHistory) {
          final last10 = preset.blocks.reversed
              .take(10)
              .map((b) => '${b.id}(${b.name})')
              .toList();
          debugPrint('CHAT: last 10 blocks: $last10');
        }
      }

      final personas = await personaRepo.getAll();
      final persona = activePersonaId != null
          ? personas.where((p) => p.id == activePersonaId).firstOrNull
          : (personas.isNotEmpty ? personas.first : null);

      final payload = PromptPayload(
        character: character,
        persona: persona,
        preset: preset,
        history: session.messages,
        apiConfig: apiConfig,
        sessionVars: session.sessionVars,
        globalVars: ref.read(globalVarsProvider),
        lorebooks: await ref.read(lorebookRepoProvider).getAll(),
        lorebookSettings: ref.read(lorebookSettingsProvider),
        lorebookActivations: ref.read(lorebookActivationsProvider),
      );

      debugPrint(
        'CHAT: building prompt for "${character.name}", '
        'history=${session.messages.length}, preset=${preset?.name ?? "none"}',
      );

      final promptResult = await buildPromptInIsolate(payload);

      debugPrint(
        'CHAT: prompt built, ${promptResult.messages.length} messages',
      );

      if (promptResult.sessionVars.isNotEmpty ||
          promptResult.globalVars.isNotEmpty) {
        _pendingSessionVars = promptResult.sessionVars;
        if (promptResult.globalVars.isNotEmpty) {
          updateGlobalVarsRef(ref, promptResult.globalVars);
        }
      }

      _cancelToken = CancelToken();

      final accumulator = StreamAccumulator(
        tagStart: apiConfig.reasoningTagStart,
        tagEnd: apiConfig.reasoningTagEnd,
        hasInlineTags: apiConfig.reasoningTagStart != null,
      );

      final apiMessages = promptResult.messages
          .where((m) => m.content.trim().isNotEmpty)
          .map((m) => m.toApiMap())
          .toList();
      debugPrint(
        'CHAT: sending ${apiMessages.length} messages to ${apiConfig.endpoint}',
      );
      for (int i = 0; i < apiMessages.length; i++) {
        final m = apiMessages[i];
        final preview = m['content']!.length > 80
            ? '${m['content']!.substring(0, 80)}...'
            : m['content'];
        debugPrint('  [$i] ${m['role']}: $preview');
      }

      final startGenTime = DateTime.now();
      final sseClient = SseClient();
      await sseClient.streamChatCompletion(
        endpoint: apiConfig.endpoint,
        apiKey: apiConfig.apiKey,
        model: apiConfig.model,
        messages: apiMessages,
        maxTokens: apiConfig.maxTokens,
        temperature: apiConfig.temperature,
        topP: apiConfig.topP,
        stream: apiConfig.stream,
        cancelToken: _cancelToken,
        requestReasoning: apiConfig.requestReasoning,
        onUpdate: (delta, reasoningDelta) {
          accumulator.consumeDelta(delta, reasoningDelta: reasoningDelta);
          state = AsyncData(
            ChatState(
              session: session,
              isGenerating: true,
              streamingText: accumulator.text,
              streamingReasoning: accumulator.reasoning.isNotEmpty
                  ? accumulator.reasoning
                  : null,
            ),
          );
        },
        onComplete: (text, reasoning) {
          final elapsed = DateTime.now()
              .difference(startGenTime)
              .inMilliseconds;
          final timeStr = '${(elapsed / 1000).toStringAsFixed(1)}s';
          final tokenCount = (text.length / 4).round();
          _saveAssistantMessage(
            text,
            reasoning,
            session,
            genTime: timeStr,
            tokens: tokenCount,
          );
        },
        onError: (error) {
          final partialText = accumulator.text;
          if (partialText.isNotEmpty) {
            _saveAssistantMessage(partialText, null, session);
          } else {
            state = AsyncData(
              ChatState(
                session: session,
                isGenerating: false,
                error: error.toString(),
              ),
            );
          }
        },
      );
    } catch (e) {
      state = AsyncData(
        ChatState(session: session, isGenerating: false, error: e.toString()),
      );
    }
  }

  void abortGeneration() {
    _cancelToken?.cancel();
    _cancelToken = null;

    final current = state.value;
    if (current == null) return;

    if (current.streamingText.isNotEmpty) {
      _saveAssistantMessage(
        current.streamingText,
        current.streamingReasoning,
        current.session!,
      );
    } else {
      state = AsyncData(current.copyWith(isGenerating: false));
    }
  }

  Future<void> clearChat() async {
    final current = state.value;
    if (current == null || current.session == null) return;

    final charRepo = ref.read(characterRepoProvider);
    final character = await charRepo.getById(arg);

    final personaRepo = ref.read(personaRepoProvider);
    final personas = await personaRepo.getAll();
    final activePersonaId = ref.read(activePersonaIdProvider);
    final persona = activePersonaId != null
        ? personas.where((p) => p.id == activePersonaId).firstOrNull
        : (personas.isNotEmpty ? personas.first : null);

    final initialMessages = <ChatMessage>[];
    if (character?.firstMes != null && character!.firstMes!.isNotEmpty) {
      final macroCtx = MacroContext(
        charName: character!.name,
        charDescription: character.description,
        charScenario: character.scenario,
        charPersonality: character.personality,
        charMesExample: character.mesExample,
        userName: persona?.name ?? 'User',
        personaPrompt: persona?.prompt,
        charId: character.id,
        sessionId: current.session!.id,
      );
      final resolved = replaceMacros(character.firstMes!, macroCtx);
      initialMessages.add(
        ChatMessage(
          id: _generateId(),
          role: 'assistant',
          content: resolved.text,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }

    final clearedSession = current.session!.copyWith(messages: initialMessages);
    await ref.read(chatRepoProvider).put(clearedSession);
    state = AsyncData(ChatState(session: clearedSession));
  }

  Future<void> editMessage(int index, String newContent) async {
    final current = state.value;
    if (current == null || current.session == null) return;
    if (index < 0 || index >= current.messages.length) return;

    final updated = current.messages[index].content != newContent
        ? current.messages[index].copyWith(content: newContent)
        : current.messages[index];
    final newMessages = List<ChatMessage>.from(current.messages);
    newMessages[index] = updated;

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

    final newMessages = List<ChatMessage>.from(current.messages)
      ..removeAt(index);

    final newSession = current.session!.copyWith(
      messages: newMessages,
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
    await ref.read(chatRepoProvider).put(newSession);
    state = AsyncData(ChatState(session: newSession));
  }

  Future<void> regenerateLastAssistant() async {
    final current = state.value;
    if (current == null || current.session == null || current.isGenerating)
      return;

    final messages = current.messages;
    if (messages.isEmpty) return;

    final trimmed = List<ChatMessage>.from(messages);
    if (trimmed.last.role == 'assistant') {
      trimmed.removeLast();
    }

    final trimmedSession = current.session!.copyWith(
      messages: trimmed,
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
    await ref.read(chatRepoProvider).put(trimmedSession);
    state = AsyncData(ChatState(session: trimmedSession, isGenerating: true));

    await _generate(trimmedSession);
  }

  Future<void> _saveAssistantMessage(
    String text,
    String? reasoning,
    ChatSession currentSession, {
    String? genTime,
    int? tokens,
  }) async {
    final assistantMsg = ChatMessage(
      id: _generateId(),
      role: 'assistant',
      content: text,
      reasoning: reasoning,
      genTime: genTime,
      tokens: tokens,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    final finalMessages = [...currentSession.messages, assistantMsg];
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final sessionVars = _pendingSessionVars ?? currentSession.sessionVars;
    _pendingSessionVars = null;
    final finalSession = currentSession.copyWith(
      messages: finalMessages,
      updatedAt: now,
      sessionVars: sessionVars,
    );
    await ref.read(chatRepoProvider).put(finalSession);
    state = AsyncData(ChatState(session: finalSession));
  }

  Future<void> toggleMessageHidden(int index) async {
    final current = state.value;
    if (current == null || current.session == null) return;
    if (index < 0 || index >= current.messages.length) return;

    final msg = current.messages[index];
    final updated = msg.copyWith(isHidden: !msg.isHidden);

    final newMessages = List<ChatMessage>.from(current.messages);
    newMessages[index] = updated;

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
      if (m.isHidden) {
        changed = true;
        return m.copyWith(isHidden: false);
      }
      return m;
    }).toList();

    if (!changed) {
      return;
    }

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

    if (current.isGenerating) {
      abortGeneration();
    }

    final repo = ref.read(chatRepoProvider);
    final sessions = await repo.getByCharacterId(arg);

    int maxIdx = 0;
    for (final s in sessions) {
      if (s.sessionIndex > maxIdx) maxIdx = s.sessionIndex;
    }

    final newSessionIndex = maxIdx + 1;
    final newSessionId = '${arg}_$newSessionIndex';

    final branchedMessages = current.messages.sublist(0, index + 1);

    final newSession = ChatSession(
      id: newSessionId,
      characterId: arg,
      sessionIndex: newSessionIndex,
      messages: branchedMessages,
      sessionVars: current.session!.sessionVars,
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );

    await repo.put(newSession);
    state = AsyncData(ChatState(session: newSession));
  }

  String _generateId() {
    return DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  }
}
