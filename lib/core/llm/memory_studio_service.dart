import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../models/api_config.dart';
import '../models/chat_message.dart';
import '../models/preset.dart';
import '../models/studio_config.dart';
import '../state/db_provider.dart';
import '../utils/cast_helpers.dart';
import '../utils/error_format.dart';
import '../../features/settings/api_list_provider.dart';
import 'history_assembler.dart';
import 'macro_engine.dart';
import 'memory_studio_mode.dart';
import 'prompt_builder.dart';
import 'studio_request_preset.dart';
import 'tokenizer.dart';
import 'transport/anthropic_chat_transport.dart';
import 'transport/chat_transport_request.dart';
import 'transport/gemini_chat_transport.dart';
import 'transport/llm_protocol.dart';
import 'transport/openai_chat_transport.dart';
import 'transport/openrouter_chat_transport.dart';
import 'transport/transport_factory.dart';

final studioStreamingOutputsProvider = StateProvider.family
    .autoDispose<List<Map<String, dynamic>>, String>((ref, _) => const []);

final studioLastRequestProvider =
    StateProvider.family<StudioRequestPreview?, String>((ref, _) => null);

final studioRuntimeStateProvider = StateProvider<StudioRuntimeState>(
  (_) => const StudioRuntimeState.idle(),
);

const _mandatoryBlockIds = {'char_card', 'char_personality', 'user_persona'};
const _studioAgentStartDelay = Duration(seconds: 2);

class StudioRuntimeState {
  final String? sessionId;
  final String? agentId;
  final String? agentName;
  final int index;
  final int total;
  final bool canFinishAgent;

  const StudioRuntimeState({
    required this.sessionId,
    required this.agentId,
    required this.agentName,
    required this.index,
    required this.total,
    required this.canFinishAgent,
  });

  const StudioRuntimeState.idle()
    : sessionId = null,
      agentId = null,
      agentName = null,
      index = 0,
      total = 0,
      canFinishAgent = false;
}

class StudioRequestPreview {
  final String agentId;
  final String agentName;
  final String protocol;
  final String model;
  final int tokenEstimate;
  final int contextSize;
  final List<Map<String, dynamic>> messages;
  final Map<String, dynamic> body;

  const StudioRequestPreview({
    required this.agentId,
    required this.agentName,
    required this.protocol,
    required this.model,
    required this.tokenEstimate,
    required this.contextSize,
    required this.messages,
    required this.body,
  });
}

/// Session-bound Studio pipeline.
///
/// The Studio menu stores a user-editable [StudioConfig]. At generation time
/// this service runs enabled agents in order. Intermediate agents produce
/// compact briefs; the last enabled agent produces the actual RP response.
class MemoryStudioService {
  final Ref _ref;
  Completer<void>? _finishCurrentAgent;
  final Map<String, _CachedStudioBrief> _briefCache = {};

  MemoryStudioService(this._ref);

  void finishCurrentAgent() {
    final completer = _finishCurrentAgent;
    if (completer == null || completer.isCompleted) {
      _log('finish current agent ignored: no active agent');
      return;
    }
    _log('finish current agent requested');
    completer.complete();
  }

  Future<StudioConfig?> getEnabledConfig(String sessionId) async {
    _log('load config session=$sessionId');
    final config = await _ref
        .read(studioConfigRepoProvider)
        .getBySessionId(sessionId);
    if (config == null) {
      _log('config missing session=$sessionId');
      return null;
    }
    if (!config.enabled) {
      _log('config disabled session=$sessionId agents=${config.agents.length}');
      return null;
    }
    final enabledAgents = config.agents.where((a) => a.enabled).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    if (enabledAgents.isEmpty) {
      _log('config has no enabled agents session=$sessionId');
      return null;
    }
    _log(
      'config enabled session=$sessionId agents=${enabledAgents.length} '
      'runApi=${config.runApiConfigId.isEmpty ? '<active>' : config.runApiConfigId}',
    );
    return config.copyWith(agents: enabledAgents);
  }

  /// Run configured Studio agents. Returns the final response + agent briefs.
  Future<StudioPipelineResult> runPipeline({
    required StudioConfig config,
    required PromptResult promptResult,
    required PromptPayload promptPayload,
    required ApiConfig apiConfig,
    required String sessionId,
    CancelToken? cancelToken,
    void Function(String text, String? reasoning)? onFinalResponseUpdate,
  }) async {
    final token = cancelToken ?? CancelToken();
    if (token.isCancelled) {
      return const StudioPipelineResult(status: 'aborted', response: '');
    }

    try {
      final agents = config.agents.where((a) => a.enabled).toList()
        ..sort((a, b) => a.order.compareTo(b.order));
      if (agents.isEmpty) {
        _log('pipeline disabled: no enabled agents session=$sessionId');
        return const StudioPipelineResult(status: 'disabled', response: '');
      }

      _log(
        'pipeline start session=$sessionId agents=${agents.length} '
        'messages=${promptResult.messages.length}',
      );
      _ref.read(studioStreamingOutputsProvider(sessionId).notifier).state =
          const [];

      if (token.isCancelled) {
        _log('pipeline aborted before agents session=$sessionId');
        return const StudioPipelineResult(status: 'aborted', response: '');
      }

      final finalAgent = agents.last;
      final intermediateAgents = agents.sublist(0, agents.length - 1);
      _ref.read(studioRuntimeStateProvider.notifier).state = StudioRuntimeState(
        sessionId: sessionId,
        agentId: null,
        agentName: intermediateAgents.isEmpty
            ? finalAgent.name
            : 'Studio agents',
        index: 0,
        total: agents.length,
        canFinishAgent: false,
      );

      final sceneKey = _sceneCacheKey(promptPayload);
      final turnIndex = _assistantTurnCount(promptPayload);
      await _warmBriefCacheFromSession(
        sessionId: sessionId,
        currentTurnIndex: turnIndex,
      );
      final briefs = intermediateAgents.isEmpty
          ? <StudioStageBrief>[]
          : await Future.wait([
              for (var i = 0; i < intermediateAgents.length; i++)
                _runStaggeredIntermediateAgent(
                  index: i,
                  agent: intermediateAgents[i],
                  promptResult: promptResult,
                  promptPayload: promptPayload,
                  apiConfig: apiConfig,
                  config: config,
                  sessionId: sessionId,
                  cancelToken: token,
                  sceneKey: sceneKey,
                  turnIndex: turnIndex,
                ),
            ]);
      if (token.isCancelled) {
        _log('pipeline aborted after intermediate agents session=$sessionId');
        return const StudioPipelineResult(status: 'aborted', response: '');
      }

      _ref.read(studioRuntimeStateProvider.notifier).state = StudioRuntimeState(
        sessionId: sessionId,
        agentId: finalAgent.id,
        agentName: finalAgent.name,
        index: agents.length - 1,
        total: agents.length,
        canFinishAgent: true,
      );
      final agentResult = await _runAgent(
        agent: finalAgent,
        promptResult: promptResult,
        promptPayload: promptPayload,
        apiConfig: apiConfig,
        config: config,
        priorBriefs: briefs,
        sessionId: sessionId,
        cancelToken: token,
        isFinalResponse: true,
        onFinalResponseUpdate: onFinalResponseUpdate,
      );
      if (token.isCancelled) {
        _log('pipeline aborted after final agent session=$sessionId');
        return const StudioPipelineResult(status: 'aborted', response: '');
      }

      _log(
        'pipeline complete session=$sessionId finalAgent="${finalAgent.name}" '
        'chars=${agentResult.text.length} reasoning=${agentResult.reasoning.length} '
        'briefs=${briefs.length}',
      );
      return StudioPipelineResult(
        status: 'ok',
        response: agentResult.text,
        reasoning: agentResult.reasoning,
        rawResponseJson: agentResult.rawResponseJson,
        stageBriefs: briefs,
      );
    } on TimeoutException catch (e) {
      _log('pipeline timeout session=$sessionId error=${e.message}');
      return StudioPipelineResult(
        status: 'timeout',
        response: '',
        error: e.message?.isNotEmpty == true ? e.message : 'Studio timed out',
      );
    } catch (e) {
      if (token.isCancelled || (e is DioException && CancelToken.isCancel(e))) {
        _log('pipeline aborted by cancel session=$sessionId');
        return const StudioPipelineResult(status: 'aborted', response: '');
      }
      _log('pipeline error session=$sessionId error=$e');
      return StudioPipelineResult(status: 'error', response: '', error: '$e');
    } finally {
      _finishCurrentAgent = null;
      _ref.read(studioRuntimeStateProvider.notifier).state =
          const StudioRuntimeState.idle();
    }
  }

  Future<StudioStageBrief> _runStaggeredIntermediateAgent({
    required int index,
    required StudioAgent agent,
    required PromptResult promptResult,
    required PromptPayload promptPayload,
    required ApiConfig apiConfig,
    required StudioConfig config,
    required String sessionId,
    required CancelToken cancelToken,
    required String sceneKey,
    required int turnIndex,
  }) async {
    if (index > 0) {
      await Future<void>.delayed(_studioAgentStartDelay * index);
      if (cancelToken.isCancelled) {
        throw DioException.requestCancelled(
          requestOptions: RequestOptions(),
          reason: 'Studio pipeline cancelled before agent start',
        );
      }
    }
    return _runIntermediateAgentWithCache(
      index: index,
      agent: agent,
      promptResult: promptResult,
      promptPayload: promptPayload,
      apiConfig: apiConfig,
      config: config,
      sessionId: sessionId,
      cancelToken: cancelToken,
      sceneKey: sceneKey,
      turnIndex: turnIndex,
    );
  }

  Future<StudioPipelineResult> runFinalAgentOnly({
    required StudioConfig config,
    required PromptResult promptResult,
    required PromptPayload promptPayload,
    required ApiConfig apiConfig,
    required String sessionId,
    required List<StudioStageBrief> priorBriefs,
    CancelToken? cancelToken,
    void Function(String text, String? reasoning)? onFinalResponseUpdate,
  }) async {
    final token = cancelToken ?? CancelToken();
    if (token.isCancelled) {
      return const StudioPipelineResult(status: 'aborted', response: '');
    }

    try {
      final agents = config.agents.where((a) => a.enabled).toList()
        ..sort((a, b) => a.order.compareTo(b.order));
      if (agents.isEmpty) {
        return const StudioPipelineResult(status: 'disabled', response: '');
      }

      final finalAgent = agents.last;
      _ref.read(studioStreamingOutputsProvider(sessionId).notifier).state = [
        for (final brief in priorBriefs) _stageBriefToStreamingJson(brief),
      ];
      _ref.read(studioRuntimeStateProvider.notifier).state = StudioRuntimeState(
        sessionId: sessionId,
        agentId: finalAgent.id,
        agentName: finalAgent.name,
        index: agents.length - 1,
        total: agents.length,
        canFinishAgent: true,
      );

      final result = await _runAgent(
        agent: finalAgent,
        promptResult: promptResult,
        promptPayload: promptPayload,
        apiConfig: apiConfig,
        config: config,
        priorBriefs: priorBriefs,
        sessionId: sessionId,
        cancelToken: token,
        isFinalResponse: true,
        onFinalResponseUpdate: onFinalResponseUpdate,
      );
      if (token.isCancelled) {
        return const StudioPipelineResult(status: 'aborted', response: '');
      }
      return StudioPipelineResult(
        status: 'ok',
        response: result.text,
        reasoning: result.reasoning,
        rawResponseJson: result.rawResponseJson,
        stageBriefs: priorBriefs,
      );
    } on TimeoutException catch (e) {
      return StudioPipelineResult(
        status: 'timeout',
        response: '',
        error: e.message?.isNotEmpty == true ? e.message : 'Studio timed out',
      );
    } catch (e) {
      if (token.isCancelled || (e is DioException && CancelToken.isCancel(e))) {
        return const StudioPipelineResult(status: 'aborted', response: '');
      }
      return StudioPipelineResult(status: 'error', response: '', error: '$e');
    }
  }

  Future<StudioStageBrief> regenerateIntermediateAgent({
    required String sessionId,
    required String agentId,
    required PromptResult promptResult,
    required PromptPayload promptPayload,
    required ApiConfig apiConfig,
    CancelToken? cancelToken,
  }) async {
    final config = await getEnabledConfig(sessionId);
    if (config == null) {
      throw Exception('Studio is not enabled for this session');
    }
    final agents = config.agents.where((a) => a.enabled).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    if (agents.length < 2) {
      throw Exception('Studio has no intermediate agents to regenerate');
    }
    final agentIndex = agents.indexWhere((a) => a.id == agentId);
    if (agentIndex < 0 || agentIndex == agents.length - 1) {
      throw Exception('Studio output is not an intermediate agent');
    }
    final token = cancelToken ?? CancelToken();
    final brief = await _runIntermediateAgentSafely(
      index: agentIndex,
      agent: agents[agentIndex],
      promptResult: promptResult,
      promptPayload: promptPayload,
      apiConfig: apiConfig,
      config: config,
      sessionId: sessionId,
      cancelToken: token,
      captureErrors: false,
    );
    return brief;
  }

  Future<StudioStageBrief> _runIntermediateAgentSafely({
    required int index,
    required StudioAgent agent,
    required PromptResult promptResult,
    required PromptPayload promptPayload,
    required ApiConfig apiConfig,
    required StudioConfig config,
    required String sessionId,
    required CancelToken cancelToken,
    bool captureErrors = true,
  }) async {
    _updateStreamingBrief(
      sessionId: sessionId,
      agent: agent,
      brief: 'Running...',
      status: 'running',
    );
    try {
      final result = await _runAgent(
        agent: agent,
        promptResult: promptResult,
        promptPayload: promptPayload,
        apiConfig: apiConfig,
        config: config,
        priorBriefs: const [],
        sessionId: sessionId,
        cancelToken: cancelToken,
        isFinalResponse: false,
        allowManualFinish: false,
        onIntermediateUpdate: (text) {
          _updateStreamingBrief(
            sessionId: sessionId,
            agent: agent,
            brief: text,
            status: 'running',
          );
        },
      );
      _updateStreamingBrief(
        sessionId: sessionId,
        agent: agent,
        brief: result.text,
        status: 'ok',
      );
      _log(
        'brief stored session=$sessionId agent="${agent.name}" '
        'index=$index chars=${result.text.length}',
      );
      return StudioStageBrief(
        agentId: agent.id,
        agentName: agent.name,
        brief: result.text,
        disposition: MemoryStudioOutputDisposition.ephemeral,
      );
    } catch (e) {
      if (!captureErrors ||
          cancelToken.isCancelled ||
          (e is DioException && CancelToken.isCancel(e))) {
        rethrow;
      }
      final error = formatError(e);
      _updateStreamingBrief(
        sessionId: sessionId,
        agent: agent,
        brief: error,
        status: 'error',
        error: error,
      );
      _log('brief error session=$sessionId agent="${agent.name}" error=$error');
      return StudioStageBrief(
        agentId: agent.id,
        agentName: agent.name,
        brief: 'Studio agent failed: $error',
        disposition: MemoryStudioOutputDisposition.ephemeral,
        status: 'error',
        error: error,
      );
    }
  }

  Future<StudioStageBrief> _runIntermediateAgentWithCache({
    required int index,
    required StudioAgent agent,
    required PromptResult promptResult,
    required PromptPayload promptPayload,
    required ApiConfig apiConfig,
    required StudioConfig config,
    required String sessionId,
    required CancelToken cancelToken,
    required String sceneKey,
    required int turnIndex,
  }) async {
    final policy = _effectiveRefreshPolicy(agent);
    final cacheKey = _cacheKeyForAgent(
      config: config,
      agent: agent,
      policy: policy,
      sceneKey: sceneKey,
    );
    final cached = _usableCachedBrief(
      cacheKey: cacheKey,
      policy: policy,
      sceneChanged: _lastUserMessageSuggestsSceneChange(promptPayload),
      turnIndex: turnIndex,
    );
    if (cached != null) {
      final brief = StudioStageBrief(
        agentId: agent.id,
        agentName: agent.name,
        brief: cached.brief,
        disposition: MemoryStudioOutputDisposition.ephemeral,
        status: 'cached',
        refreshPolicy: policy,
        cacheKey: cacheKey,
        cacheHit: true,
      );
      _updateStreamingBrief(
        sessionId: sessionId,
        agent: agent,
        brief: cached.brief,
        status: 'cached',
        refreshPolicy: policy,
        cacheHit: true,
      );
      _log(
        'brief cache hit session=$sessionId agent="${agent.name}" '
        'policy=$policy index=$index',
      );
      return brief;
    }

    final brief = await _runIntermediateAgentSafely(
      index: index,
      agent: agent,
      promptResult: promptResult,
      promptPayload: promptPayload,
      apiConfig: apiConfig,
      config: config,
      sessionId: sessionId,
      cancelToken: cancelToken,
    );
    if (!cancelToken.isCancelled &&
        brief.status == 'ok' &&
        _isCacheablePolicy(policy)) {
      _briefCache[cacheKey] = _CachedStudioBrief(
        brief: brief.brief,
        policy: policy,
        createdTurnIndex: turnIndex,
      );
      _log(
        'brief cache store session=$sessionId agent="${agent.name}" '
        'policy=$policy index=$index',
      );
    }
    return brief.copyWithCacheMetadata(
      refreshPolicy: policy,
      cacheKey: _isCacheablePolicy(policy) ? cacheKey : null,
    );
  }

  Future<_StudioAgentRunResult> _runAgent({
    required StudioAgent agent,
    required PromptResult promptResult,
    required PromptPayload promptPayload,
    required ApiConfig apiConfig,
    required StudioConfig config,
    required List<StudioStageBrief> priorBriefs,
    required String sessionId,
    required CancelToken cancelToken,
    required bool isFinalResponse,
    bool allowManualFinish = true,
    void Function(String text, String? reasoning)? onFinalResponseUpdate,
    void Function(String text)? onIntermediateUpdate,
  }) async {
    final resolved = await _resolveAgentConfig(agent, apiConfig, sessionId);
    if (resolved.endpoint.isEmpty || resolved.model.isEmpty) {
      throw Exception('Studio agent "${agent.name}" API is not configured');
    }

    final completer = Completer<_StudioAgentRunResult>();
    final finishCompleter = Completer<void>();
    if (allowManualFinish) _finishCurrentAgent = finishCompleter;
    final messages = _buildAgentMessages(
      agent: agent,
      promptResult: promptResult,
      promptPayload: promptPayload,
      config: config,
      priorBriefs: priorBriefs,
      isFinalResponse: isFinalResponse,
    );
    final requestMessages =
        isFinalResponse &&
            (!resolved.requestReasoning || resolved.omitReasoning)
        ? _stripPromptLevelReasoning(messages)
        : messages;
    final shouldStream = resolved.stream;
    final request = ChatTransportRequest(
      endpoint: resolved.endpoint,
      apiKey: resolved.apiKey,
      model: resolved.model,
      messages: requestMessages,
      maxTokens: agent.maxTokens,
      temperature: agent.temperature,
      topP: resolved.topP,
      topK: resolved.topK,
      frequencyPenalty: resolved.frequencyPenalty,
      presencePenalty: resolved.presencePenalty,
      stream: shouldStream,
      requestReasoning: isFinalResponse ? resolved.requestReasoning : false,
      reasoningEffort: isFinalResponse ? resolved.reasoningEffort : null,
      omitTemperature: resolved.omitTemperature,
      omitTopP: resolved.omitTopP,
      omitReasoning: isFinalResponse ? resolved.omitReasoning : true,
      omitReasoningEffort: isFinalResponse
          ? resolved.omitReasoningEffort
          : true,
      sessionId: sessionId,
      cacheControlTtl: resolved.cacheControlTtl,
      cacheBreakpointMode: resolved.cacheBreakpointMode,
      sessionIdMode: resolved.sessionIdMode,
    );
    _ref
        .read(studioLastRequestProvider(sessionId).notifier)
        .state = StudioRequestPreview(
      agentId: agent.id,
      agentName: agent.name,
      protocol: resolved.protocol,
      model: resolved.model,
      tokenEstimate: estimateTokens(
        requestMessages.map((m) => m['content']?.toString() ?? '').join('\n'),
      ),
      contextSize: resolved.contextSize,
      messages: requestMessages,
      body: _buildRequestPreviewBody(resolved.protocol, request),
    );
    final transport = pickChatTransport(resolved.protocol);
    final startedAt = DateTime.now();
    final timeoutMs = _effectiveTimeoutMs(agent, isFinalResponse);
    final output = StringBuffer();
    final reasoning = StringBuffer();
    Timer? idleTimer;
    CancelToken? agentCancelToken;
    var finishRequested = false;
    void completeWithAccumulated(String reason) {
      if (completer.isCompleted) return;
      final text = output.toString().trim();
      final reasoningText = isFinalResponse ? reasoning.toString().trim() : '';
      _log(
        'agent finish accumulated session=$sessionId name="${agent.name}" '
        'reason=$reason chars=${text.length} reasoning=${reasoningText.length}',
      );
      completer.complete(
        _StudioAgentRunResult(text: text, reasoning: reasoningText),
      );
    }

    void resetAgentTimer() {
      idleTimer?.cancel();
      idleTimer = Timer(Duration(milliseconds: timeoutMs), () {
        if (shouldStream && (output.isNotEmpty || reasoning.isNotEmpty)) {
          completeWithAccumulated('idle_timeout');
          agentCancelToken?.cancel('Studio agent idle timeout');
        } else if (!completer.isCompleted) {
          completer.completeError(
            TimeoutException(
              'Studio agent "${agent.name}" timed out after ${timeoutMs}ms',
            ),
          );
        }
      });
    }

    final inputChars = requestMessages.fold<int>(
      0,
      (sum, m) => sum + (m['content']?.toString().length ?? 0),
    );
    _log(
      'agent start session=$sessionId name="${agent.name}" '
      'final=$isFinalResponse source=${agent.modelSource} '
      'protocol=${resolved.protocol} model=${resolved.model} '
      'messages=${requestMessages.length} inputChars=$inputChars '
      'stream=$shouldStream maxTokens=${agent.maxTokens} temp=${agent.temperature} '
      'timeoutMs=$timeoutMs persistedTimeoutMs=${agent.timeoutMs}',
    );

    agentCancelToken = CancelToken();
    unawaited(
      cancelToken.whenCancel.then((_) {
        if (!(agentCancelToken?.isCancelled ?? true)) {
          agentCancelToken?.cancel('Studio pipeline cancelled');
        }
      }),
    );
    if (allowManualFinish) {
      unawaited(
        finishCompleter.future.then((_) {
          finishRequested = true;
          completeWithAccumulated('manual_finish');
          if (!(agentCancelToken?.isCancelled ?? true)) {
            agentCancelToken?.cancel('Studio agent manually finished');
          }
        }),
      );
    }
    resetAgentTimer();

    unawaited(
      transport.stream(
        request: request,
        cancelToken: agentCancelToken,
        onUpdate: (delta, reasoningDelta) {
          if (delta.isNotEmpty) output.write(delta);
          if (isFinalResponse && delta.isNotEmpty) {
            onFinalResponseUpdate?.call(
              output.toString().trimLeft(),
              reasoning.isNotEmpty ? reasoning.toString() : null,
            );
          } else if (!isFinalResponse && delta.isNotEmpty) {
            onIntermediateUpdate?.call(output.toString().trimLeft());
          }
          if (reasoningDelta != null && reasoningDelta.isNotEmpty) {
            reasoning.write(reasoningDelta);
            if (isFinalResponse) {
              onFinalResponseUpdate?.call(
                output.toString().trimLeft(),
                reasoning.toString(),
              );
            }
          }
          if (delta.isNotEmpty || reasoningDelta?.isNotEmpty == true) {
            resetAgentTimer();
          }
        },
        onComplete: (text, finalReasoning, {rawResponseJson}) {
          final elapsed = DateTime.now().difference(startedAt).inMilliseconds;
          idleTimer?.cancel();
          if (shouldStream && output.isEmpty && text.isNotEmpty) {
            output.write(text);
          }
          if (isFinalResponse) {
            final accumulated = output.toString().trimLeft();
            final reasoningText = reasoning.isNotEmpty
                ? reasoning.toString()
                : finalReasoning?.trim().isNotEmpty == true
                ? finalReasoning!.trim()
                : null;
            if (accumulated.isNotEmpty) {
              onFinalResponseUpdate?.call(accumulated, reasoningText);
            } else if (text.isNotEmpty) {
              onFinalResponseUpdate?.call(text.trimLeft(), reasoningText);
            }
          } else {
            final accumulated = output.toString().trimLeft();
            if (accumulated.isNotEmpty) {
              onIntermediateUpdate?.call(accumulated);
            } else if (text.isNotEmpty) {
              onIntermediateUpdate?.call(text.trimLeft());
            }
          }
          _log(
            'agent complete session=$sessionId name="${agent.name}" '
            'elapsedMs=$elapsed chars=${text.trim().length} '
            'rawJson=${rawResponseJson?.length ?? 0}',
          );
          if (!completer.isCompleted) {
            final accumulated = output.toString().trim();
            final reasoningText = isFinalResponse
                ? reasoning.isNotEmpty
                      ? reasoning.toString().trim()
                      : finalReasoning?.trim() ?? ''
                : '';
            completer.complete(
              _StudioAgentRunResult(
                text: shouldStream && accumulated.isNotEmpty
                    ? accumulated
                    : text.trim(),
                reasoning: reasoningText,
                rawResponseJson: rawResponseJson,
              ),
            );
          }
        },
        onError: (error) {
          final elapsed = DateTime.now().difference(startedAt).inMilliseconds;
          idleTimer?.cancel();
          if (finishRequested && completer.isCompleted) return;
          if (shouldStream &&
              (agentCancelToken?.isCancelled ?? false) &&
              output.isNotEmpty) {
            completeWithAccumulated('cancel_with_streamed_text');
            return;
          }
          _log(
            'agent error session=$sessionId name="${agent.name}" '
            'elapsedMs=$elapsed error=$error',
          );
          if (!completer.isCompleted) completer.completeError(error);
        },
      ),
    );

    return completer.future.whenComplete(() {
      idleTimer?.cancel();
      if (allowManualFinish &&
          identical(_finishCurrentAgent, finishCompleter)) {
        _finishCurrentAgent = null;
      }
    });
  }

  Future<_ResolvedAgentConfig> _resolveAgentConfig(
    StudioAgent agent,
    ApiConfig current,
    String sessionId,
  ) async {
    if (agent.modelSource == 'custom') {
      await _ref.read(apiListProvider.future);
      final apiConfigs =
          _ref.read(apiListProvider).value ?? const <ApiConfig>[];
      final selected = apiConfigs.where((c) => c.id == agent.model).firstOrNull;
      if (selected != null) {
        return _ResolvedAgentConfig.fromApiConfig(
          selected,
          modelOverride: agent.modelOverride,
        );
      }
      return _ResolvedAgentConfig(
        endpoint: agent.endpoint,
        apiKey: current.apiKey,
        model: agent.modelOverride.isNotEmpty
            ? agent.modelOverride
            : agent.model,
        protocol: LlmProtocol.openai,
        stream: current.stream,
      );
    }

    await _ref.read(apiListProvider.future);
    final apiConfigs = _ref.read(apiListProvider).value ?? const <ApiConfig>[];
    final configRunId = await _readRunApiConfigId(sessionId);
    final selected = configRunId.isNotEmpty
        ? apiConfigs.where((c) => c.id == configRunId).firstOrNull
        : null;
    final active = selected ?? _ref.read(activeApiConfigProvider) ?? current;
    return _ResolvedAgentConfig.fromApiConfig(
      active,
      modelOverride: agent.modelOverride,
    );
  }

  Future<String> _readRunApiConfigId(String sessionId) async {
    final config = await _ref
        .read(studioConfigRepoProvider)
        .getBySessionId(sessionId);
    return config?.runApiConfigId ?? '';
  }

  List<Map<String, dynamic>> _buildAgentMessages({
    required StudioAgent agent,
    required PromptResult promptResult,
    required PromptPayload promptPayload,
    required StudioConfig config,
    required List<StudioStageBrief> priorBriefs,
    required bool isFinalResponse,
  }) {
    final studioPreset = studioRequestPresetById(
      isFinalResponse ? config.finalStudioPresetId : config.agentStudioPresetId,
      finalPreset: isFinalResponse,
      overrides: config.studioPresetOverrides,
    );
    final context = _studioContextBuckets(
      promptResult,
      promptPayload: promptPayload,
    );
    final blocks = studioPreset.blocks.where((b) => b.enabled).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    final messages = <Map<String, dynamic>>[];

    for (final block in blocks) {
      switch (block.kind) {
        case 'agent_instruction':
          final control = StringBuffer();
          final promptShard = _expandStudioBlockContent(
            agent.promptShard,
            promptPayload: promptPayload,
            promptResult: promptResult,
            context: context,
          ).trim();
          if (promptShard.isNotEmpty) {
            control
              ..writeln(promptShard)
              ..writeln();
          }
          control.writeln(
            _expandStudioBlockContent(
              block.content,
              promptPayload: promptPayload,
              promptResult: promptResult,
              context: context,
            ).trim(),
          );
          messages.add({
            'role': _normalizeRole(
              block.role.isNotEmpty ? block.role : agent.role,
            ),
            'content': control.toString().trim(),
          });
          break;
        case 'previous_agents':
          if (!isFinalResponse) break;
          messages.addAll(
            priorBriefs
                .where((b) => b.brief.trim().isNotEmpty)
                .map(
                  (b) => {
                    'role': _normalizeRole(block.role),
                    'content': 'Studio agent brief: ${b.agentName}\n${b.brief}',
                  },
                ),
          );
          break;
        case 'static_context':
          messages.addAll(context.staticContext.map((m) => m.toApiMap()));
          break;
        case 'chat_history':
          messages.addAll(context.history.map((m) => m.toApiMap()));
          break;
        case 'dynamic_context':
          messages.addAll(context.dynamicContext.map((m) => m.toApiMap()));
          break;
        default:
          final promptMessages = context.messagesForKind(block.kind);
          if (promptMessages.isNotEmpty) {
            messages.addAll(promptMessages.map((m) => m.toApiMap()));
            break;
          }
          final content = _expandStudioBlockContent(
            block.content,
            promptPayload: promptPayload,
            promptResult: promptResult,
            context: context,
          ).trim();
          if (content.isNotEmpty) {
            messages.add({
              'role': _normalizeRole(block.role),
              'content': content,
            });
          }
      }
    }

    return messages;
  }

  List<Map<String, dynamic>> _stripPromptLevelReasoning(
    List<Map<String, dynamic>> messages,
  ) {
    return [
      for (final message in messages)
        {
          ...message,
          if (message['content'] is String)
            'content': _stripThinkDirective(message['content'] as String),
        },
    ];
  }

  String _stripThinkDirective(String content) {
    var result = content;
    final patterns = <RegExp>[
      RegExp(
        r'\s*Plan internally[^.]*<think>[\s\S]*?(?:after\s*</think>|</think>)[^.]*\. ?',
        caseSensitive: false,
      ),
      RegExp(
        r'\s*Think internally[^.]*<think>[\s\S]*?(?:after\s*</think>|</think>)[^.]*\. ?',
        caseSensitive: false,
      ),
      RegExp(
        r'\s*Use\s+<think>[\s\S]*?</think>\s*(?:for|to)[^.]*\. ?',
        caseSensitive: false,
      ),
    ];
    for (final pattern in patterns) {
      result = result.replaceAll(pattern, ' ');
    }
    result = result.replaceAll('<think>', 'hidden reasoning');
    result = result.replaceAll('</think>', 'hidden reasoning');
    result = result.replaceAll(RegExp(r'\s{2,}'), ' ');
    return result.trim();
  }

  String _expandStudioBlockContent(
    String content, {
    required PromptPayload promptPayload,
    required PromptResult promptResult,
    required _StudioContextBuckets context,
  }) {
    if (!content.contains('{')) return content;
    final macroCtx = MacroContext(
      charName: promptPayload.character.name,
      charDescription: promptPayload.character.description,
      charScenario: promptPayload.character.scenario,
      charPersonality: promptPayload.character.personality,
      charMesExample: promptPayload.character.mesExample,
      userName: promptPayload.persona?.name ?? 'User',
      personaPrompt: promptPayload.persona?.prompt,
      reasoningStart: promptPayload.preset?.reasoningStart,
      reasoningEnd: promptPayload.preset?.reasoningEnd,
      sessionVars: promptResult.sessionVars,
      globalVars: promptResult.globalVars,
      charId: promptPayload.character.id,
      sessionId: promptPayload.sessionId ?? '',
      summaryContent:
          promptPayload.summaryContent ?? context.joinKind('summary'),
      memoryContent:
          promptPayload.memoryMacroContent ??
          promptPayload.memoryContent ??
          context
              .joinKind('memory')
              .ifBlank(context.taggedDynamicContent('summary')),
      lorebooksContent:
          [
                context.joinKind('worldInfoBefore'),
                context.joinKind('worldInfoAfter'),
              ]
              .where((value) => value.trim().isNotEmpty)
              .join('\n\n')
              .ifBlank(context.taggedDynamicContent('lorebooks')),
      guidanceText: promptPayload.guidanceText,
      macroName: promptPayload.character.macroName,
      arcContent: promptPayload.arcContent,
      entitiesContent: promptPayload.entitiesContent,
    );
    return replaceMacros(content, macroCtx).text;
  }

  _StudioContextBuckets _studioContextBuckets(
    PromptResult promptResult, {
    required PromptPayload promptPayload,
  }) {
    final staticIds = <String>{
      'char_card',
      'char_personality',
      'user_persona',
      'scenario',
      'example_dialogue',
      'authors_note',
    };
    final dynamicIds = <String>{
      'memory',
      'summary',
      'worldInfoBefore',
      'worldInfoAfter',
      'guided_generation',
    };
    final presetBlockNames = <String, String>{
      for (final b in promptPayload.preset?.blocks ?? const <PresetBlock>[])
        normalizeBlockId(b.id): b.name,
    };
    final mandatoryFallback = _mandatoryCharacterPersonaContext(
      promptResult,
      promptPayload,
      presetBlockNames,
    ).where((m) => !promptResult.messages.any((p) => p.blockId == m.blockId));

    final staticContext = <PromptMessage>[];
    final dynamicContext = <PromptMessage>[];
    final history = <PromptMessage>[];
    final byKind = <String, List<PromptMessage>>{};
    void addByKind(String kind, PromptMessage message) {
      byKind.putIfAbsent(kind, () => <PromptMessage>[]).add(message);
    }

    for (final message in promptResult.messages) {
      if (message.content.trim().isEmpty) continue;
      final blockId = message.blockId;
      if (message.isHistory) {
        history.add(message);
      } else if (blockId != null && staticIds.contains(blockId)) {
        addByKind(blockId, message);
      } else if (blockId != null && dynamicIds.contains(blockId)) {
        addByKind(blockId, message);
      } else if (_isStudioDynamicMessage(message, dynamicIds)) {
        dynamicContext.add(message);
      } else {
        staticContext.add(message);
      }
    }

    for (final m in mandatoryFallback) {
      final blockId = m.blockId;
      final fallback = PromptMessage(
        role: 'system',
        content:
            '[Mandatory fallback: ${_studioBlockLabel(m, presetBlockNames)}]\n${_trimForStudioContext(m.content, 6000)}',
        blockId: blockId,
        blockName: m.blockName,
      );
      if (blockId != null && blockId.isNotEmpty) {
        byKind
            .putIfAbsent(blockId, () => <PromptMessage>[])
            .insert(0, fallback);
      } else {
        staticContext.insert(0, fallback);
      }
    }

    return _StudioContextBuckets(
      staticContext: staticContext,
      history: history,
      dynamicContext: dynamicContext,
      byKind: byKind,
    );
  }

  bool _isStudioDynamicMessage(PromptMessage message, Set<String> dynamicIds) {
    final blockId = message.blockId;
    if (message.isSummary || message.isLorebook) return true;
    if (blockId != null && dynamicIds.contains(blockId)) return true;
    if (blockId != null && blockId.startsWith('runtime_prompt:')) return true;

    final name = (message.blockName ?? '').toLowerCase();
    if (name.contains('dynamic') ||
        name.contains('memory') ||
        name.contains('summary') ||
        name.contains('lore') ||
        name.contains('world info') ||
        name.contains('arc') ||
        name.contains('entit')) {
      return true;
    }

    final content = message.content.toLowerCase();
    return content.contains('<lorebooks>') ||
        content.contains('<summary>') ||
        content.contains('<memory>') ||
        content.contains('<arc') ||
        content.contains('<entities>');
  }

  List<PromptMessage> _mandatoryCharacterPersonaContext(
    PromptResult promptResult,
    PromptPayload promptPayload,
    Map<String, String> presetBlockNames,
  ) {
    final existing = promptResult.messages
        .where((m) => _mandatoryBlockIds.contains(m.blockId))
        .where((m) => m.content.trim().isNotEmpty)
        .toList();
    final found = existing.map((m) => m.blockId).whereType<String>().toSet();
    final fallback = <PromptMessage>[...existing];
    if (!found.contains('char_card')) {
      final character = promptPayload.character;
      final parts = <String>[
        'Name: ${character.name}',
        if ((character.description ?? '').trim().isNotEmpty)
          'Description:\n${character.description}',
        if ((character.scenario ?? '').trim().isNotEmpty)
          'Scenario:\n${character.scenario}',
        if ((character.systemPrompt ?? '').trim().isNotEmpty)
          'System prompt:\n${character.systemPrompt}',
        if ((character.postHistoryInstructions ?? '').trim().isNotEmpty)
          'Post-history instructions:\n${character.postHistoryInstructions}',
        if ((character.mesExample ?? '').trim().isNotEmpty)
          'Example dialogue:\n${character.mesExample}',
      ];
      fallback.add(
        PromptMessage(
          role: 'system',
          content: parts.join('\n\n'),
          blockId: 'char_card',
          blockName: presetBlockNames['char_card'] ?? 'Character Card',
        ),
      );
    }
    if (!found.contains('char_personality') &&
        (promptPayload.character.personality ?? '').trim().isNotEmpty) {
      fallback.add(
        PromptMessage(
          role: 'system',
          content: promptPayload.character.personality!,
          blockId: 'char_personality',
          blockName: presetBlockNames['char_personality'] ?? 'Personality',
        ),
      );
    }
    if (!found.contains('user_persona')) {
      final persona = promptPayload.persona;
      if (persona != null && (persona.prompt ?? '').trim().isNotEmpty) {
        fallback.add(
          PromptMessage(
            role: 'system',
            content: 'Name: ${persona.name}\n\n${persona.prompt}',
            blockId: 'user_persona',
            blockName: presetBlockNames['user_persona'] ?? 'User Persona',
          ),
        );
      }
    }
    return fallback;
  }

  String _studioBlockLabel(
    PromptMessage msg,
    Map<String, String> presetBlockNames,
  ) {
    if ((msg.blockName ?? '').trim().isNotEmpty) return msg.blockName!;
    final id = msg.blockId;
    if (id != null && (presetBlockNames[id] ?? '').trim().isNotEmpty) {
      return presetBlockNames[id]!;
    }
    return id ?? msg.role;
  }

  String _trimForStudioContext(String text, int maxChars) {
    final trimmed = text.trim();
    if (trimmed.length <= maxChars) return trimmed;
    return '${trimmed.substring(0, maxChars)}...';
  }

  String _normalizeRole(String role) {
    const allowed = {'system', 'user', 'assistant'};
    return allowed.contains(role) ? role : 'system';
  }

  int _effectiveTimeoutMs(StudioAgent agent, bool isFinalResponse) {
    final fallback = isFinalResponse ? 90000 : 60000;
    if (agent.timeoutMs <= 4000) return fallback;
    return agent.timeoutMs.clamp(1000, 120000);
  }

  void _updateStreamingBrief({
    required String sessionId,
    required StudioAgent agent,
    required String brief,
    String status = 'ok',
    String? error,
    String? refreshPolicy,
    bool cacheHit = false,
  }) {
    final trimmed = brief.trimLeft();
    if (trimmed.isEmpty) return;
    final notifier = _ref.read(
      studioStreamingOutputsProvider(sessionId).notifier,
    );
    Map<String, dynamic> itemJson() {
      final json = <String, dynamic>{
        'id': agent.id,
        'name': agent.name,
        'content': trimmed,
        'status': status,
        'refreshPolicy': refreshPolicy ?? _effectiveRefreshPolicy(agent),
      };
      if (error != null) json['error'] = error;
      if (cacheHit) json['cacheHit'] = true;
      return json;
    }

    final current = notifier.state;
    final next = <Map<String, dynamic>>[];
    var replaced = false;
    for (final item in current) {
      if (item['id'] == agent.id) {
        next.add(itemJson());
        replaced = true;
      } else {
        next.add(Map<String, dynamic>.from(item));
      }
    }
    if (!replaced) {
      next.add(itemJson());
    }
    notifier.state = next;
  }

  Map<String, dynamic> _stageBriefToStreamingJson(StudioStageBrief brief) {
    final json = <String, dynamic>{
      'id': brief.agentId,
      'name': brief.agentName,
      'content': brief.brief,
      'status': brief.status,
      'refreshPolicy': brief.refreshPolicy,
    };
    if (brief.error != null) json['error'] = brief.error;
    if (brief.cacheHit) json['cacheHit'] = true;
    if (brief.cacheKey != null) json['cacheKey'] = brief.cacheKey;
    return json;
  }

  String _normalizeRefreshPolicy(String policy) {
    return switch (policy.trim().toLowerCase()) {
      'static' || 'scene' || 'turn' => policy.trim().toLowerCase(),
      _ => 'turn',
    };
  }

  String _effectiveRefreshPolicy(StudioAgent agent) {
    final policy = _normalizeRefreshPolicy(agent.refreshPolicy);
    if (policy != 'turn' || agent.invalidationSignals.isNotEmpty) {
      return policy;
    }

    final text = [
      agent.name,
      agent.sourceBlockNames,
      agent.promptShard,
    ].join('\n').toLowerCase();
    if (RegExp(
      r'ban|banned|forbidden|clich|клиш|запрет|forbidden words',
      caseSensitive: false,
    ).hasMatch(text)) {
      return 'static';
    }
    if (RegExp(
      r'lumia|ghost in the machine',
      caseSensitive: false,
    ).hasMatch(text)) {
      return 'scene';
    }
    if (RegExp(
      r'last\s+3|recent chat|last beat|last user|continuity|memory|current scene|anti-loop|anti-echo',
      caseSensitive: false,
    ).hasMatch(text)) {
      return 'turn';
    }
    if (RegExp(
      r'tone|genre|style|romantic|fluff|comfort|lumia|ghost|director',
      caseSensitive: false,
    ).hasMatch(text)) {
      return 'scene';
    }
    return policy;
  }

  bool _isCacheablePolicy(String policy) =>
      policy == 'static' || policy == 'scene';

  _CachedStudioBrief? _usableCachedBrief({
    required String cacheKey,
    required String policy,
    required bool sceneChanged,
    required int turnIndex,
  }) {
    if (!_isCacheablePolicy(policy)) return null;
    if (policy == 'scene' && sceneChanged) return null;
    final cached = _briefCache[cacheKey];
    if (cached == null) return null;
    if (policy == 'scene' && turnIndex - cached.createdTurnIndex >= 4) {
      return null;
    }
    return cached;
  }

  Future<void> _warmBriefCacheFromSession({
    required String sessionId,
    required int currentTurnIndex,
  }) async {
    final session = await _ref.read(chatRepoProvider).getById(sessionId);
    if (session == null) return;
    for (final message in session.messages) {
      if (message.role != 'assistant') continue;
      final outputs = _storedStudioOutputsForMessage(message);
      for (final output in outputs) {
        final policy = _normalizeRefreshPolicy(
          output['refreshPolicy'] as String? ?? '',
        );
        if (!_isCacheablePolicy(policy)) continue;
        final cacheKey = output['cacheKey'] as String? ?? '';
        final content = output['content'] as String? ?? '';
        if (cacheKey.isEmpty || content.trim().isEmpty) continue;
        _briefCache.putIfAbsent(
          cacheKey,
          () => _CachedStudioBrief(
            brief: content,
            policy: policy,
            createdTurnIndex: currentTurnIndex,
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> _storedStudioOutputsForMessage(
    ChatMessage message,
  ) {
    final outputs = <Map<String, dynamic>>[];
    void addOutputs(Object? raw) {
      if (raw is! List) return;
      for (final item in raw.whereType<Map<dynamic, dynamic>>()) {
        outputs.add(Map<String, dynamic>.from(item));
      }
    }

    addOutputs(message.studioOutputs);
    for (final meta in message.swipesMeta) {
      addOutputs(meta['studioOutputs']);
    }
    return outputs;
  }

  String _cacheKeyForAgent({
    required StudioConfig config,
    required StudioAgent agent,
    required String policy,
    required String sceneKey,
  }) {
    final base = <String, dynamic>{
      'v': 1,
      'profileId': config.profileId,
      'sourcePresetHash': config.sourcePresetHash,
      'configUpdatedAt': config.updatedAt,
      'agentId': agent.id,
      'promptShard': agent.promptShard,
      'sourceBlockNames': agent.sourceBlockNames,
      'refreshPolicy': policy,
      'invalidationSignals': agent.invalidationSignals,
      'agentPreset': config.agentStudioPresetId,
      'finalPreset': config.finalStudioPresetId,
      if (policy == 'scene') 'sceneKey': sceneKey,
    };
    return computeHash(jsonEncode(base));
  }

  String _sceneCacheKey(PromptPayload payload) {
    final summary = payload.summaryContent?.trim() ?? '';
    final authorsNote = payload.authorsNote?.content.trim() ?? '';
    final recentAssistants = payload.history
        .where((m) => m.role == 'assistant')
        .length;
    return computeHash(
      jsonEncode({
        'characterId': payload.character.id,
        'personaId': payload.persona?.id ?? '',
        'summary': summary,
        'authorsNote': authorsNote,
        'assistantBucket': recentAssistants ~/ 4,
      }),
    );
  }

  int _assistantTurnCount(PromptPayload payload) {
    return payload.history.where((m) => m.role == 'assistant').length;
  }

  bool _lastUserMessageSuggestsSceneChange(PromptPayload payload) {
    for (final message in payload.history.reversed) {
      if (message.role != 'user') continue;
      final text = message.content.toLowerCase();
      return RegExp(
        r'\b(new scene|next scene|time skip|timeskip|later|meanwhile|the next day|next morning|новая сцена|следующая сцена|позже|тем временем|на следующий день|утром|вечером|ночью|перенес[её]мся)\b',
        caseSensitive: false,
      ).hasMatch(text);
    }
    return false;
  }

  Map<String, dynamic> _buildRequestPreviewBody(
    String protocol,
    ChatTransportRequest request,
  ) {
    return switch (protocol) {
      LlmProtocol.anthropic => AnthropicChatTransport.buildRequest(
        request,
      ).body,
      LlmProtocol.gemini => GeminiChatTransport.buildRequest(request).body,
      LlmProtocol.openrouter => OpenAiChatTransport.buildBody(
        OpenRouterChatTransport.buildRouterRequest(request),
      ),
      _ => OpenAiChatTransport.buildBody(request),
    };
  }

  void _log(String message) {
    debugPrint('[Studio] $message');
  }
}

class _StudioContextBuckets {
  final List<PromptMessage> staticContext;
  final List<PromptMessage> history;
  final List<PromptMessage> dynamicContext;
  final Map<String, List<PromptMessage>> byKind;

  const _StudioContextBuckets({
    required this.staticContext,
    required this.history,
    required this.dynamicContext,
    required this.byKind,
  });

  List<PromptMessage> messagesForKind(String kind) =>
      byKind[kind] ?? const <PromptMessage>[];

  String joinKind(String kind) =>
      messagesForKind(kind).map((message) => message.content).join('\n\n');

  String taggedDynamicContent(String tag) {
    final buffer = StringBuffer();
    final pattern = RegExp(
      '<$tag>\\s*([\\s\\S]*?)\\s*</$tag>',
      caseSensitive: false,
    );
    for (final message in dynamicContext) {
      for (final match in pattern.allMatches(message.content)) {
        final content = match.group(1)?.trim();
        if (content != null && content.isNotEmpty) {
          if (buffer.isNotEmpty) buffer.writeln('\n');
          buffer.write(content);
        }
      }
    }
    return buffer.toString();
  }
}

extension _BlankStringFallback on String {
  String ifBlank(String fallback) => trim().isEmpty ? fallback : this;
}

class _ResolvedAgentConfig {
  final String endpoint;
  final String apiKey;
  final String model;
  final String protocol;
  final double topP;
  final int topK;
  final double frequencyPenalty;
  final double presencePenalty;
  final bool omitTemperature;
  final bool omitTopP;
  final bool requestReasoning;
  final String? reasoningEffort;
  final bool omitReasoning;
  final bool omitReasoningEffort;
  final bool stream;
  final String cacheControlTtl;
  final String cacheBreakpointMode;
  final String sessionIdMode;
  final int contextSize;

  const _ResolvedAgentConfig({
    required this.endpoint,
    required this.apiKey,
    required this.model,
    required this.protocol,
    this.topP = 1.0,
    this.topK = 0,
    this.frequencyPenalty = 0.0,
    this.presencePenalty = 0.0,
    this.omitTemperature = false,
    this.omitTopP = false,
    this.requestReasoning = false,
    this.reasoningEffort,
    this.omitReasoning = false,
    this.omitReasoningEffort = false,
    this.stream = false,
    this.cacheControlTtl = 'off',
    this.cacheBreakpointMode = 'depth',
    this.sessionIdMode = 'openrouter',
    this.contextSize = 32000,
  });

  factory _ResolvedAgentConfig.fromApiConfig(
    ApiConfig config, {
    String modelOverride = '',
  }) {
    return _ResolvedAgentConfig(
      endpoint: config.endpoint,
      apiKey: config.apiKey,
      model: modelOverride.isNotEmpty ? modelOverride : config.model,
      protocol: config.protocol,
      topP: config.topP,
      topK: config.topK,
      frequencyPenalty: config.frequencyPenalty,
      presencePenalty: config.presencePenalty,
      omitTemperature: config.omitTemperature,
      omitTopP: config.omitTopP,
      requestReasoning: config.requestReasoning,
      reasoningEffort: config.reasoningEffort,
      omitReasoning: config.omitReasoning,
      omitReasoningEffort: config.omitReasoningEffort,
      stream: config.stream,
      cacheControlTtl: config.cacheControlTtl,
      cacheBreakpointMode: config.cacheBreakpointMode,
      sessionIdMode: config.sessionIdMode,
      contextSize: config.contextSize,
    );
  }
}

class StudioPipelineResult {
  final String status;
  final String response;
  final String reasoning;
  final String? rawResponseJson;
  final List<StudioStageBrief> stageBriefs;
  final String? error;

  const StudioPipelineResult({
    required this.status,
    required this.response,
    this.reasoning = '',
    this.rawResponseJson,
    this.stageBriefs = const [],
    this.error,
  });
}

class _StudioAgentRunResult {
  final String text;
  final String reasoning;
  final String? rawResponseJson;

  const _StudioAgentRunResult({
    required this.text,
    this.reasoning = '',
    this.rawResponseJson,
  });
}

class StudioStageBrief {
  final String agentId;
  final String agentName;
  final String brief;
  final MemoryStudioOutputDisposition disposition;
  final String status;
  final String? error;
  final String refreshPolicy;
  final String? cacheKey;
  final bool cacheHit;

  const StudioStageBrief({
    required this.agentId,
    required this.agentName,
    required this.brief,
    required this.disposition,
    this.status = 'ok',
    this.error,
    this.refreshPolicy = 'turn',
    this.cacheKey,
    this.cacheHit = false,
  });

  StudioStageBrief copyWithCacheMetadata({
    required String refreshPolicy,
    String? cacheKey,
    bool cacheHit = false,
  }) {
    return StudioStageBrief(
      agentId: agentId,
      agentName: agentName,
      brief: brief,
      disposition: disposition,
      status: status,
      error: error,
      refreshPolicy: refreshPolicy,
      cacheKey: cacheKey,
      cacheHit: cacheHit,
    );
  }
}

class _CachedStudioBrief {
  final String brief;
  final String policy;
  final int createdTurnIndex;

  const _CachedStudioBrief({
    required this.brief,
    required this.policy,
    required this.createdTurnIndex,
  });
}
