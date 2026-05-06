import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/llm/lorebook_vector_search.dart';
import '../../core/llm/memory_injection_service.dart';
import '../../core/llm/prompt_builder.dart';
import '../../core/llm/prompt_isolate.dart';
import '../../core/llm/sse_client.dart';
import '../../core/llm/stream_accumulator.dart';
import '../../core/llm/summary_service.dart';
import '../../core/models/chat_message.dart';
import '../../core/models/lorebook.dart';
import '../../core/state/active_selection_provider.dart';
import '../../core/state/db_provider.dart';
import '../../core/state/lorebook_provider.dart';
import 'chat_provider.dart';
import 'chat_state.dart';

class ChatGenerationService {
  final Ref _ref;

  ChatGenerationService(this._ref);

  Future<ChatState> generate({
    required ChatSession session,
    required String charId,
    required ChatState currentState,
    required void Function(ChatState) onStateUpdate,
    List<String>? previousSwipes,
    int previousSwipeId = 0,
    String? previousReasoning,
    String? previousGenTime,
    int? previousTokens,
  }) async {
    try {
      final charRepo = _ref.read(characterRepoProvider);
      final presetRepo = _ref.read(presetRepoProvider);
      final personaRepo = _ref.read(personaRepoProvider);
      final apiConfigRepo = _ref.read(apiConfigRepoProvider);

      final character = await charRepo.getById(charId);
      if (character == null) {
        return ChatState(session: session, isGenerating: false, error: 'Character not found');
      }

      final apiConfigs = await apiConfigRepo.getAll();
      if (apiConfigs.isEmpty) {
        return ChatState(session: session, isGenerating: false, error: 'No API config');
      }
      final apiConfig = apiConfigs.first;

      final activePresetId = _ref.read(activePresetIdProvider);
      final activePersonaId = _ref.read(activePersonaIdProvider);

      final presets = await presetRepo.getAll();
      final preset = activePresetId != null
          ? presets.where((p) => p.id == activePresetId).firstOrNull
          : (presets.isNotEmpty ? presets.first : null);

      final personas = await personaRepo.getAll();
      final persona = activePersonaId != null
          ? personas.where((p) => p.id == activePersonaId).firstOrNull
          : (personas.isNotEmpty ? personas.first : null);

      final vectorEntries = await _runVectorSearch(
        session.messages,
        session.messages.lastOrNull?.content ?? '',
      );

      final summaryService = _ref.read(summaryServiceProvider);
      final summaryContent = await summaryService.getSummary(session.id);

      final memoryService = _ref.read(memoryInjectionServiceProvider);
      final historyText = session.messages
          .where((m) => m.role == 'user' || m.role == 'assistant')
          .map((m) => m.content)
          .join('\n');
      final memoryResult = await memoryService.buildInjection(
        sessionId: session.id,
        historyText: historyText,
        messageCount: session.messages.length,
        summaryExcerpt: summaryContent,
      );

      final payload = PromptPayload(
        character: character,
        persona: persona,
        preset: preset,
        history: session.messages,
        apiConfig: apiConfig,
        sessionVars: session.sessionVars,
        globalVars: _ref.read(globalVarsProvider),
        lorebooks: await _ref.read(lorebookRepoProvider).getAll(),
        lorebookSettings: _ref.read(lorebookSettingsProvider),
        lorebookActivations: _ref.read(lorebookActivationsProvider),
        vectorEntries: vectorEntries,
        summaryContent: summaryContent,
        memoryContent: memoryResult.content.isNotEmpty ? memoryResult.content : null,
        memoryInjectionTarget: memoryResult.injectionTarget,
      );

      debugPrint('CHAT: building prompt for "${character.name}", history=${session.messages.length}, preset=${preset?.name ?? "none"}');

      final promptResult = await buildPromptInIsolate(payload);
      debugPrint('CHAT: prompt built, ${promptResult.messages.length} messages');

      Map<String, String>? pendingSessionVars;
      if (promptResult.sessionVars.isNotEmpty || promptResult.globalVars.isNotEmpty) {
        pendingSessionVars = promptResult.sessionVars;
        if (promptResult.globalVars.isNotEmpty) {
          updateGlobalVarsRef(_ref, promptResult.globalVars);
        }
      }

      final cancelToken = CancelToken();
      _ref.read(chatProvider(charId).notifier).setCancelToken(cancelToken);
      final accumulator = StreamAccumulator(
        tagStart: apiConfig.reasoningTagStart,
        tagEnd: apiConfig.reasoningTagEnd,
        hasInlineTags: apiConfig.reasoningTagStart != null,
      );

      final apiMessages = promptResult.messages
          .where((m) => m.content.trim().isNotEmpty)
          .map((m) => m.toApiMap())
          .toList();

      debugPrint('CHAT: sending ${apiMessages.length} messages to ${apiConfig.endpoint}');
      for (int i = 0; i < apiMessages.length; i++) {
        final m = apiMessages[i];
        final preview = m['content']!.length > 80 ? '${m['content']!.substring(0, 80)}...' : m['content'];
        debugPrint('  [$i] ${m['role']}: $preview');
      }

      final startGenTime = DateTime.now();
      final sseClient = SseClient();
      ChatState? finalState;

      await sseClient.streamChatCompletion(
        endpoint: apiConfig.endpoint,
        apiKey: apiConfig.apiKey,
        model: apiConfig.model,
        messages: apiMessages,
        maxTokens: apiConfig.maxTokens,
        temperature: apiConfig.temperature,
        topP: apiConfig.topP,
        stream: apiConfig.stream,
        cancelToken: cancelToken,
        requestReasoning: apiConfig.requestReasoning,
        onUpdate: (delta, reasoningDelta) {
          accumulator.consumeDelta(delta, reasoningDelta: reasoningDelta);
          onStateUpdate(ChatState(
            session: session,
            isGenerating: true,
            streamingText: accumulator.text,
            streamingReasoning: accumulator.reasoning.isNotEmpty ? accumulator.reasoning : null,
          ));
        },
        onComplete: (text, reasoning) {
          final elapsed = DateTime.now().difference(startGenTime).inMilliseconds;
          final timeStr = '${(elapsed / 1000).toStringAsFixed(1)}s';
          final tokenCount = (text.length / 4).round();
          finalState = _saveAssistantMessage(
            text, reasoning, session,
            pendingSessionVars: pendingSessionVars,
            genTime: timeStr, tokens: tokenCount,
            rawResponse: text,
            previousSwipes: previousSwipes,
            previousSwipeId: previousSwipeId,
            previousReasoning: previousReasoning,
            previousGenTime: previousGenTime,
            previousTokens: previousTokens,
          );
        },
        onError: (error) {
          final partialText = accumulator.text;
          if (partialText.isNotEmpty) {
            finalState = _saveAssistantMessage(partialText, null, session, pendingSessionVars: pendingSessionVars);
          } else {
            finalState = ChatState(session: session, isGenerating: false, error: error.toString());
          }
        },
      );

      return finalState ?? ChatState(session: session, isGenerating: false);
    } catch (e) {
      return ChatState(session: session, isGenerating: false, error: e.toString());
    }
  }

  ChatState _saveAssistantMessage(
    String text,
    String? reasoning,
    ChatSession currentSession, {
    Map<String, String>? pendingSessionVars,
    String? genTime,
    int? tokens,
    String? rawResponse,
    List<String>? previousSwipes,
    int previousSwipeId = 0,
    String? previousReasoning,
    String? previousGenTime,
    int? previousTokens,
  }) {
    List<String> swipes;
    int swipeId;

    if (previousSwipes != null && previousSwipes.isNotEmpty) {
      swipes = [...previousSwipes, text];
      swipeId = swipes.length - 1;
    } else {
      swipes = [text];
      swipeId = 0;
    }

    final assistantMsg = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toRadixString(36),
      role: 'assistant',
      content: text,
      reasoning: reasoning,
      genTime: genTime,
      tokens: tokens,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      swipes: swipes,
      swipeId: swipeId,
    );
    final finalMessages = [...currentSession.messages, assistantMsg];
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final sessionVars = pendingSessionVars ?? currentSession.sessionVars;
    final finalSession = currentSession.copyWith(
      messages: finalMessages,
      updatedAt: now,
      sessionVars: sessionVars,
    );
    _ref.read(chatRepoProvider).put(finalSession);
    return ChatState(session: finalSession, lastRawResponse: rawResponse);
  }

  Future<List<LorebookEntry>> _runVectorSearch(
    List<ChatMessage> history,
    String currentText,
  ) async {
    final settings = _ref.read(lorebookSettingsProvider);
    if (settings.searchType == 'keys') return [];

    final config = _ref.read(embeddingConfigProvider);
    if (config.endpoint.isEmpty) return [];

    final lorebooks = await _ref.read(lorebookRepoProvider).getAll();
    if (lorebooks.isEmpty) return [];

    final searchHistory = history
        .map((m) => ChatMessageForSearch(role: m.role, content: m.content))
        .toList();

    try {
      final searchService = _ref.read(lorebookVectorSearchProvider);
      final results = await searchService.search(searchHistory, currentText, lorebooks, settings, config);

      final entryMap = <String, LorebookEntry>{};
      for (final lb in lorebooks) {
        for (final entry in lb.entries) {
          entryMap[entry.id] = entry;
        }
      }

      return results.where((r) => entryMap.containsKey(r.entryId)).map((r) => entryMap[r.entryId]!.copyWith()).toList();
    } catch (e) {
      debugPrint('VECTOR SEARCH: failed: $e');
      return [];
    }
  }
}
