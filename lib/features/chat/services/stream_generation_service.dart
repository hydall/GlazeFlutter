import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/llm/prompt_isolate.dart';
import '../../../core/llm/prompt_payload_builder.dart';
import '../../../core/llm/sse_client.dart';
import '../../../core/llm/stream_accumulator.dart';
import '../../../core/llm/tokenizer.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/state/active_selection_provider.dart';
import '../chat_provider.dart';
import '../chat_state.dart';
import '../state/cached_token_breakdown.dart';
import 'saved_message_writer.dart';

class StreamGenerationService {
  final Ref _ref;
  final String _charId;
  final int _genId;
  final bool Function() _isAborted;
  final SavedMessageWriter _writer = const SavedMessageWriter();

  StreamGenerationService({
    required this._ref,
    required this._charId,
    required this._genId,
    required this._isAborted,
  });

  Future<ChatState> run({
    required ChatSession session,
    ChatSession? saveSession,
    List<String>? previousSwipes,
    int previousSwipeId = 0,
    String? previousReasoning,
    String? previousGenTime,
    int? previousTokens,
    List<Map<String, dynamic>>? previousSwipesMeta,
    String? guidanceText,
    String? regenTargetId,
    required ChatState currentState,
  }) async {
    debugPrint('[gen] generate() START charId=$_charId genId=$_genId');
    final vsi = currentState.visibleStartIndex;
    final cancelToken = CancelToken();
    _ref.read(chatProvider(_charId).notifier).setCancelToken(cancelToken, genId: _genId);
    if (cancelToken.isCancelled) {
      return ChatState(session: saveSession ?? session, isGenerating: false, visibleStartIndex: vsi);
    }
    try {
      debugPrint('[gen] building payload...');
      final builder = _ref.read(promptPayloadBuilderProvider);
      final payload = await builder.buildFromSession(
        charId: _charId,
        session: session,
        guidanceText: guidanceText,
        shouldAbort: _isAborted,
        cancelToken: cancelToken,
      );
      if (_isAborted()) {
        return ChatState(session: saveSession ?? session, isGenerating: false, visibleStartIndex: vsi);
      }
      debugPrint('[gen] payload built, building prompt in isolate...');

      final apiConfig = payload.apiConfig;

      final promptResult = await buildPromptInIsolate(payload);
      if (_isAborted()) {
        return ChatState(session: saveSession ?? session, isGenerating: false, visibleStartIndex: vsi);
      }
      debugPrint('[gen] prompt built, messages=${promptResult.messages.length}, totalTokens=${promptResult.breakdown.totalTokens}');

      _ref.read(cachedTokenBreakdownProvider(_charId).notifier).state =
          promptResult.breakdown;

      _ref.read(lastVectorLoreTokensProvider(_charId).notifier).state =
          promptResult.breakdown.vectorLoreTokens;

      Map<String, String>? pendingSessionVars;
      if (promptResult.sessionVars.isNotEmpty || promptResult.globalVars.isNotEmpty) {
        pendingSessionVars = promptResult.sessionVars;
        if (promptResult.globalVars.isNotEmpty) {
          updateGlobalVarsRef(_ref, promptResult.globalVars);
        }
      }

      if (_isAborted()) return ChatState(session: saveSession ?? session, isGenerating: false, visibleStartIndex: vsi);
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
        sessionId: session.id,
        cacheControlTtl: apiConfig.cacheControlTtl,
        onUpdate: (delta, reasoningDelta) {
          if (_isAborted()) return;
          accumulator.consumeDelta(delta, reasoningDelta: reasoningDelta);
          if (!frameScheduled) {
            frameScheduled = true;
            SchedulerBinding.instance.scheduleFrameCallback((_) {
              frameScheduled = false;
              if (_isAborted()) return;
              _ref.read(streamingStateProvider(_charId).notifier).state =
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
          if (_isAborted()) return;
          if (!apiConfig.stream &&
              accumulator.text.isEmpty &&
              accumulator.reasoning.isEmpty &&
              (text.isNotEmpty || (reasoning != null && reasoning.isNotEmpty))) {
            accumulator.consumeDelta(text, reasoningDelta: reasoning);
          }
          var finalText = accumulator.text.trimLeft();
          var finalReasoning = accumulator.reasoning.isNotEmpty ? accumulator.reasoning : reasoning;

          finalText = _writer.sanitizeReasoningMarkers(finalText, reasoningTagStart, reasoningTagEnd);
          if (finalReasoning != null && finalReasoning.isNotEmpty) {
            finalReasoning = _writer.sanitizeReasoningMarkers(finalReasoning, reasoningTagStart, reasoningTagEnd);
          }

          final isAllReasoning = finalText.isEmpty && finalReasoning != null && finalReasoning.isNotEmpty;
          final elapsed = DateTime.now().difference(startGenTime).inMilliseconds;
          final timeStr = '${(elapsed / 1000).toStringAsFixed(1)}s';
          final tokenCount = estimateTokens(finalText);
          finalState = _writer.writeAssistant(
            text: finalText,
            reasoning: finalReasoning,
            currentSession: saveSession ?? session,
            isAborted: _isAborted,
            pendingSessionVars: pendingSessionVars,
            genTime: timeStr,
            tokens: tokenCount,
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
              || _isAborted();
          if (isCancelled) {
            finalState = ChatState(session: session, isGenerating: false, visibleStartIndex: vsi);
          } else if (regenTargetId != null && saveSession != null) {
            finalState = _writer.writeRegenError(
              errorText: error.toString(),
              saveSession: saveSession,
              regenTargetId: regenTargetId,
              visibleStartIndex: vsi,
            );
          } else {
            finalState = _writer.writeError(
              errorText: error.toString(),
              currentSession: session,
              visibleStartIndex: vsi,
            );
          }
        },
      );

      return finalState ?? ChatState(session: session, isGenerating: false, visibleStartIndex: vsi);
    } catch (e) {
      if (_isAborted()) return ChatState(session: session, isGenerating: false, visibleStartIndex: vsi);
      if (regenTargetId != null && saveSession != null) {
        return _writer.writeRegenError(
          errorText: e.toString(),
          saveSession: saveSession,
          regenTargetId: regenTargetId,
          visibleStartIndex: vsi,
        );
      }
      return _writer.writeError(
        errorText: e.toString(),
        currentSession: session,
        visibleStartIndex: vsi,
      );
    }
  }
}
