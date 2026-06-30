import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/llm/prompt_isolate.dart';
import '../../../core/llm/prompt_payload_builder.dart';
import '../../../core/llm/memory_studio_service.dart';
import '../../../core/llm/studio_stage_brief.dart';
import '../../../core/llm/stream_accumulator.dart';
import '../../../core/llm/beauty_state_parser.dart';
import '../../../core/llm/transport/chat_transport_request.dart';
import '../../../core/llm/transport/transport_factory.dart';
import '../../../core/utils/error_format.dart';
import '../../../core/llm/tokenizer.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/agent_operation_record.dart';
import '../../../core/state/active_selection_provider.dart';
import '../../../core/state/memory_agent_providers.dart';
import '../chat_provider.dart';
import '../chat_state.dart';
import '../state/agent_operations_log_provider.dart';
import '../state/cached_token_breakdown.dart';
import '../state/memory_activity_provider.dart';
import '../state/studio_cycle_state_provider.dart';
import 'saved_message_writer.dart';

class StreamGenerationService {
  static final Map<String, List<Map<String, dynamic>>> _lastRequestsBySession =
      <String, List<Map<String, dynamic>>>{};

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
    final vsi = currentState.visibleStartIndex;
    final cancelToken = CancelToken();
    _ref
        .read(chatProvider(_charId).notifier)
        .setCancelToken(cancelToken, genId: _genId);
    if (cancelToken.isCancelled) {
      return ChatState(
        session: saveSession ?? session,
        isGenerating: false,
        visibleStartIndex: vsi,
      );
    }
    try {
      final builder = _ref.read(promptPayloadBuilderProvider);
      final payload = await builder.buildFromSession(
        charId: _charId,
        session: session,
        guidanceText: guidanceText,
        shouldAbort: _isAborted,
        cancelToken: cancelToken,
      );
      if (_isAborted()) {
        return ChatState(
          session: saveSession ?? session,
          isGenerating: false,
          visibleStartIndex: vsi,
        );
      }
      final apiConfig = payload.apiConfig;

      final promptResult = await buildPromptInIsolate(payload);
      if (_isAborted()) {
        return ChatState(
          session: saveSession ?? session,
          isGenerating: false,
          visibleStartIndex: vsi,
        );
      }
      _ref.read(cachedTokenBreakdownProvider(_charId).notifier).state =
          promptResult.breakdown;

      _ref.read(lastVectorLoreTokensProvider(_charId).notifier).state =
          promptResult.breakdown.vectorLoreTokens;

      Map<String, String>? pendingSessionVars;
      if (promptResult.sessionVars.isNotEmpty ||
          promptResult.globalVars.isNotEmpty) {
        pendingSessionVars = promptResult.sessionVars;
        if (promptResult.globalVars.isNotEmpty) {
          updateGlobalVarsRef(_ref, promptResult.globalVars);
        }
      }

      if (_isAborted()) {
        return ChatState(
          session: saveSession ?? session,
          isGenerating: false,
          visibleStartIndex: vsi,
        );
      }
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

      final apiMessages = promptResult.messages
          .where((m) => m.content.trim().isNotEmpty)
          .map((m) => m.toApiMap())
          .toList();
      final previousApiMessages = _lastRequestsBySession[session.id];
      _rememberRequest(session.id, apiMessages);
      _log(
        'base prompt ready char=$_charId session=${session.id} '
        'messages=${apiMessages.length} model=${apiConfig.model} '
        'protocol=${apiConfig.protocol}',
      );

      final coverage = promptResult.memoryCoverage.isNotEmpty
          ? promptResult.memoryCoverage
          : payload.memoryCoverage;
      final memoryDiagnostics = coverage['diagnostics'];
      final triggeredLorebooks = promptResult.triggeredLorebooks;
      final triggeredMemories = promptResult.triggeredMemories;

      final studioConfig = await _ref
          .read(memoryStudioServiceProvider)
          .getEnabledConfig(session.id);
      if (_isAborted()) {
        return ChatState(
          session: saveSession ?? session,
          isGenerating: false,
          visibleStartIndex: vsi,
        );
      }
      if (studioConfig != null) {
        _log(
          'studio intercept char=$_charId session=${session.id} '
          'agents=${studioConfig.agents.length}',
        );
        _ref
            .read(studioCycleStateProvider.notifier)
            .state = StudioCycleState.running(
          sessionId: session.id,
          totalAgents: studioConfig.agents.length,
        );
        final promptResult = await buildPromptInIsolate(payload);
        if (_isAborted()) {
          return ChatState(
            session: saveSession ?? session,
            isGenerating: false,
            visibleStartIndex: vsi,
          );
        }
        final startGenTime = DateTime.now();
        DateTime? finalStartTime;
        bool studioFrameScheduled = false;
        var latestStudioText = '';
        String? latestStudioReasoning;
        void scheduleStudioStreamingUpdate() {
          if (studioFrameScheduled) return;
          studioFrameScheduled = true;
          SchedulerBinding.instance.scheduleFrameCallback((_) {
            studioFrameScheduled = false;
            if (_isAborted()) return;
            _ref
                .read(streamingStateProvider(_charId).notifier)
                .state = StreamingState(
              text: latestStudioText,
              reasoning: latestStudioReasoning,
            );
          });
        }

        final studioService = _ref.read(memoryStudioServiceProvider);
        final studioResult = await studioService.runTrackerCycle(
          config: studioConfig,
          promptResult: promptResult,
          promptPayload: payload,
          apiConfig: apiConfig,
          sessionId: session.id,
          cancelToken: cancelToken,
          onFinalResponseUpdate: (text, reasoning) {
            if (_isAborted()) return;
            latestStudioText = text;
            latestStudioReasoning = reasoning;
            final cur = _ref.read(studioCycleStateProvider);
            if (cur.phase == StudioCyclePhase.running) {
              finalStartTime ??= DateTime.now();
              _ref
                  .read(studioCycleStateProvider.notifier)
                  .state = StudioCycleState.writingFinal(
                sessionId: session.id,
                totalAgents: cur.totalAgents,
                completedAgents: cur.completedAgents,
                failedAgents: cur.failedAgents,
                failedAgentNames: cur.failedAgentNames,
              );
            }
            scheduleStudioStreamingUpdate();
          },
        );
        if (_isAborted() || studioResult.status == 'aborted') {
          _ref.read(studioCycleStateProvider.notifier).state =
              const StudioCycleState.idle();
          return ChatState(
            session: saveSession ?? session,
            isGenerating: false,
            visibleStartIndex: vsi,
          );
        }
        if (studioResult.status == 'agent_errors') {
          // Intermediate agents failed — save their outputs (with error
          // status) so the user can regenerate failed agents, then
          // explicitly send to the final model. Do NOT write an error
          // message; the studio outputs panel shows the failures.
          _log(
            'studio agent_errors char=$_charId session=${session.id} '
            'error=${studioResult.error}',
          );
          _ref
              .read(studioCycleStateProvider.notifier)
              .state = _studioFinalState(
            session.id,
            studioResult,
            StudioCyclePhase.agentErrors,
          );
          final elapsed = DateTime.now()
              .difference(startGenTime)
              .inMilliseconds;
          final finalState = _writer
              .writeAssistant(
                text: '',
                reasoning: null,
                currentSession: saveSession ?? session,
                isAborted: _isAborted,
                pendingSessionVars: pendingSessionVars,
                genTime: '${(elapsed / 1000).toStringAsFixed(1)}s',
                tokens: 0,
                rawResponse: '',
                previousSwipes: previousSwipes,
                previousSwipeId: previousSwipeId,
                previousReasoning: previousReasoning,
                previousGenTime: previousGenTime,
                previousTokens: previousTokens,
                previousSwipesMeta: previousSwipesMeta,
                guidanceText: guidanceText,
                memoryCoverage: coverage,
                isAllReasoning: false,
                triggeredLorebooks: triggeredLorebooks,
                triggeredMemories: triggeredMemories,
                regenTargetId: regenTargetId,
                visibleStartIndex: vsi,
                studioOutputs: _studioOutputsToJson(studioResult.stageBriefs),
              )
              .copyWith(promptPayload: payload);
          final messageId = _lastAssistantId(
            finalState.session ?? saveSession ?? session,
            regenTargetId,
          );
          _recordStudioTrackerOperation(
            sessionId: session.id,
            messageId: messageId,
            startGenTime: startGenTime,
            finalStartTime: finalStartTime,
            result: studioResult,
            model: apiConfig.model,
          );
          return finalState;
        }
        if (studioResult.status != 'ok' || studioResult.response.isEmpty) {
          final message =
              studioResult.error ?? 'Studio failed: ${studioResult.status}';
          _log(
            'studio failed char=$_charId session=${session.id} '
            'status=${studioResult.status} error=$message',
          );
          _recordStudioTrackerOperation(
            sessionId: session.id,
            startGenTime: startGenTime,
            result: studioResult,
            model: apiConfig.model,
          );
          _ref.read(studioCycleStateProvider.notifier).state =
              const StudioCycleState.error(sessionId: '');
          if (regenTargetId != null && saveSession != null) {
            return _writer.writeRegenError(
              errorText: message,
              saveSession: saveSession,
              regenTargetId: regenTargetId,
              visibleStartIndex: vsi,
            );
          }
          return _writer.writeError(
            errorText: message,
            currentSession: session,
            visibleStartIndex: vsi,
          );
        }

        final elapsed = DateTime.now().difference(startGenTime).inMilliseconds;
        _log(
          'studio write assistant char=$_charId session=${session.id} '
          'elapsedMs=$elapsed chars=${studioResult.response.length} '
          'briefs=${studioResult.stageBriefs.length}',
        );
        _ref.read(studioCycleStateProvider.notifier).state = _studioFinalState(
          session.id,
          studioResult,
          StudioCyclePhase.done,
        );
        final beautyApplied = _applyBeautyState(
          studioResult.response,
          pendingSessionVars,
        );
        final finalState = _writer
            .writeAssistant(
              text: beautyApplied.text,
              reasoning: studioResult.reasoning.isNotEmpty
                  ? studioResult.reasoning
                  : null,
              currentSession: saveSession ?? session,
              isAborted: _isAborted,
              pendingSessionVars: beautyApplied.vars,
              genTime: '${(elapsed / 1000).toStringAsFixed(1)}s',
              tokens: estimateTokens(studioResult.response),
              rawResponse:
                  studioResult.rawResponseJson ?? studioResult.response,
              previousSwipes: previousSwipes,
              previousSwipeId: previousSwipeId,
              previousReasoning: previousReasoning,
              previousGenTime: previousGenTime,
              previousTokens: previousTokens,
              previousSwipesMeta: previousSwipesMeta,
              guidanceText: guidanceText,
              memoryCoverage: coverage,
              isAllReasoning: false,
              triggeredLorebooks: triggeredLorebooks,
              triggeredMemories: triggeredMemories,
              regenTargetId: regenTargetId,
              visibleStartIndex: vsi,
              studioOutputs: _studioOutputsToJson(studioResult.stageBriefs),
            )
            .copyWith(promptPayload: payload);
        final messageId = _lastAssistantId(finalState.session!, regenTargetId);
        _recordStudioTrackerOperation(
          sessionId: session.id,
          messageId: messageId,
          startGenTime: startGenTime,
          finalStartTime: finalStartTime,
          result: studioResult,
          model: apiConfig.model,
        );
        if (memoryDiagnostics is Map<String, dynamic> &&
            finalState.session != null) {
          final memoryMessageId = _lastAssistantId(
            finalState.session!,
            regenTargetId,
          );
          _ref
              .read(lastMemoryActivityProvider(_charId).notifier)
              .state = MemoryActivityState(
            sessionId: finalState.session!.id,
            messageId: memoryMessageId,
            diagnostics: Map<String, dynamic>.from(memoryDiagnostics),
            updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
          );
          _recordSidecarOperation(
            finalState.session!.id,
            memoryMessageId,
            memoryDiagnostics,
          );
        } else {
          _ref.read(lastMemoryActivityProvider(_charId).notifier).state = null;
        }
        if (finalState.session != null) {
          unawaited(
            _ref
                .read(memoryPostTurnServiceProvider)
                .runPostTurn(finalState.session!.id),
          );
        }
        return finalState;
      }

      _log('studio not active char=$_charId session=${session.id}');

      final accumulator = StreamAccumulator(
        tagStart: reasoningTagStart,
        tagEnd: reasoningTagEnd,
        hasInlineTags: hasInlineTags,
      );

      final startGenTime = DateTime.now();
      final transport = pickChatTransport(apiConfig.protocol);
      ChatState? finalState;

      bool frameScheduled = false;

      await transport.stream(
        request: ChatTransportRequest(
          endpoint: apiConfig.endpoint,
          apiKey: apiConfig.apiKey,
          model: apiConfig.model,
          messages: apiMessages,
          maxTokens: apiConfig.maxTokens,
          temperature: apiConfig.temperature,
          topP: apiConfig.topP,
          topK: apiConfig.topK,
          frequencyPenalty: apiConfig.frequencyPenalty,
          presencePenalty: apiConfig.presencePenalty,
          stream: apiConfig.stream,
          requestReasoning: apiConfig.requestReasoning,
          reasoningEffort: apiConfig.reasoningEffort,
          omitTemperature: apiConfig.omitTemperature,
          omitTopP: apiConfig.omitTopP,
          omitReasoning: apiConfig.omitReasoning,
          omitReasoningEffort: apiConfig.omitReasoningEffort,
          sessionId: session.id,
          previousMessages: previousApiMessages,
          cacheControlTtl: apiConfig.cacheControlTtl,
          cacheBreakpointMode: apiConfig.cacheBreakpointMode,
          sessionIdMode: apiConfig.sessionIdMode,
        ),
        cancelToken: cancelToken,
        onUpdate: (delta, reasoningDelta) {
          if (_isAborted()) return;
          accumulator.consumeDelta(delta, reasoningDelta: reasoningDelta);
          if (!frameScheduled) {
            frameScheduled = true;
            SchedulerBinding.instance.scheduleFrameCallback((_) {
              frameScheduled = false;
              if (_isAborted()) return;
              _ref
                  .read(streamingStateProvider(_charId).notifier)
                  .state = StreamingState(
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
              (text.isNotEmpty ||
                  (reasoning != null && reasoning.isNotEmpty))) {
            accumulator.consumeDelta(text, reasoningDelta: reasoning);
          }
          var finalText = accumulator.text.trimLeft();
          var finalReasoning = accumulator.reasoning.isNotEmpty
              ? accumulator.reasoning
              : reasoning;

          finalText = _writer.sanitizeReasoningMarkers(
            finalText,
            reasoningTagStart,
            reasoningTagEnd,
          );
          if (finalReasoning != null && finalReasoning.isNotEmpty) {
            finalReasoning = _writer.sanitizeReasoningMarkers(
              finalReasoning,
              reasoningTagStart,
              reasoningTagEnd,
            );
          }

          final beautyApplied = _applyBeautyState(
            finalText,
            pendingSessionVars,
          );
          finalText = beautyApplied.text;
          pendingSessionVars = beautyApplied.vars;

          final isAllReasoning =
              finalText.isEmpty &&
              finalReasoning != null &&
              finalReasoning.isNotEmpty;
          final elapsed = DateTime.now()
              .difference(startGenTime)
              .inMilliseconds;
          final timeStr = '${(elapsed / 1000).toStringAsFixed(1)}s';
          final tokenCount = estimateTokens(finalText);
          finalState = _writer
              .writeAssistant(
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
              )
              .copyWith(promptPayload: payload);
          if (memoryDiagnostics is Map<String, dynamic> &&
              finalState?.session != null) {
            final messageId = _lastAssistantId(
              finalState!.session!,
              regenTargetId,
            );
            _ref
                .read(lastMemoryActivityProvider(_charId).notifier)
                .state = MemoryActivityState(
              sessionId: finalState!.session!.id,
              messageId: messageId,
              diagnostics: Map<String, dynamic>.from(memoryDiagnostics),
              updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
            );
            _recordSidecarOperation(
              finalState!.session!.id,
              messageId,
              memoryDiagnostics,
            );
          } else {
            _ref.read(lastMemoryActivityProvider(_charId).notifier).state =
                null;
          }
          // Post-turn memory pipeline (Phase G4): fire-and-forget.
          // Does NOT block generation or user interaction.
          if (finalState?.session != null) {
            unawaited(
              _ref
                  .read(memoryPostTurnServiceProvider)
                  .runPostTurn(finalState!.session!.id),
            );
          }
        },
        onError: (error) {
          final isCancelled =
              (error is DioException &&
                  error.type == DioExceptionType.cancel) ||
              cancelToken.isCancelled ||
              _isAborted();
          if (isCancelled) {
            finalState = ChatState(
              session: session,
              isGenerating: false,
              visibleStartIndex: vsi,
            );
          } else if (regenTargetId != null && saveSession != null) {
            finalState = _writer.writeRegenError(
              errorText: formatError(error),
              saveSession: saveSession,
              regenTargetId: regenTargetId,
              visibleStartIndex: vsi,
            );
          } else {
            finalState = _writer.writeError(
              errorText: formatError(error),
              currentSession: session,
              visibleStartIndex: vsi,
            );
          }
        },
      );

      return finalState ??
          ChatState(
            session: session,
            isGenerating: false,
            visibleStartIndex: vsi,
          );
    } catch (e) {
      if (_isAborted()) {
        return ChatState(
          session: session,
          isGenerating: false,
          visibleStartIndex: vsi,
        );
      }
      if (regenTargetId != null && saveSession != null) {
        return _writer.writeRegenError(
          errorText: formatError(e),
          saveSession: saveSession,
          regenTargetId: regenTargetId,
          visibleStartIndex: vsi,
        );
      }
      return _writer.writeError(
        errorText: formatError(e),
        currentSession: session,
        visibleStartIndex: vsi,
      );
    }
  }

  static void _rememberRequest(
    String sessionId,
    List<Map<String, dynamic>> messages,
  ) {
    _lastRequestsBySession[sessionId] = messages
        .map((m) => Map<String, dynamic>.from(m))
        .toList(growable: false);
    if (_lastRequestsBySession.length > 64) {
      _lastRequestsBySession.remove(_lastRequestsBySession.keys.first);
    }
  }

  static String? _lastAssistantId(ChatSession session, String? regenTargetId) {
    if (regenTargetId != null &&
        session.messages.any((m) => m.id == regenTargetId)) {
      return regenTargetId;
    }
    for (final message in session.messages.reversed) {
      if (message.role == 'assistant') return message.id;
    }
    return null;
  }

  static void _log(String message) {
    debugPrint('[StudioGen] $message');
  }

  /// Convert Studio stage briefs into the compact JSON format stored on
  /// `ChatMessage.studioOutputs` / `AgentSwipe.studioOutputs` and read by the
  /// UI (Agentic Ops panel). Format: `{'id','name','content'}` per brief.
  static List<Map<String, dynamic>> _studioOutputsToJson(
    List<StudioStageBrief> briefs,
  ) {
    return briefs
        .map((b) => {'id': b.agentId, 'name': b.agentName, 'content': b.brief})
        .toList(growable: false);
  }

  /// Records a memory sidecar reranker operation in the agentic operations log
  /// when the diagnostics carry a `sidecarAttempts` array (deep mode only).
  void _recordSidecarOperation(
    String sessionId,
    String? messageId,
    Map<String, dynamic> diagnostics,
  ) {
    // Memory sidecar (reranker) operation.
    final sidecarStatus = diagnostics['sidecarStatus'] as String?;
    if (sidecarStatus != null && sidecarStatus != 'disabled') {
      final rawAttempts = diagnostics['sidecarAttempts'];
      if (rawAttempts is List) {
        final attempts = rawAttempts
            .whereType<Map<dynamic, dynamic>>()
            .map(
              (e) =>
                  AgentOperationAttempt.fromJson(Map<String, dynamic>.from(e)),
            )
            .toList();
        if (attempts.isNotEmpty) {
          final status = _sidecarStatusToOp(sidecarStatus);
          _appendOperation(
            AgentOperationRecord(
              id: 'sidecar-$sessionId-${DateTime.now().microsecondsSinceEpoch}',
              kind: AgentOperationKind.memorySidecar,
              status: status,
              sessionId: sessionId,
              messageId: messageId,
              attempts: attempts,
              totalElapsedMs: attempts.fold(0, (sum, a) => sum + a.elapsedMs),
              summary: status == AgentOperationStatus.ok
                  ? 'reranked ${diagnostics['selectedCount'] ?? 0} entries'
                  : sidecarStatus,
              startedAtMs: attempts.first.startedAtMs,
              finishedAtMs: attempts.last.startedAtMs + attempts.last.elapsedMs,
              canRegenerate: status.isFailure,
            ),
          );
        }
      }
    }

    // Agentic search (searchMemory tool) operation.
    final agenticStatus = diagnostics['agenticStatus'] as String?;
    if (agenticStatus != null &&
        agenticStatus != 'disabled' &&
        agenticStatus != 'aborted') {
      final rawAttempts = diagnostics['agenticAttempts'];
      if (rawAttempts is List) {
        final attempts = rawAttempts
            .whereType<Map<dynamic, dynamic>>()
            .map(
              (e) =>
                  AgentOperationAttempt.fromJson(Map<String, dynamic>.from(e)),
            )
            .toList();
        if (attempts.isNotEmpty) {
          final status = _sidecarStatusToOp(agenticStatus);
          _appendOperation(
            AgentOperationRecord(
              id: 'agentic-search-$sessionId-${DateTime.now().microsecondsSinceEpoch}',
              kind: AgentOperationKind.agenticSearch,
              status: status,
              sessionId: sessionId,
              messageId: messageId,
              attempts: attempts,
              totalElapsedMs: attempts.fold(0, (sum, a) => sum + a.elapsedMs),
              summary: status == AgentOperationStatus.ok
                  ? 'agentic search'
                  : agenticStatus,
              startedAtMs: attempts.first.startedAtMs,
              finishedAtMs: attempts.last.startedAtMs + attempts.last.elapsedMs,
              canRegenerate: status.isFailure,
            ),
          );
        }
      }
    }
  }

  void _appendOperation(AgentOperationRecord record) {
    _ref.read(agentOperationsLogProvider.notifier).state = _ref
        .read(agentOperationsLogProvider)
        .append(record);
  }

  /// Records a Studio tracker-cycle operation in the agentic operations log.
  ///
  /// Studio differs from the other agentic ops in that the per-agent LLM
  /// attempts are not surfaced as a structured `attempts` array on the
  /// pipeline result — they are summarised as `stageBriefs` (one per tracker
  /// agent) plus an overall `status`. We synthesise a single aggregate
  /// `AgentOperationAttempt` covering the whole cycle elapsed time and put
  /// the per-agent breakdown into the `summary` text.
  ///
  /// Call sites:
  ///   - success path (`status == 'ok'`)
  ///   - partial agent errors (`status == 'agent_errors'`)
  ///   - hard failure (`status != 'ok' && status != 'agent_errors' &&
  ///     status != 'aborted' && status != 'disabled'`)
  ///
  /// Aborted / disabled runs are not logged — they are user-initiated
  /// cancellations or no-op configurations, not real operations.
  void _recordStudioTrackerOperation({
    required String sessionId,
    String? messageId,
    required DateTime startGenTime,
    DateTime? finalStartTime,
    required StudioPipelineResult result,
    String? model,
  }) {
    final status = _studioStatusToOp(result.status);
    if (status == AgentOperationStatus.aborted ||
        status == AgentOperationStatus.disabled) {
      return;
    }
    final now = DateTime.now();
    final elapsedMs = now.difference(startGenTime).inMilliseconds;
    final startedAtMs = startGenTime.millisecondsSinceEpoch;

    final briefs = result.stageBriefs;

    if (briefs.isEmpty) {
      _appendOperation(
        AgentOperationRecord(
          id: 'studio-tracker-$sessionId-${now.microsecondsSinceEpoch}',
          kind: AgentOperationKind.studioTracker,
          status: status,
          sessionId: sessionId,
          messageId: messageId,
          attempts: [
            AgentOperationAttempt(
              attempt: 1,
              statusCode: 0,
              status: status.label,
              error: status.isFailure ? (result.error ?? result.status) : null,
              startedAtMs: startedAtMs,
              elapsedMs: elapsedMs,
            ),
          ],
          totalElapsedMs: elapsedMs,
          model: model,
          summary: result.error ?? result.status,
          startedAtMs: startedAtMs,
          finishedAtMs: now.millisecondsSinceEpoch,
          canRegenerate: status.isFailure,
        ),
      );
      return;
    }

    for (var i = 0; i < briefs.length; i++) {
      final brief = briefs[i];
      final briefStatus = brief.status == 'ok'
          ? AgentOperationStatus.ok
          : AgentOperationStatus.error;
      final summary = brief.status == 'ok'
          ? '${brief.agentName} · ${brief.brief.length} chars'
          : '${brief.agentName} · ${brief.error ?? brief.status}';
      final idStamp = now.microsecondsSinceEpoch + i;
      final opStartedAt = startedAtMs + i;
      _appendOperation(
        AgentOperationRecord(
          id: 'studio-tracker-${brief.agentId}-$sessionId-$idStamp',
          kind: AgentOperationKind.studioTracker,
          status: briefStatus,
          sessionId: sessionId,
          messageId: messageId,
          attempts: [
            AgentOperationAttempt(
              attempt: 1,
              statusCode: 0,
              status: briefStatus.label,
              error: briefStatus.isFailure
                  ? (brief.error ?? brief.status)
                  : null,
              startedAtMs: opStartedAt,
              elapsedMs: elapsedMs,
            ),
          ],
          totalElapsedMs: elapsedMs,
          model: model,
          summary: summary,
          startedAtMs: opStartedAt,
          finishedAtMs: opStartedAt,
          canRegenerate: briefStatus.isFailure,
        ),
      );
    }

    final finalStartedAt =
        finalStartTime?.millisecondsSinceEpoch ?? startedAtMs + briefs.length;
    final finalElapsedMs = now.millisecondsSinceEpoch - finalStartedAt;
    _appendOperation(
      AgentOperationRecord(
        id: 'studio-final-$sessionId-${now.microsecondsSinceEpoch}',
        kind: AgentOperationKind.studioFinal,
        status: status,
        sessionId: sessionId,
        messageId: messageId,
        attempts: [
          AgentOperationAttempt(
            attempt: 1,
            statusCode: 0,
            status: status.label,
            error: status.isFailure ? (result.error ?? result.status) : null,
            startedAtMs: finalStartedAt,
            elapsedMs: finalElapsedMs < 0 ? elapsedMs : finalElapsedMs,
          ),
        ],
        totalElapsedMs: finalElapsedMs < 0 ? elapsedMs : finalElapsedMs,
        model: model,
        summary: status.isOk
            ? 'final reply · ${result.response.length} chars'
            : result.error ?? result.status,
        startedAtMs: finalStartedAt,
        finishedAtMs: now.millisecondsSinceEpoch,
        canRegenerate: status.isFailure,
      ),
    );
  }

  static AgentOperationStatus _studioStatusToOp(String status) {
    return switch (status) {
      'ok' => AgentOperationStatus.ok,
      'disabled' => AgentOperationStatus.disabled,
      'aborted' => AgentOperationStatus.aborted,
      'timeout' => AgentOperationStatus.timeout,
      'error' => AgentOperationStatus.error,
      'agent_errors' => AgentOperationStatus.error,
      _ => AgentOperationStatus.error,
    };
  }

  /// Builds the terminal `StudioCycleState` from a `StudioPipelineResult`,
  /// aggregating the per-agent briefs into completed/failed counts.
  static StudioCycleState _studioFinalState(
    String sessionId,
    StudioPipelineResult result,
    StudioCyclePhase phase,
  ) {
    final briefs = result.stageBriefs;
    final ok = briefs.where((b) => b.status == 'ok').length;
    final failed = briefs.length - ok;
    final failedNames = briefs
        .where((b) => b.status != 'ok')
        .map((b) => b.agentName)
        .toList(growable: false);
    switch (phase) {
      case StudioCyclePhase.done:
        return StudioCycleState.done(
          sessionId: sessionId,
          totalAgents: briefs.length,
          completedAgents: ok,
          failedAgents: failed,
          failedAgentNames: failedNames,
        );
      case StudioCyclePhase.agentErrors:
        return StudioCycleState.agentErrors(
          sessionId: sessionId,
          totalAgents: briefs.length,
          completedAgents: ok,
          failedAgents: failed,
          failedAgentNames: failedNames,
        );
      default:
        return const StudioCycleState.idle();
    }
  }

  static AgentOperationStatus _sidecarStatusToOp(String status) {
    return switch (status) {
      'ok' => AgentOperationStatus.ok,
      'disabled' => AgentOperationStatus.disabled,
      'aborted' => AgentOperationStatus.aborted,
      'timeout' => AgentOperationStatus.timeout,
      'http_error' => AgentOperationStatus.httpError,
      'invalid_output' => AgentOperationStatus.invalidOutput,
      'error' => AgentOperationStatus.error,
      _ => AgentOperationStatus.error,
    };
  }

  /// Strips any `<glaze_beauty_state>...</glaze_beauty_state>` marker from
  /// the assistant response and merges the parsed JSON state into the pending
  /// session vars (success-only persistence — INV-C5 still holds because this
  /// is only called from the two success-path `writeAssistant` call sites).
  /// When no marker is found, returns [text] and [vars] unchanged.
  _BeautyStateResult _applyBeautyState(
    String text,
    Map<String, String>? pendingVars,
  ) {
    final parsed = parseBeautyState(text);
    if (!parsed.markerFound) {
      return _BeautyStateResult(text: text, vars: pendingVars);
    }
    final vars = parsed.stateJson == null
        ? pendingVars
        : <String, String>{
            ...?pendingVars,
            beautyStateVarKey: parsed.stateJson!,
          };
    return _BeautyStateResult(text: parsed.cleanedText, vars: vars);
  }
}

class _BeautyStateResult {
  final String text;
  final Map<String, String>? vars;
  const _BeautyStateResult({required this.text, required this.vars});
}
