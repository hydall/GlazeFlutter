import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/api_config.dart';
import '../models/studio_config.dart';
import '../state/db_provider.dart';
import '../utils/error_format.dart';
import '../../features/settings/api_list_provider.dart';
import 'agent_stream_runner.dart';
import 'reasoning_stripper.dart';
import 'studio_api_config_resolver.dart';
import 'transport/transport_factory.dart';

/// Thin LLM orchestrator extracted from `MemoryStudioService` (Phase 5.1,
/// port of Marinara `agent-executor.ts` single-agent execution path).
///
/// Responsibility: given a [StudioAgent] and already-built `messages`, resolve
/// the API config, build a [ChatTransportRequest], stream the LLM, accumulate
/// the output, and return it. **No prompt-building, no batching, no caching** —
/// those stay in `MemoryStudioService`.
///
/// Used by:
/// - `MemoryStudioService.runTrackerCycle` for the final generator and
///   individual tracker fallbacks.
/// - `MemoryStudioService.executeTrackerBatch` for the per-agent fallback path
///   inside a batch (this class is unaware of batching).
class AgentRunner {
  final Ref _ref;
  late final AgentStreamRunner _streamRunner = AgentStreamRunner(
    pickChatTransport,
  );

  AgentRunner(this._ref);

  /// Run a single agent against the LLM. Streaming is driven by
  /// [onFinalResponseUpdate] / [onIntermediateUpdate]; the returned
  /// [AgentRunResult] carries the final accumulated text + reasoning.
  ///
  /// [isFinalResponse] = true → the generator (final agent). Reasoning is
  /// forwarded to the UI. [isFinalResponse] = false → a tracker; reasoning
  /// is discarded (trackers are JSON/plain-text producers).
  ///
  /// Per-agent failure isolation (Phase 5.7.5): when [isFinalResponse] is
  /// false, any exception (timeout, transport, idle) is **caught and rethrown
  /// as [AgentRunFailedException]** so a single tracker cannot crash the whole
  /// pipeline — `runTrackerCycle` converts it to a failed `StudioStageBrief`.
  /// The final generator rethrows normally (its failure aborts the turn).
  Future<AgentRunResult> runAgent({
    required StudioAgent agent,
    required List<Map<String, dynamic>> messages,
    required ApiConfig apiConfig,
    required String sessionId,
    required bool isFinalResponse,
    CancelToken? cancelToken,
    void Function(String text, String? reasoning)? onFinalResponseUpdate,
    void Function(String text)? onIntermediateUpdate,
  }) async {
    final token = cancelToken ?? CancelToken();
    if (token.isCancelled) {
      throw AgentRunFailedException(
        agentId: agent.id,
        agentName: agent.name,
        reason: 'cancelled',
      );
    }

    try {
      return await _runAgentInner(
        agent: agent,
        messages: messages,
        apiConfig: apiConfig,
        sessionId: sessionId,
        isFinalResponse: isFinalResponse,
        cancelToken: token,
        onFinalResponseUpdate: onFinalResponseUpdate,
        onIntermediateUpdate: onIntermediateUpdate,
      );
    } catch (e) {
      if (token.isCancelled || (e is DioException && CancelToken.isCancel(e))) {
        throw AgentRunFailedException(
          agentId: agent.id,
          agentName: agent.name,
          reason: 'cancelled',
        );
      }
      if (isFinalResponse) rethrow;
      // Per-agent failure isolation: wrap so the caller can map to a failed
      // brief without losing the other agents' results.
      throw AgentRunFailedException(
        agentId: agent.id,
        agentName: agent.name,
        reason: formatError(e),
        cause: e,
      );
    }
  }

  Future<AgentRunResult> _runAgentInner({
    required StudioAgent agent,
    required List<Map<String, dynamic>> messages,
    required ApiConfig apiConfig,
    required String sessionId,
    required bool isFinalResponse,
    required CancelToken cancelToken,
    void Function(String text, String? reasoning)? onFinalResponseUpdate,
    void Function(String text)? onIntermediateUpdate,
  }) async {
    final resolved = await resolveAgentConfig(agent, apiConfig, sessionId);
    if (resolved.endpoint.isEmpty || resolved.model.isEmpty) {
      throw Exception('Studio agent "${agent.name}" API is not configured');
    }
    final timeoutMs = effectiveTimeoutMs(agent, isFinalResponse);
    return _streamRunner.run(
      agent: agent,
      messages: messages,
      resolved: resolved,
      sessionId: sessionId,
      isFinalResponse: isFinalResponse,
      cancelToken: cancelToken,
      timeoutMs: timeoutMs,
      onFinalResponseUpdate: onFinalResponseUpdate,
      onIntermediateUpdate: onIntermediateUpdate,
    );
  }

  /// Resolve which API config an agent uses. Ports Marinara's
  /// `resolveAgentApiConfig`:
  /// - `modelSource == 'custom'` → use the [StudioAgent.model] id to pick an
  ///   [ApiConfig] from the saved list, then apply [StudioAgent.modelOverride]
  ///   on top. If the id is unknown, fall back to the agent's own endpoint /
  ///   model fields with the *current* chat API's key.
  /// - otherwise → use the chat session's configured run API (or the active
  ///   API), with [StudioAgent.modelOverride] on top.
  Future<ResolvedAgentConfig> resolveAgentConfig(
    StudioAgent agent,
    ApiConfig current,
    String sessionId,
  ) async {
    await _ref.read(apiListProvider.future);
    final apiConfigs =
        _ref.read(apiListProvider).value ?? const <ApiConfig>[];
    final runApiConfigId = await _readRunApiConfigId(sessionId);
    final resolver = StudioApiConfigResolver(
      apiConfigs: apiConfigs,
      activeConfig: _ref.read(activeApiConfigProvider),
    );
    return resolver.resolveAgentConfig(agent, current, runApiConfigId);
  }

  Future<String> _readRunApiConfigId(String sessionId) async {
    final config = await _ref
        .read(studioConfigRepoProvider)
        .getBySessionId(sessionId);
    return config?.runApiConfigId ?? '';
  }

  /// Per-agent idle/total timeout. Final generator: 90s, trackers: 60s.
  /// Anything ≤4000ms is treated as "unset" → fallback. Clamped to
  /// [1000ms, 120000ms]. Ports Marinara `effectiveAgentTimeout`.
  int effectiveTimeoutMs(StudioAgent agent, bool isFinalResponse) {
    final fallback = isFinalResponse ? 90000 : 60000;
    if (agent.timeoutMs <= 4000) return fallback;
    return agent.timeoutMs.clamp(1000, 120000);
  }

  /// Strip `<think>`/Plan-internally directives from a message before sending
  /// to a model that won't honor them. Delegates to [ReasoningStripper]; kept
  /// as a static shim because call sites reference
  /// `AgentRunner.stripPromptLevelReasoning`.
  static List<Map<String, dynamic>> stripPromptLevelReasoning(
    List<Map<String, dynamic>> messages,
  ) => ReasoningStripper.stripMessageReasoning(messages);
}

/// Successful single-agent run. Mirrors the former `_StudioAgentRunResult`.
class AgentRunResult {
  final String text;
  final String reasoning;
  final String? rawResponseJson;

  const AgentRunResult({
    required this.text,
    this.reasoning = '',
    this.rawResponseJson,
  });
}

/// Per-agent failure wrapper (Phase 5.7.5). Thrown by [AgentRunner.runAgent]
/// for trackers (non-final agents) when the underlying LLM call fails for any
/// reason (timeout, transport, parse). The caller converts it to a failed
/// `StudioStageBrief` so the rest of the pipeline keeps going. The final
/// generator's failures propagate as the original exception (no wrap).
class AgentRunFailedException implements Exception {
  final String agentId;
  final String agentName;
  final String reason;
  final Object? cause;

  const AgentRunFailedException({
    required this.agentId,
    required this.agentName,
    required this.reason,
    this.cause,
  });

  @override
  String toString() =>
      'AgentRunFailedException(agent="$agentName" id="$agentId" reason="$reason")';
}

/// Resolved per-agent API parameters. Mirrors the former private
/// `_ResolvedAgentConfig` from `MemoryStudioService`, now public on this
/// orchestrator so `MemoryStudioService.executeTrackerBatch` can read the
/// `maxTokens` cap and `stream` flag when computing a batch budget.
class ResolvedAgentConfig {
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

  const ResolvedAgentConfig({
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

  factory ResolvedAgentConfig.fromApiConfig(
    ApiConfig config, {
    String modelOverride = '',
  }) {
    return ResolvedAgentConfig(
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

/// Riverpod provider for [AgentRunner]. Single shared instance — it is
/// stateless beyond the injected [Ref].
final agentRunnerProvider = Provider<AgentRunner>((ref) {
  return AgentRunner(ref);
});
