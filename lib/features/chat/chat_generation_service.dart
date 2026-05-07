import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/llm/prompt_isolate.dart';
import '../../core/llm/prompt_payload_builder.dart';
import '../../core/llm/sse_client.dart';
import '../../core/llm/stream_accumulator.dart';
import '../../core/models/chat_message.dart';
import '../../core/state/active_selection_provider.dart';
import '../../core/utils/id_generator.dart';
import '../../core/utils/time_helpers.dart';
import '../../core/state/db_provider.dart';
import '../image_gen/image_gen_provider.dart';
import '../image_gen/services/image_gen_service.dart';
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
    List<Map<String, dynamic>>? previousSwipesMeta,
    String? guidanceText,
  }) async {
    try {
      final builder = _ref.read(promptPayloadBuilderProvider);
      final payload = await builder.buildFromSession(
        charId: charId,
        session: session,
        guidanceText: guidanceText,
      );

      final apiConfig = payload.apiConfig;

      debugPrint('CHAT: building prompt for "${payload.character.name}", history=${session.messages.length}, preset=${payload.preset?.name ?? "none"}');

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
      final coverage = payload.memoryCoverage;

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
        reasoningEffort: apiConfig.reasoningEffort,
        omitTemperature: apiConfig.omitTemperature,
        omitTopP: apiConfig.omitTopP,
        omitReasoning: apiConfig.omitReasoning,
        omitReasoningEffort: apiConfig.omitReasoningEffort,
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
            previousSwipesMeta: previousSwipesMeta,
            guidanceText: guidanceText,
            memoryCoverage: coverage,
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

  Future<void> processImageTags({
    required ChatState currentState,
    required String charId,
    required void Function(ChatState) onStateUpdate,
  }) async {
    final session = currentState.session;
    if (session == null) return;

    final imgGenSettingsAsync = _ref.read(imageGenSettingsProvider);
    final imgGenSettings = imgGenSettingsAsync.value;
    if (imgGenSettings == null || !imgGenSettings.enabled) return;

    final lastIdx = session.messages.length - 1;
    if (lastIdx < 0) return;
    final lastMsg = session.messages[lastIdx];
    if (lastMsg.role != 'assistant') return;

    final service = _ref.read(imageGenSettingsProvider.notifier).getService();
    if (!service.hasImageGenTags(lastMsg.content)) return;

    final apiConfigs = await _ref.read(apiConfigRepoProvider).getAll();
    if (apiConfigs.isEmpty) return;
    final apiConfig = apiConfigs.first;

    final charRepo = _ref.read(characterRepoProvider);
    final character = await charRepo.getById(charId);

    final personaRepo = _ref.read(personaRepoProvider);
    final personas = await personaRepo.getAll();
    final connections = _ref.read(personaConnectionsProvider);
    final activePersonaId = _ref.read(activePersonaIdProvider);
    final persona = getEffectivePersona(
      personas, charId, session.id, activePersonaId, connections,
    );

    final recentContexts = _collectRecentImageContexts(session.messages);

    final updatedContent = await service.processMessageImages(
      text: lastMsg.content,
      settings: imgGenSettings,
      llmEndpoint: apiConfig.endpoint,
      llmApiKey: apiConfig.apiKey,
      llmModel: apiConfig.model,
      character: character,
      persona: persona,
      recentImageContexts: recentContexts,
      onUpdate: (updatedText) {
        final newMessages = List<ChatMessage>.from(session.messages);
        newMessages[lastIdx] = lastMsg.copyWith(content: updatedText);
        final updatedSession = session.copyWith(
          messages: newMessages,
          updatedAt: currentTimestampSeconds(),
        );
        onStateUpdate(ChatState(session: updatedSession));
      },
    );

    final newMessages = List<ChatMessage>.from(session.messages);
    newMessages[lastIdx] = lastMsg.copyWith(content: updatedContent);
    final finalSession = session.copyWith(
      messages: newMessages,
      updatedAt: currentTimestampSeconds(),
    );
    _ref.read(chatRepoProvider).put(finalSession);
    onStateUpdate(ChatState(session: finalSession));
  }

  List<String> _collectRecentImageContexts(List<ChatMessage> messages) {
    final contexts = <String>[];
    for (int i = messages.length - 1; i >= 0 && contexts.length < 3; i--) {
      final paths = ImageGenService.extractImageResultPaths(messages[i].content);
      contexts.addAll(paths);
    }
    return contexts.reversed.toList();
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
    List<Map<String, dynamic>>? previousSwipesMeta,
    String? guidanceText,
    Map<String, dynamic> memoryCoverage = const {},
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

    final currentSwipeMeta = <String, dynamic>{
      'genTime': genTime,
      'reasoning': reasoning,
      'tokens': tokens,
    };
    if (guidanceText != null && guidanceText.isNotEmpty) {
      currentSwipeMeta['guidanceText'] = guidanceText;
      currentSwipeMeta['guidanceType'] = 'GENERATION';
    }

    List<Map<String, dynamic>> swipesMeta;
    if (previousSwipesMeta != null && previousSwipesMeta.isNotEmpty) {
      swipesMeta = [...previousSwipesMeta, currentSwipeMeta];
    } else if (previousSwipes != null && previousSwipes.isNotEmpty) {
      final prevMeta = <String, dynamic>{
        'genTime': previousGenTime,
        'reasoning': previousReasoning,
        'tokens': previousTokens,
      };
      swipesMeta = [prevMeta, currentSwipeMeta];
    } else {
      swipesMeta = [currentSwipeMeta];
    }

    final assistantMsg = ChatMessage(
      id: generateId(),
      role: 'assistant',
      content: text,
      reasoning: reasoning,
      genTime: genTime,
      tokens: tokens,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      swipes: swipes,
      swipeId: swipeId,
      swipesMeta: swipesMeta,
      memoryCoverage: memoryCoverage,
    );
    final finalMessages = [...currentSession.messages, assistantMsg];
    final now = currentTimestampSeconds();
    final sessionVars = pendingSessionVars ?? currentSession.sessionVars;
    final finalSession = currentSession.copyWith(
      messages: finalMessages,
      updatedAt: now,
      sessionVars: sessionVars,
    );
    _ref.read(chatRepoProvider).put(finalSession);
    return ChatState(session: finalSession, lastRawResponse: rawResponse);
  }
}
