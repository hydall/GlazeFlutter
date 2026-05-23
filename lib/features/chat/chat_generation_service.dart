import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
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
import '../../shared/widgets/glaze_toast.dart';
import '../image_gen/image_gen_provider.dart';
import '../settings/api_list_provider.dart';
import '../image_gen/services/image_gen_service.dart';
import 'chat_provider.dart';
import 'chat_state.dart';
import 'widgets/cached_token_breakdown.dart';

class ChatGenerationService {
  final Ref _ref;

  ChatGenerationService(this._ref);

  Future<ChatState> generate({
    required ChatSession session,
    ChatSession? saveSession,
    required String charId,
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
    try {
      final builder = _ref.read(promptPayloadBuilderProvider);
      final payload = await builder.buildFromSession(
        charId: charId,
        session: session,
        guidanceText: guidanceText,
      );

      final apiConfig = payload.apiConfig;

      final promptResult = await buildPromptInIsolate(payload);

      _ref.read(cachedTokenBreakdownProvider(charId).notifier).state =
          promptResult.breakdown;

      Map<String, String>? pendingSessionVars;
      if (promptResult.sessionVars.isNotEmpty || promptResult.globalVars.isNotEmpty) {
        pendingSessionVars = promptResult.sessionVars;
        if (promptResult.globalVars.isNotEmpty) {
          updateGlobalVarsRef(_ref, promptResult.globalVars);
        }
      }

      final cancelToken = CancelToken();
      _ref.read(chatProvider(charId).notifier).setCancelToken(cancelToken);
      final preset = payload.preset;
      const defaultTagStart = '<think' + '>' ;
      const defaultTagEnd = '</think' + '>' ;
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
      final accumulator = StreamAccumulator(
        tagStart: reasoningTagStart,
        tagEnd: reasoningTagEnd,
        hasInlineTags: true,
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
          accumulator.consumeDelta(delta, reasoningDelta: reasoningDelta);
          if (!frameScheduled) {
            frameScheduled = true;
            SchedulerBinding.instance.scheduleFrameCallback((_) {
              frameScheduled = false;
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
        onComplete: (text, reasoning) {
          if (isAborted()) return;
          accumulator.flush();
          var finalText = accumulator.text.trimLeft();
          // If the model emitted <think>...</think> via reasoning_content but leaked
          // the closing tag into content, strip it from the start of finalText.
          if (finalText.startsWith(reasoningTagEnd)) {
            finalText = finalText.substring(reasoningTagEnd.length).trimLeft();
          }
          var finalReasoning = accumulator.reasoning.isNotEmpty ? accumulator.reasoning : reasoning;
          final isAllReasoning = finalText.isEmpty && finalReasoning != null && finalReasoning.isNotEmpty;
          final elapsed = DateTime.now().difference(startGenTime).inMilliseconds;
          final timeStr = '${(elapsed / 1000).toStringAsFixed(1)}s';
          final tokenCount = (finalText.length / 4).round();
          finalState = _saveAssistantMessage(
            finalText, finalReasoning, saveSession ?? session,
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
            isAllReasoning: isAllReasoning,
            triggeredLorebooks: triggeredLorebooks,
            triggeredMemories: triggeredMemories,
            regenTargetId: regenTargetId,
          );
        },
        onError: (error) {
          final isCancelled = error is DioException && error.type == DioExceptionType.cancel;
          debugPrint('[gen] SSE onError: isCancelled=$isCancelled errorType=${error.runtimeType} regenTargetId=$regenTargetId');
          if (isCancelled) {
            finalState = ChatState(session: session, isGenerating: false);
          } else {
            debugPrint('[gen] SSE error details: $error');
            finalState = _saveErrorMessage(error.toString(), session, pendingSessionVars: pendingSessionVars);
          }
        },
      );

      return finalState ?? ChatState(session: session, isGenerating: false);
    } catch (e) {
      debugPrint('[gen] generate() caught exception: $e regenTargetId=$regenTargetId isAborted=${isAborted()}');
      if (isAborted()) return ChatState(session: session, isGenerating: false);
      return _saveErrorMessage(e.toString(), session);
    }
  }

  Future<void> processImageTags({
    required ChatState currentState,
    required String charId,
    CancelToken? cancelToken,
    required void Function(ChatState) onStateUpdate,
  }) async {
    final session = currentState.session;
    debugPrint('IMGGEN processImageTags CALLED: session=${session != null}');
    if (session == null) return;

    final imgGenSettingsAsync = _ref.read(imageGenSettingsProvider);
    if (imgGenSettingsAsync.isLoading) {
      debugPrint('IMGGEN: settings still loading, waiting...');
      final imgGenSettings = await _ref.read(imageGenSettingsProvider.future);
      debugPrint('IMGGEN: settings loaded, enabled=${imgGenSettings.enabled}');
      if (!imgGenSettings.enabled) return;
    } else {
      final imgGenSettings = imgGenSettingsAsync.value;
      debugPrint('IMGGEN: settings=${imgGenSettings != null}, enabled=${imgGenSettings?.enabled}, isLoading=${imgGenSettingsAsync.isLoading}, hasError=${imgGenSettingsAsync.hasError}');
      if (imgGenSettings == null || !imgGenSettings.enabled) return;
    }
    final imgGenSettings = await _ref.read(imageGenSettingsProvider.future);

    final lastIdx = session.messages.length - 1;
    if (lastIdx < 0) return;
    final lastMsg = session.messages[lastIdx];
    if (lastMsg.role != 'assistant') return;

    final notifier = _ref.read(imageGenSettingsProvider.notifier);
    final service = await notifier.getServiceAsync();
    debugPrint('IMGGEN: service ready, hasTags=${service.hasImageGenTags(lastMsg.content)}, contentLen=${lastMsg.content.length}');
    if (!service.hasImageGenTags(lastMsg.content)) return;

    final apiConfig = _ref.read(activeApiConfigProvider);
    if (apiConfig == null) return;

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

    onStateUpdate(ChatState(session: session, isGeneratingImage: true));

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
          onStateUpdate(ChatState(session: updatedSession));
        },
        onError: (error) {
          GlazeToast.showWithoutContext('Image gen: $error', isError: true, duration: 4000);
        },
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        onStateUpdate(ChatState(session: session, isGeneratingImage: false));
        return;
      }
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
      onStateUpdate(ChatState(session: finalSession, isGeneratingImage: false));
      return;
    }

    final newMessages = List<ChatMessage>.from(session.messages);
    final finalSwipeIdx = lastMsg.swipeId;
    final finalSwipes = lastMsg.swipes.isNotEmpty && finalSwipeIdx >= 0 && finalSwipeIdx < lastMsg.swipes.length
        ? (List<String>.from(lastMsg.swipes)..[finalSwipeIdx] = updatedContent)
        : lastMsg.swipes;
    newMessages[lastIdx] = lastMsg.copyWith(content: updatedContent, swipes: finalSwipes);
    debugPrint('IMGGEN: final persist swipeId=$finalSwipeIdx contentHasResult=${updatedContent.contains('[IMG:RESULT')} swipeHasResult=${finalSwipeIdx < finalSwipes.length && finalSwipes[finalSwipeIdx].contains('[IMG:RESULT')}');
    final finalSession = session.copyWith(
      messages: newMessages,
      updatedAt: currentTimestampSeconds(),
    );
    await _ref.read(chatRepoProvider).put(finalSession);
    onStateUpdate(ChatState(session: finalSession, isGeneratingImage: false));
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
    bool isAllReasoning = false,
    List<TriggeredEntry> triggeredLorebooks = const [],
    List<TriggeredEntry> triggeredMemories = const [],
    String? regenTargetId,
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
      final idx = currentSession.messages.indexWhere((m) => m.id == regenTargetId);
      debugPrint('[gen] _saveAssistantMessage regenTargetId=$regenTargetId idx=$idx swipes=${swipes.length} swipeId=$swipeId');
      if (idx >= 0) {
        final updated = currentSession.messages[idx].copyWith(
          content: text,
          reasoning: reasoning,
          isAllReasoning: isAllReasoning,
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
        _ref.read(chatRepoProvider).put(finalSession);
        return ChatState(session: finalSession, lastRawResponse: rawResponse, regenTargetId: regenTargetId);
      }
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
    _ref.read(chatRepoProvider).put(finalSession);
    return ChatState(session: finalSession, lastRawResponse: rawResponse);
  }

  ChatState _saveErrorMessage(
    String errorText,
    ChatSession currentSession, {
    Map<String, String>? pendingSessionVars,
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
    _ref.read(chatRepoProvider).put(finalSession);
    return ChatState(session: finalSession);
  }
}
