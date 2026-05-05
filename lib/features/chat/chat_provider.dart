import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/chat_message.dart';
import '../../core/llm/sse_client.dart';
import '../../core/llm/stream_accumulator.dart';
import '../../core/llm/prompt_builder.dart';
import '../../core/llm/prompt_isolate.dart';
import '../../core/state/active_selection_provider.dart';
import '../../core/state/db_provider.dart';

final chatProvider =
    AsyncNotifierProvider.family<ChatNotifier, ChatState, String>(
        ChatNotifier.new);

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

    final initialMessages = <ChatMessage>[];
    if (character?.firstMes != null && character!.firstMes!.isNotEmpty) {
      initialMessages.add(ChatMessage(
        id: _generateId(),
        role: 'assistant',
        content: character.firstMes!,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ));
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
    state = AsyncData(ChatState(session: updatedSession, isGenerating: true));

    try {
      final charRepo = ref.read(characterRepoProvider);
      final presetRepo = ref.read(presetRepoProvider);
      final personaRepo = ref.read(personaRepoProvider);
      final apiConfigRepo = ref.read(apiConfigRepoProvider);

      final character = await charRepo.getById(arg);
      if (character == null) {
        state = AsyncData(current.copyWith(isGenerating: false, error: 'Character not found'));
        return;
      }

      final apiConfigs = await apiConfigRepo.getAll();
      if (apiConfigs.isEmpty) {
        state = AsyncData(current.copyWith(isGenerating: false, error: 'No API config'));
        return;
      }
      final apiConfig = apiConfigs.first;

      final activePresetId = ref.read(activePresetIdProvider);
      final activePersonaId = ref.read(activePersonaIdProvider);

      final presets = await presetRepo.getAll();
      final preset = activePresetId != null
          ? presets.where((p) => p.id == activePresetId).firstOrNull
          : (presets.isNotEmpty ? presets.first : null);

      final personas = await personaRepo.getAll();
      final persona = activePersonaId != null
          ? personas.where((p) => p.id == activePersonaId).firstOrNull
          : (personas.isNotEmpty ? personas.first : null);

      final payload = PromptPayload(
        character: character,
        persona: persona,
        preset: preset,
        history: updatedMessages,
        apiConfig: apiConfig,
        sessionVars: current.session?.sessionVars ?? {},
        globalVars: ref.read(globalVarsProvider),
      );

      debugPrint('CHAT: building prompt for "${character.name}", '
          'history=${updatedMessages.length}, preset=${preset?.name ?? "none"}');

      final promptResult = await buildPromptInIsolate(payload);

      debugPrint('CHAT: prompt built, ${promptResult.messages.length} messages');

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

      final apiMessages = promptResult.messages.map((m) => m.toApiMap()).toList();
      debugPrint('CHAT: sending ${apiMessages.length} messages to ${apiConfig.endpoint}');
      for (int i = 0; i < apiMessages.length; i++) {
        final m = apiMessages[i];
        final preview = m['content']!.length > 80
            ? '${m['content']!.substring(0, 80)}...'
            : m['content'];
        debugPrint('  [$i] ${m['role']}: $preview');
      }

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
          state = AsyncData(ChatState(
            session: updatedSession,
            isGenerating: true,
            streamingText: accumulator.text,
            streamingReasoning: accumulator.reasoning.isNotEmpty
                ? accumulator.reasoning
                : null,
          ));
        },
        onComplete: (text, reasoning) {
          _saveAssistantMessage(text, reasoning, updatedSession);
        },
        onError: (error) {
          final partialText = accumulator.text;
          if (partialText.isNotEmpty) {
            _saveAssistantMessage(partialText, null, updatedSession);
          } else {
            state = AsyncData(current.copyWith(isGenerating: false, error: error.toString()));
          }
        },
      );
    } catch (e) {
      state = AsyncData(current.copyWith(isGenerating: false, error: e.toString()));
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

    final initialMessages = <ChatMessage>[];
    if (character?.firstMes != null && character!.firstMes!.isNotEmpty) {
      initialMessages.add(ChatMessage(
        id: _generateId(),
        role: 'assistant',
        content: character.firstMes!,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ));
    }

    final clearedSession = current.session!.copyWith(messages: initialMessages);
    await ref.read(chatRepoProvider).put(clearedSession);
    state = AsyncData(ChatState(session: clearedSession));
  }

  Future<void> _saveAssistantMessage(
    String text,
    String? reasoning,
    ChatSession currentSession,
  ) async {
    final assistantMsg = ChatMessage(
      id: _generateId(),
      role: 'assistant',
      content: text,
      reasoning: reasoning,
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

  String _generateId() {
    return DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  }
}
