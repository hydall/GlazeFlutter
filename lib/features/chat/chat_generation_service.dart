import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/llm/prompt_isolate.dart';
import '../../core/llm/prompt_payload_builder.dart';
import '../../core/llm/sse_client.dart';
import '../../core/llm/stream_accumulator.dart';
import '../../core/llm/tokenizer.dart';
import '../../core/models/api_config.dart';
import '../../core/models/chat_message.dart';
import '../../core/state/active_selection_provider.dart';
import '../../core/utils/id_generator.dart';
import '../../core/utils/time_helpers.dart';
import '../../core/state/db_provider.dart';
import '../../shared/widgets/glaze_toast.dart';
import '../image_gen/image_gen_provider.dart';
import '../settings/api_list_provider.dart';
import '../image_gen/services/image_gen_service.dart';
import 'chat_provider.dart';
import 'chat_state.dart';
import 'state/cached_token_breakdown.dart';

final chatGenerationServiceProvider = Provider<ChatGenerationService>((ref) {
  return ChatGenerationService(ref);
});

class ChatGenerationService {
  final Ref _ref;

  ChatGenerationService(this._ref);

  void _persist(ChatSession session) {
    _ref.read(chatRepoProvider).put(session).catchError((Object e) {
      debugPrint('[ChatGenerationService] failed to persist session: $e');
    });
  }

  Future<ChatState> generate({
    required ChatSession session,
    ChatSession? saveSession,
    required String charId,
    required int genId,
    required ChatState currentState,
    required void Function(ChatState) onStateUpdate,
    required bool Function() isAborted,
    List<String>? previousSwipes,
    int previousSwipeId = 0,
    String? previousReasoning,
    String? previousGenTime,
    int? previousTokens,
    List<Map<String, dynamic>>? previousSwipesMeta,
    String? guidanceText,
    String? regenTargetId,
  }) async {
    debugPrint('[gen] generate() START charId=$charId genId=$genId');
    final vsi = currentState.visibleStartIndex;
    final cancelToken = CancelToken();
    _ref.read(chatProvider(charId).notifier).setCancelToken(cancelToken, genId: genId);
    if (cancelToken.isCancelled) {
      return ChatState(session: saveSession ?? session, isGenerating: false, visibleStartIndex: vsi);
    }
    try {
      debugPrint('[gen] building payload...');
      final builder = _ref.read(promptPayloadBuilderProvider);
      final payload = await builder.buildFromSession(
        charId: charId,
        session: session,
        guidanceText: guidanceText,
        shouldAbort: isAborted,
        cancelToken: cancelToken,
      );
      if (isAborted()) {
        return ChatState(
          session: saveSession ?? session,
          isGenerating: false,
          visibleStartIndex: vsi,
        );
      }
      debugPrint('[gen] payload built, building prompt in isolate...');

      final apiConfig = payload.apiConfig;

      final promptResult = await buildPromptInIsolate(payload);
      if (isAborted()) {
        return ChatState(
          session: saveSession ?? session,
          isGenerating: false,
          visibleStartIndex: vsi,
        );
      }
      debugPrint('[gen] prompt built, messages=${promptResult.messages.length}, totalTokens=${promptResult.breakdown.totalTokens}');

      _ref.read(cachedTokenBreakdownProvider(charId).notifier).state =
          promptResult.breakdown;

      Map<String, String>? pendingSessionVars;
      if (promptResult.sessionVars.isNotEmpty || promptResult.globalVars.isNotEmpty) {
        pendingSessionVars = promptResult.sessionVars;
        if (promptResult.globalVars.isNotEmpty) {
          updateGlobalVarsRef(_ref, promptResult.globalVars);
        }
      }

      if (isAborted()) return ChatState(session: saveSession ?? session, isGenerating: false, visibleStartIndex: vsi);
      final preset = payload.preset;
      const defaultTagStart = '<think>';
      const defaultTagEnd = '</think>';
      final reasoningTagStart = (preset?.reasoningStart?.isNotEmpty == true)
          ? preset!.reasoningStart!
          : (apiConfig.reasoningTagStart?.isNotEmpty == true)
              ? apiConfig.reasoningTagStart!
              : defaultTagStart;
      final reasoningTagEnd = (preset?.reasoningEnd?.isNotEmpty == true)
          ? preset!.reasoningEnd!
          : (apiConfig.reasoningTagEnd?.isNotEmpty == true)
              ? apiConfig.reasoningTagEnd!
              : defaultTagEnd;

      // Enable inline tag parsing when tag markers are available. Some providers
      // still emit <think>...</think> even if preset.reasoningEnabled is false;
      // in that case we still must route the content into reasoning instead of
      // leaking it into visible assistant text.
      final hasInlineTags =
          reasoningTagStart.isNotEmpty && reasoningTagEnd.isNotEmpty;

      final accumulator = StreamAccumulator(
        tagStart: reasoningTagStart,
        tagEnd: reasoningTagEnd,
        hasInlineTags: hasInlineTags,
      );

      final apiMessages = promptResult.messages
          .where((m) => m.content.trim().isNotEmpty)
          .map((m) => m.toApiMap())
          .toList();


      final startGenTime = DateTime.now();
      final sseClient = SseClient();
      ChatState? finalState;
      final coverage = payload.memoryCoverage;
      final triggeredLorebooks = promptResult.triggeredLorebooks;
      final triggeredMemories = promptResult.triggeredMemories;

      debugPrint('[gen] starting SSE stream to ${apiConfig.endpoint} model=${apiConfig.model}');

      bool frameScheduled = false;

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
          if (isAborted()) return;
          accumulator.consumeDelta(delta, reasoningDelta: reasoningDelta);
          if (!frameScheduled) {
            frameScheduled = true;
            SchedulerBinding.instance.scheduleFrameCallback((_) {
              frameScheduled = false;
              if (isAborted()) return;
              _ref.read(streamingStateProvider(charId).notifier).state =
                  StreamingState(
                    text: accumulator.text.trimLeft(),
                    reasoning: accumulator.reasoning.isNotEmpty
                        ? accumulator.reasoning
                        : null,
                  );
            });
          }
        },
        onComplete: (text, reasoning, {rawResponseJson}) {
          if (isAborted()) return;
          if (!apiConfig.stream &&
              accumulator.text.isEmpty &&
              accumulator.reasoning.isEmpty &&
              (text.isNotEmpty || (reasoning != null && reasoning.isNotEmpty))) {
            accumulator.consumeDelta(text, reasoningDelta: reasoning);
          }
          var finalText = accumulator.text.trimLeft();
          var finalReasoning = accumulator.reasoning.isNotEmpty ? accumulator.reasoning : reasoning;

          // Belt-and-suspenders sanitization: remove any leaked reasoning tag markers
          // from the final visible text and reasoning. This catches cases where the model
          // (especially on non-streaming path) emits an unbalanced stray </think> or the
          // configured closing tag "from thin air". The markers are control tokens and
          // must never appear in the persisted assistant message content or reasoning field.
          finalText = _sanitizeReasoningMarkers(finalText, reasoningTagStart, reasoningTagEnd);
          if (finalReasoning != null && finalReasoning.isNotEmpty) {
            finalReasoning = _sanitizeReasoningMarkers(finalReasoning, reasoningTagStart, reasoningTagEnd);
          }

          final isAllReasoning = finalText.isEmpty && finalReasoning != null && finalReasoning.isNotEmpty;
          final elapsed = DateTime.now().difference(startGenTime).inMilliseconds;
          final timeStr = '${(elapsed / 1000).toStringAsFixed(1)}s';
          final tokenCount = estimateTokens(finalText);
          finalState = _saveAssistantMessage(
            finalText, finalReasoning, saveSession ?? session,
            isAborted: isAborted,
            pendingSessionVars: pendingSessionVars,
            genTime: timeStr, tokens: tokenCount,
            rawResponse: rawResponseJson ?? text,
            previousSwipes: previousSwipes,
            previousSwipeId: previousSwipeId,
            previousReasoning: previousReasoning,
            previousGenTime: previousGenTime,
            previousTokens: previousTokens,
            previousSwipesMeta: previousSwipesMeta,
            guidanceText: guidanceText,
            memoryCoverage: coverage,
            isAllReasoning: isAllReasoning,
            triggeredLorebooks: triggeredLorebooks,
            triggeredMemories: triggeredMemories,
            regenTargetId: regenTargetId,
            visibleStartIndex: vsi,
          );
        },
        onError: (error) {
          final isCancelled = (error is DioException && error.type == DioExceptionType.cancel)
              || cancelToken.isCancelled
              || isAborted();
          if (isCancelled) {
            finalState = ChatState(session: session, isGenerating: false, visibleStartIndex: vsi);
          } else if (regenTargetId != null && saveSession != null) {
            finalState = _saveRegenError(error.toString(), saveSession, regenTargetId, pendingSessionVars: pendingSessionVars, visibleStartIndex: vsi);
          } else {
            finalState = _saveErrorMessage(error.toString(), session, pendingSessionVars: pendingSessionVars, visibleStartIndex: vsi);
          }
        },
      );

      return finalState ?? ChatState(session: session, isGenerating: false, visibleStartIndex: vsi);
    } catch (e) {
      if (isAborted()) return ChatState(session: session, isGenerating: false, visibleStartIndex: vsi);
      if (regenTargetId != null && saveSession != null) {
        return _saveRegenError(e.toString(), saveSession, regenTargetId, visibleStartIndex: vsi);
      }
      return _saveErrorMessage(e.toString(), session, visibleStartIndex: vsi);
    }
  }

  Future<void> processImageTags({
    required ChatState currentState,
    required String charId,
    CancelToken? cancelToken,
    required void Function(ChatState) onStateUpdate,
  }) async {
    final session = currentState.session;
    if (session == null) return;

    final imgGenSettingsAsync = _ref.read(imageGenSettingsProvider);
    if (imgGenSettingsAsync.isLoading) {
      final imgGenSettings = await _ref.read(imageGenSettingsProvider.future);
      if (!imgGenSettings.enabled) return;
    } else {
      final imgGenSettings = imgGenSettingsAsync.value;
      if (imgGenSettings == null || !imgGenSettings.enabled) return;
    }
    final imgGenSettings = await _ref.read(imageGenSettingsProvider.future);

    final lastIdx = session.messages.length - 1;
    if (lastIdx < 0) return;
    final lastMsg = session.messages[lastIdx];
    if (lastMsg.role != 'assistant') return;

    final notifier = _ref.read(imageGenSettingsProvider.notifier);
    final service = await notifier.getServiceAsync();
    if (!service.hasImageGenTags(lastMsg.content)) return;

    final apiConfigSync = _ref.read(activeApiConfigProvider);
    final ApiConfig apiConfig;
    if (apiConfigSync != null) {
      apiConfig = apiConfigSync;
    } else {
      final apiList = await _ref.read(apiListProvider.future);
      if (apiList.isEmpty) return;
      final activeId = _ref.read(activeApiPresetIdProvider);
      apiConfig = activeId != null
          ? apiList.firstWhere((c) => c.id == activeId, orElse: () => apiList.first)
          : apiList.first;
    }

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

    debugPrint('[IMGGEN] → setting isGeneratingImage=true');
    onStateUpdate(currentState.copyWith(session: session, isGeneratingImage: true));

    String updatedContent;
    try {
      updatedContent = await service.processMessageImages(
        text: lastMsg.content,
        settings: imgGenSettings,
        llmEndpoint: apiConfig.endpoint,
        llmApiKey: apiConfig.apiKey,
        llmModel: apiConfig.model,
        character: character,
        persona: persona,
        recentImageContexts: recentContexts,
        cancelToken: cancelToken,
        onUpdate: (updatedText) {
          final newMessages = List<ChatMessage>.from(session.messages);
          final swipeIdx = lastMsg.swipeId;
          final updatedSwipes = lastMsg.swipes.isNotEmpty && swipeIdx >= 0 && swipeIdx < lastMsg.swipes.length
              ? (List<String>.from(lastMsg.swipes)..[swipeIdx] = updatedText)
              : lastMsg.swipes;
          newMessages[lastIdx] = lastMsg.copyWith(content: updatedText, swipes: updatedSwipes);
          final updatedSession = session.copyWith(
            messages: newMessages,
            updatedAt: currentTimestampSeconds(),
          );
          onStateUpdate(currentState.copyWith(session: updatedSession));
        },
        onError: (error) {
          debugPrint('[IMGGEN] onError: $error');
          GlazeToast.showWithoutContext('Image gen: $error', isError: true, duration: 4000);
        },
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        onStateUpdate(currentState.copyWith(session: session, isGeneratingImage: false));
        return;
      }
      onStateUpdate(currentState.copyWith(session: session, isGeneratingImage: false));
      rethrow;
    } catch (e) {
      onStateUpdate(currentState.copyWith(session: session, isGeneratingImage: false));
      rethrow;
    }

    if (cancelToken?.isCancelled == true) {
      var cancelContent = updatedContent;
      int idx = 0;
      while (service.hasImageGenTags(cancelContent)) {
        cancelContent = service.replaceTagWithError(cancelContent, idx, 'Cancelled by user');
        idx++;
      }
      final newMessages = List<ChatMessage>.from(session.messages);
      final cancelSwipeIdx = lastMsg.swipeId;
      final cancelSwipes = lastMsg.swipes.isNotEmpty && cancelSwipeIdx >= 0 && cancelSwipeIdx < lastMsg.swipes.length
          ? (List<String>.from(lastMsg.swipes)..[cancelSwipeIdx] = cancelContent)
          : lastMsg.swipes;
      newMessages[lastIdx] = lastMsg.copyWith(content: cancelContent, swipes: cancelSwipes);
      final finalSession = session.copyWith(messages: newMessages, updatedAt: currentTimestampSeconds());
      onStateUpdate(currentState.copyWith(session: finalSession, isGeneratingImage: false));
      return;
    }

    final newMessages = List<ChatMessage>.from(session.messages);
    final finalSwipeIdx = lastMsg.swipeId;
    final finalSwipes = lastMsg.swipes.isNotEmpty && finalSwipeIdx >= 0 && finalSwipeIdx < lastMsg.swipes.length
        ? (List<String>.from(lastMsg.swipes)..[finalSwipeIdx] = updatedContent)
        : lastMsg.swipes;
    newMessages[lastIdx] = lastMsg.copyWith(content: updatedContent, swipes: finalSwipes);
    final finalSession = session.copyWith(
      messages: newMessages,
      updatedAt: currentTimestampSeconds(),
    );
    await _ref.read(chatRepoProvider).put(finalSession);
    onStateUpdate(currentState.copyWith(session: finalSession, isGeneratingImage: false));
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
    required bool Function() isAborted,
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
    bool isAllReasoning = false,
    List<TriggeredEntry> triggeredLorebooks = const [],
    List<TriggeredEntry> triggeredMemories = const [],
    String? regenTargetId,
    int visibleStartIndex = 0,
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
      swipesMeta = List<Map<String, dynamic>>.generate(
        previousSwipes.length,
        (i) => i == previousSwipeId ? prevMeta : {},
      );
      swipesMeta.add(currentSwipeMeta);
    } else {
      swipesMeta = [currentSwipeMeta];
    }

    if (regenTargetId != null) {
      if (isAborted()) {
        return ChatState(session: currentSession, isGenerating: false, visibleStartIndex: visibleStartIndex);
      }
      final idx = currentSession.messages.indexWhere((m) => m.id == regenTargetId);
      if (idx >= 0) {
        final updated = currentSession.messages[idx].copyWith(
          content: text,
          reasoning: reasoning,
          isAllReasoning: isAllReasoning,
          isError: false,
          isTyping: false,
          genTime: genTime,
          tokens: tokens,
          swipes: swipes,
          swipeId: swipeId,
          swipesMeta: swipesMeta,
          swipeDirection: 'right',
          memoryCoverage: memoryCoverage,
          triggeredLorebooks: triggeredLorebooks,
          triggeredMemories: triggeredMemories,
        );
        final updatedMessages = [...currentSession.messages];
        updatedMessages[idx] = updated;
        final finalSession = currentSession.copyWith(
          messages: updatedMessages,
          updatedAt: currentTimestampSeconds(),
          sessionVars: pendingSessionVars ?? currentSession.sessionVars,
        );
        _persist(finalSession);
        return ChatState(session: finalSession, lastRawResponse: rawResponse, regenTargetId: regenTargetId, visibleStartIndex: visibleStartIndex);
      }
    }

    if (isAborted()) {
      return ChatState(session: currentSession, isGenerating: false, visibleStartIndex: visibleStartIndex);
    }

    final assistantMsg = ChatMessage(
      id: generateId(),
      role: 'assistant',
      content: text,
      reasoning: reasoning,
      isAllReasoning: isAllReasoning,
      genTime: genTime,
      tokens: tokens,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      swipes: swipes,
      swipeId: swipeId,
      swipesMeta: swipesMeta,
      memoryCoverage: memoryCoverage,
      triggeredLorebooks: triggeredLorebooks,
      triggeredMemories: triggeredMemories,
    );
    final finalMessages = [...currentSession.messages, assistantMsg];
    final now = currentTimestampSeconds();
    final sessionVars = pendingSessionVars ?? currentSession.sessionVars;
    final finalSession = currentSession.copyWith(
      messages: finalMessages,
      updatedAt: now,
      sessionVars: sessionVars,
    );
    _persist(finalSession);
    return ChatState(session: finalSession, lastRawResponse: rawResponse, visibleStartIndex: visibleStartIndex);
  }

  /// Removes stray reasoning tag markers (both the configured ones and the
  /// canonical <think>/</think> defaults) from the final text or reasoning.
  /// This is a last-line defense against unbalanced or leaked tags that the model
  /// (especially on the non-streaming path) may emit "from thin air".
  String _sanitizeReasoningMarkers(String input, String tagStart, String tagEnd) {
    var s = input;
    // Configured tags first (user may have chosen custom markers)
    if (tagStart.isNotEmpty) {
      s = s.replaceAll(tagStart, '');
    }
    if (tagEnd.isNotEmpty) {
      s = s.replaceAll(tagEnd, '');
    }
    // Canonical defaults (in case of leakage even when custom tags are configured)
    s = s.replaceAll('<think>', '');
    s = s.replaceAll('</think>', '');
    s = s.replaceAll('<think>\n', '');
    s = s.replaceAll('\n</think>', '');
    s = s.replaceAll('<think> ', '');
    s = s.replaceAll(' </think>', '');
    // Also catch partially malformed variants that sometimes leak
    s = s.replaceAll('<think', '');
    s = s.replaceAll('</think', '');
    s = s.replaceAll('think>', '');
    s = s.replaceAll('think\n', '');
    return s;
  }

  ChatState _saveErrorMessage(
    String errorText,
    ChatSession currentSession, {
    Map<String, String>? pendingSessionVars,
    int visibleStartIndex = 0,
  }) {
    final errorMsg = ChatMessage(
      id: generateId(),
      role: 'assistant',
      content: errorText,
      isError: true,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      swipes: [errorText],
      swipeId: 0,
      swipesMeta: [{}],
    );
    final finalMessages = [...currentSession.messages, errorMsg];
    final now = currentTimestampSeconds();
    final sessionVars = pendingSessionVars ?? currentSession.sessionVars;
    final finalSession = currentSession.copyWith(
      messages: finalMessages,
      updatedAt: now,
      sessionVars: sessionVars,
    );
    _persist(finalSession);
    return ChatState(session: finalSession, visibleStartIndex: visibleStartIndex);
  }

  ChatState _saveRegenError(
    String errorText,
    ChatSession saveSession,
    String regenTargetId, {
    Map<String, String>? pendingSessionVars,
    int visibleStartIndex = 0,
  }) {
    final idx = saveSession.messages.indexWhere((m) => m.id == regenTargetId);
    if (idx < 0) {
      return _saveErrorMessage(errorText, saveSession, pendingSessionVars: pendingSessionVars, visibleStartIndex: visibleStartIndex);
    }
    final original = saveSession.messages[idx];
    final errorSwipes = original.swipes.isNotEmpty ? [...original.swipes] : [original.content];
    errorSwipes.add(errorText);
    final errorSwipesMeta = original.swipesMeta.isNotEmpty
        ? [...original.swipesMeta, <String, dynamic>{}]
        : [<String, dynamic>{'genTime': original.genTime, 'reasoning': original.reasoning, 'tokens': original.tokens}, <String, dynamic>{}];
    final updated = original.copyWith(
      content: errorText,
      isError: true,
      isTyping: false,
      swipes: errorSwipes,
      swipesMeta: errorSwipesMeta,
      swipeId: errorSwipes.length - 1,
      reasoning: null,
      genTime: null,
      tokens: null,
    );
    final finalMessages = [...saveSession.messages];
    finalMessages[idx] = updated;
    final now = currentTimestampSeconds();
    final sessionVars = pendingSessionVars ?? saveSession.sessionVars;
    final finalSession = saveSession.copyWith(
      messages: finalMessages,
      updatedAt: now,
      sessionVars: sessionVars,
    );
    _persist(finalSession);
    return ChatState(session: finalSession, regenTargetId: regenTargetId, visibleStartIndex: visibleStartIndex);
  }
}
