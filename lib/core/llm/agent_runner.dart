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
///   individual trackers.
/// - `StudioBatchCoordinator` for batch tracker requests.
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
  /// Tracker failure handling: when [isFinalResponse] is false, any exception
  /// (timeout, transport, idle) is **caught and rethrown as
  /// [AgentRunFailedException]** so callers can retry consistently. Exhausted
  /// tracker retries abort the Studio turn before the final generator runs.
  /// The final generator rethrows normally (its failure aborts the turn).
  /// When [preResolvedConfig] is provided, [resolveAgentConfig] is skipped
  /// and the caller-supplied config is used directly. This avoids double
  /// resolution when the caller (e.g. `StudioBatchCoordinator`) has already
  /// resolved the config at grouping time. When provided, global tracker
  /// maxTokens/temperature overrides are also skipped — the agent's own
  /// values (which for batch carry the batch budget) are used instead.
  Future<AgentRunResult> runAgent({
    required StudioAgent agent,
    required List<Map<String, dynamic>> messages,
    required ApiConfig apiConfig,
    required String sessionId,
    required bool isFinalResponse,
    CancelToken? cancelToken,
    ResolvedAgentConfig? preResolvedConfig,
    String? apiConfigId,
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
        preResolvedConfig: preResolvedConfig,
        apiConfigId: apiConfigId,
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
      // Wrap so Studio tracker callers can retry and then hard-fail with a
      // tracker-specific error.
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
    ResolvedAgentConfig? preResolvedConfig,
    String? apiConfigId,
    void Function(String text, String? reasoning)? onFinalResponseUpdate,
    void Function(String text)? onIntermediateUpdate,
  }) async {
    final resolved =
        preResolvedConfig ??
        await resolveAgentConfig(
          agent,
          apiConfig,
          sessionId,
          isFinalResponse: isFinalResponse,
          apiConfigId: apiConfigId,
        );
    if (resolved.endpoint.isEmpty || resolved.model.isEmpty) {
      throw Exception('Studio agent "${agent.name}" API is not configured');
    }
    final timeoutMs = effectiveTimeoutMs(agent, isFinalResponse);
    // When preResolvedConfig is provided, skip global tracker maxTokens/
    // temperature overrides — the agent carries the batch budget (sum of
    // all group agents' maxTokens, min temperature). Global overrides are
    // for individual tracker requests; applying them to a batch would
    // overwrite the computed batch budget with a per-agent cap.
    final maxTokensOverride = preResolvedConfig != null && !isFinalResponse
        ? null
        : effectiveMaxTokens(agent, isFinalResponse);
    final temperatureOverride = preResolvedConfig != null && !isFinalResponse
        ? null
        : effectiveTemperature(agent, isFinalResponse);
    final pipeline = _ref.read(pipelineSettingsProvider);
    final effectiveResolved = isFinalResponse
        ? resolved.copyWithReasoning(
            requestReasoning: pipeline.studioAgent.studioFinalDisableReasoning
                ? false
                : pipeline.studioAgent.studioFinalRequestReasoning,
            omitReasoning: pipeline.studioAgent.studioFinalDisableReasoning
                ? true
                : pipeline.studioAgent.studioFinalOmitReasoning,
            omitReasoningEffort: pipeline.studioAgent.studioFinalOmitReasoningEffort,
            reasoningEffort: pipeline.studioAgent.studioFinalReasoningEffort,
          )
        : agent.phase == 'post_processing'
        ? resolved.copyWithReasoning(
            requestReasoning: pipeline.cleaner.postCleanerDisableReasoning
                ? false
                : pipeline.cleaner.postCleanerRequestReasoning,
            omitReasoning: pipeline.cleaner.postCleanerDisableReasoning
                ? true
                : pipeline.cleaner.postCleanerOmitReasoning,
            omitReasoningEffort: pipeline.cleaner.postCleanerOmitReasoningEffort,
            reasoningEffort: pipeline.cleaner.postCleanerReasoningEffort,
          )
        : resolved.copyWithReasoning(
            requestReasoning: pipeline.studioAgent.studioTrackerDisableReasoning
                ? false
                : pipeline.studioAgent.studioTrackerRequestReasoning,
            omitReasoning: pipeline.studioAgent.studioTrackerDisableReasoning
                ? true
                : pipeline.studioAgent.studioTrackerOmitReasoning,
            omitReasoningEffort: pipeline.studioAgent.studioTrackerOmitReasoningEffort,
            reasoningEffort: pipeline.studioAgent.studioTrackerReasoningEffort,
          );
    return _streamRunner.run(
      agent: agent,
      messages: messages,
      resolved: effectiveResolved,
      sessionId: sessionId,
      isFinalResponse: isFinalResponse,
      cancelToken: cancelToken,
      timeoutMs: timeoutMs,
      maxTokensOverride: maxTokensOverride,
      temperatureOverride: temperatureOverride,
      onFinalResponseUpdate: onFinalResponseUpdate,
      onIntermediateUpdate: onIntermediateUpdate,
    );
  }

  /// Resolve which API config an agent uses. With the 3-slot model (v55):
  /// - [apiConfigId] — if non-empty, overrides `runApiConfigId` from the
  ///   StudioConfig. Callers pass `cheapApiConfigId` for trackers,
  ///   `expensiveApiConfigId` for the final generator, `cleanerApiConfigId`
  ///   for post-processing agents. When empty, falls back to `runApiConfigId`
  ///   then to the active chat config.
  /// - Model overrides are global PipelineSettings values configured from the
  ///   Studio menu: studioFinalModelOverride for the final generator,
  ///   postCleanerModel for post-processing trackers, studioTrackerModelOverride
  ///   for pre-gen trackers. The final generator intentionally does not read
  ///   PipelineSettings.memoryBookApi.generationModel because that field belongs to MemoryBook
  ///   generation / agentic write-loop routing.
  Future<ResolvedAgentConfig> resolveAgentConfig(
    StudioAgent agent,
    ApiConfig current,
    String sessionId, {
    bool isFinalResponse = false,
    String? apiConfigId,
  }) async {
    await _ref.read(apiListProvider.future);
    final apiConfigs = _ref.read(apiListProvider).value ?? const <ApiConfig>[];
    final runApiConfigId = (apiConfigId != null && apiConfigId.isNotEmpty)
        ? apiConfigId
        : await _readRunApiConfigId(sessionId);
    final resolver = StudioApiConfigResolver(
      apiConfigs: apiConfigs,
      activeConfig: _ref.read(activeApiConfigProvider),
    );
    final pipeline = _ref.read(pipelineSettingsProvider);
    if (isFinalResponse) {
      return resolver
          .resolveAgentConfig(
            current,
            runApiConfigId,
            pipeline.studioAgent.studioFinalModelOverride,
          )
          .copyWithSampling(
            topP: pipeline.studioAgent.studioFinalTopP,
            topK: pipeline.studioAgent.studioFinalTopK,
            frequencyPenalty: pipeline.studioAgent.studioFinalFrequencyPenalty,
            presencePenalty: pipeline.studioAgent.studioFinalPresencePenalty,
            omitTemperature: pipeline.studioAgent.studioFinalOmitTemperature,
            omitTopP: pipeline.studioAgent.studioFinalOmitTopP,
          );
    } else if (agent.phase == 'post_processing') {
      if (pipeline.cleaner.postCleanerModel.isNotEmpty) {
        return resolver
            .resolveAgentConfig(
              current,
              runApiConfigId,
              pipeline.cleaner.postCleanerModel,
            )
            .copyWithSampling(
              topP: pipeline.cleaner.postCleanerTopP,
              topK: pipeline.cleaner.postCleanerTopK,
              frequencyPenalty: pipeline.cleaner.postCleanerFrequencyPenalty,
              presencePenalty: pipeline.cleaner.postCleanerPresencePenalty,
              omitTemperature: pipeline.cleaner.postCleanerOmitTemperature,
              omitTopP: pipeline.cleaner.postCleanerOmitTopP,
            );
      }
      return resolver
          .resolveAgentConfig(current, runApiConfigId, '')
          .copyWithSampling(
            topP: pipeline.cleaner.postCleanerTopP,
            topK: pipeline.cleaner.postCleanerTopK,
            frequencyPenalty: pipeline.cleaner.postCleanerFrequencyPenalty,
            presencePenalty: pipeline.cleaner.postCleanerPresencePenalty,
            omitTemperature: pipeline.cleaner.postCleanerOmitTemperature,
            omitTopP: pipeline.cleaner.postCleanerOmitTopP,
          );
    } else if (pipeline.studioAgent.studioTrackerModelOverride.isNotEmpty) {
      return resolver
          .resolveAgentConfig(
            current,
            runApiConfigId,
            pipeline.studioAgent.studioTrackerModelOverride,
          )
          .copyWithSampling(
            topP: pipeline.studioAgent.studioTrackerTopP,
            topK: pipeline.studioAgent.studioTrackerTopK,
            frequencyPenalty: pipeline.studioAgent.studioTrackerFrequencyPenalty,
            presencePenalty: pipeline.studioAgent.studioTrackerPresencePenalty,
            omitTemperature: pipeline.studioAgent.studioTrackerOmitTemperature,
            omitTopP: pipeline.studioAgent.studioTrackerOmitTopP,
          );
    }
    return resolver
        .resolveAgentConfig(current, runApiConfigId, '')
        .copyWithSampling(
          topP: pipeline.studioAgent.studioTrackerTopP,
          topK: pipeline.studioAgent.studioTrackerTopK,
          frequencyPenalty: pipeline.studioAgent.studioTrackerFrequencyPenalty,
          presencePenalty: pipeline.studioAgent.studioTrackerPresencePenalty,
          omitTemperature: pipeline.studioAgent.studioTrackerOmitTemperature,
          omitTopP: pipeline.studioAgent.studioTrackerOmitTopP,
        );
  }

  Future<String> _readRunApiConfigId(String sessionId) async {
    final config = await _ref
        .read(studioConfigRepoProvider)
        .getBySessionId(sessionId);
    return config?.runApiConfigId ?? '';
  }

  /// Per-agent idle timeout. The idle timer fires only if the model emits
  /// NO chunks (text or reasoning) within the window — once any chunk
  /// arrives the timer is cancelled entirely (see AgentStreamRunner). So
  /// this is effectively a "first-byte" timeout, not a total-generation
  /// timeout.
  ///
  /// Resolution order:
  /// 1. [StudioAgent.timeoutMs] (>4000ms, clamped to [1000, 120000]) —
  ///    per-agent override set at Studio build time.
  /// 2. [PipelineSettings.studioAgent.studioTimeoutMs] (>0, clamped to [1000, 120000])
  ///    — global user setting from the Post-Building menu.
  /// 3. hardcoded fallback: final generator 90s, trackers 60s.
  int effectiveTimeoutMs(StudioAgent agent, bool isFinalResponse) {
    final fallback = isFinalResponse ? 90000 : 60000;
    final pipeline = _ref.read(pipelineSettingsProvider);
    final slot = isFinalResponse
        ? pipeline.studioAgent.studioFinalTimeoutMs
        : agent.phase == 'post_processing'
        ? pipeline.cleaner.postCleanerTimeoutMs
        : pipeline.studioAgent.studioTrackerTimeoutMs;
    if (slot > 0) {
      return slot.clamp(1000, 120000);
    }
    if (agent.timeoutMs > 4000) {
      return agent.timeoutMs.clamp(1000, 120000);
    }
    final global = pipeline.studioAgent.studioTimeoutMs;
    if (global > 0) {
      return global.clamp(1000, 120000);
    }
    return fallback;
  }

  /// Max tokens override. Two tiers:
  /// - Final generator: [PipelineSettings.studioAgent.studioFinalMaxTokens] (>0)
  ///   overrides the per-agent default (8000).
  /// - Trackers: [PipelineSettings.studioAgent.studioTrackerMaxTokens] (>0) overrides the
  ///   per-agent default (1600). Lets the user tighten/loosen the compact JSON
  ///   brief budget for all 7 pre-gen agents at once from the Studio menu.
  /// Returns null when the relevant global override is 0 and the caller should
  /// use the agent's own value.
  int? effectiveMaxTokens(StudioAgent agent, bool isFinalResponse) {
    if (isFinalResponse) {
      final global = _ref.read(pipelineSettingsProvider).studioAgent.studioFinalMaxTokens;
      if (global > 0) return global;
      return null;
    }
    if (agent.phase == 'post_processing') {
      final cleanerGlobal = _ref
          .read(pipelineSettingsProvider)
          .cleaner.postCleanerMaxTokens;
      if (cleanerGlobal > 0) return cleanerGlobal;
      return null;
    }
    final trackerGlobal = _ref
        .read(pipelineSettingsProvider)
        .studioAgent.studioTrackerMaxTokens;
    if (trackerGlobal > 0) return trackerGlobal;
    return null;
  }

  /// Temperature override. Two tiers:
  /// - Final generator: [PipelineSettings.studioAgent.studioFinalTemperature] (>= 0)
  ///   overrides the per-agent default (0.8).
  /// - Trackers: [PipelineSettings.studioAgent.studioTrackerTemperature] (>= 0) overrides
  ///   the per-agent default (0.3). Lets the user tune the creativity of all
  ///   7 pre-gen agents at once from the Studio menu.
  /// Returns null when the relevant global override is negative and the
  /// caller should use the agent's own value.
  double? effectiveTemperature(StudioAgent agent, bool isFinalResponse) {
    if (isFinalResponse) {
      final global = _ref.read(pipelineSettingsProvider).studioAgent.studioFinalTemperature;
      if (global >= 0) return global;
      return null;
    }
    if (agent.phase == 'post_processing') {
      return _ref.read(pipelineSettingsProvider).cleaner.postCleanerTemperature;
    }
    final trackerGlobal = _ref
        .read(pipelineSettingsProvider)
        .studioAgent.studioTrackerTemperature;
    if (trackerGlobal >= 0) return trackerGlobal;
    return null;
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

/// Per-agent failure wrapper. Thrown by [AgentRunner.runAgent] for trackers
/// (non-final agents) when the underlying LLM call fails for any reason
/// (timeout, transport, parse). The caller retries and then returns a hard
/// Studio error. The final generator's failures propagate as the original
/// exception (no wrap).
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

  /// Per-call override of the reasoning-related flags. Used by
  /// [AgentRunner._runAgentInner] when `studioFinalDisableReasoning` is on.
  ResolvedAgentConfig copyWithReasoning({
    bool? requestReasoning,
    bool? omitReasoning,
    bool? omitReasoningEffort,
    String? reasoningEffort,
  }) {
    return ResolvedAgentConfig(
      endpoint: endpoint,
      apiKey: apiKey,
      model: model,
      protocol: protocol,
      topP: topP,
      topK: topK,
      frequencyPenalty: frequencyPenalty,
      presencePenalty: presencePenalty,
      omitTemperature: omitTemperature,
      omitTopP: omitTopP,
      requestReasoning: requestReasoning ?? this.requestReasoning,
      reasoningEffort: reasoningEffort ?? this.reasoningEffort,
      omitReasoning: omitReasoning ?? this.omitReasoning,
      omitReasoningEffort: omitReasoningEffort ?? this.omitReasoningEffort,
      stream: stream,
      cacheControlTtl: cacheControlTtl,
      cacheBreakpointMode: cacheBreakpointMode,
      sessionIdMode: sessionIdMode,
      contextSize: contextSize,
    );
  }

  ResolvedAgentConfig copyWithSampling({
    double? topP,
    int? topK,
    double? frequencyPenalty,
    double? presencePenalty,
    bool? omitTemperature,
    bool? omitTopP,
  }) {
    return ResolvedAgentConfig(
      endpoint: endpoint,
      apiKey: apiKey,
      model: model,
      protocol: protocol,
      topP: topP ?? this.topP,
      topK: topK ?? this.topK,
      frequencyPenalty: frequencyPenalty ?? this.frequencyPenalty,
      presencePenalty: presencePenalty ?? this.presencePenalty,
      omitTemperature: omitTemperature ?? this.omitTemperature,
      omitTopP: omitTopP ?? this.omitTopP,
      requestReasoning: requestReasoning,
      reasoningEffort: reasoningEffort,
      omitReasoning: omitReasoning,
      omitReasoningEffort: omitReasoningEffort,
      stream: stream,
      cacheControlTtl: cacheControlTtl,
      cacheBreakpointMode: cacheBreakpointMode,
      sessionIdMode: sessionIdMode,
      contextSize: contextSize,
    );
  }
}

/// Riverpod provider for [AgentRunner]. Single shared instance — it is
/// stateless beyond the injected [Ref].
final agentRunnerProvider = Provider<AgentRunner>((ref) {
  return AgentRunner(ref);
});
