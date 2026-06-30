import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/api_config.dart';
import '../models/studio_config.dart';
import '../state/pipeline_settings_provider.dart';
import '../utils/error_format.dart';
import 'agent_runner.dart';
import 'prompt_builder.dart';
import 'studio_brief_parser.dart';
import 'studio_message_builder.dart';
import 'studio_stage_brief.dart';
import 'tracker_batcher.dart';

/// Runs the per-agent LLM calls of the Studio chat-time pipeline: the
/// pre-gen tracker, the post-processing tracker, the individual (non-batch)
/// fallback tracker, and the final generator. Extracted from
/// `MemoryStudioService` (plan §2.8).
///
/// Each adapter assembles the agent's message list via the injected
/// [StudioMessageBuilder], invokes [AgentRunner.runAgent], and adapts the
/// result type to the pipeline-internal [StudioStageBrief] / [TrackerBatchResult]
/// / [StudioFinalRunResult] shapes. Tracker failures are retried by the
/// relevant adapter and returned as failed results when retries are exhausted;
/// the final generator rethrows.
class StudioAgentExecutor {
  final Ref _ref;
  final StudioMessageBuilder _messageBuilder;
  final StudioBriefParser _briefParser;

  StudioAgentExecutor(this._ref, this._messageBuilder, this._briefParser);

  /// Delegate the actual LLM call to [AgentRunner]. This method still
  /// builds the `messages` list (prompt assembly via [StudioMessageBuilder])
  /// and adapts the result type to the internal [StudioStageBrief] pipeline.
  ///
  /// When [isFinalResponse] is false, [AgentRunner.runAgent] wraps any failure
  /// into an [AgentRunFailedException]; here we unwrap it into a failed brief
  /// so callers can retry and then surface a hard Studio error. The final
  /// generator rethrows.
  Future<StudioStageBrief> runTracker({
    required StudioAgent agent,
    required PromptResult promptResult,
    required PromptPayload promptPayload,
    required ApiConfig apiConfig,
    required StudioConfig config,
    required String sessionId,
    required CancelToken cancelToken,
    void Function(String text)? onIntermediateUpdate,
  }) async {
    if (_briefParser.isMetaPolicyAgent(agent)) {
      return StudioStageBrief(
        agentId: agent.id,
        agentName: agent.name,
        brief: _briefParser.metaPolicyBrief(agent),
      );
    }
    try {
      final messages = _messageBuilder.buildAgentMessages(
        agent: agent,
        promptResult: promptResult,
        promptPayload: promptPayload,
        config: config,
        priorBriefs: const [],
        isFinalResponse: false,
      );
      final runner = _ref.read(agentRunnerProvider);
      final result = await runner.runAgent(
        agent: agent,
        messages: messages,
        apiConfig: apiConfig,
        sessionId: sessionId,
        isFinalResponse: false,
        cancelToken: cancelToken,
        onIntermediateUpdate: onIntermediateUpdate,
      );
      final sanitized = _briefParser.sanitizeIntermediateAgentOutput(
        agent,
        result.text,
      );
      return StudioStageBrief(
        agentId: agent.id,
        agentName: agent.name,
        brief: sanitized,
      );
    } on AgentRunFailedException catch (e) {
      return StudioStageBrief(
        agentId: e.agentId,
        agentName: e.agentName,
        brief: 'Studio agent failed: ${e.reason}',
        status: 'error',
        error: e.reason,
      );
    }
  }

  /// Feature 6 — run ONE post-processing tracker. The tracker receives the
  /// generator's [mainResponse] in its context (as an extra
  /// `<assistant_response>` block appended to its `dynamic_context`) and
  /// can produce an edited/rewritten version. Its raw output is returned as
  /// a `StudioStageBrief` whose `brief` field is the rewritten text (NOT
  /// sanitized through the brief-shape contract — a post-gen tracker IS
  /// allowed to produce prose, since its job is to rewrite the response).
  /// The caller decides whether the rewrite replaces `mainResponse`.
  ///
  /// Failure policy: a post-gen tracker gets the same initial attempt + two
  /// retries as pre-gen trackers. Exhausting retries returns a failed brief;
  /// the caller surfaces it as a hard Studio error instead of silently keeping
  /// the previous `mainResponse`.
  Future<StudioStageBrief> runPostProcessingTracker({
    required StudioAgent agent,
    required String mainResponse,
    required PromptResult promptResult,
    required PromptPayload promptPayload,
    required ApiConfig apiConfig,
    required StudioConfig config,
    required String sessionId,
    required CancelToken cancelToken,
  }) async {
    String? lastError;
    for (var attempt = 1; attempt <= 3; attempt++) {
      if (cancelToken.isCancelled) {
        return StudioStageBrief(
          agentId: agent.id,
          agentName: agent.name,
          brief: '',
          status: 'error',
          error: 'cancelled',
        );
      }
      try {
        final messages = _messageBuilder.buildAgentMessages(
          agent: agent,
          promptResult: promptResult,
          promptPayload: promptPayload,
          config: config,
          priorBriefs: const [],
          isFinalResponse: false,
          mainResponse: mainResponse,
        );
        final runner = _ref.read(agentRunnerProvider);
        final result = await runner.runAgent(
          agent: agent,
          messages: messages,
          apiConfig: apiConfig,
          sessionId: sessionId,
          isFinalResponse: false,
          cancelToken: cancelToken,
          onIntermediateUpdate: null,
        );
        // Post-gen trackers produce prose (a rewrite), NOT a brief — skip the
        // brief-shape sanitization that pre-gen trackers go through. Empty
        // output means "no edit needed" → caller keeps `mainResponse`. This is
        // the intentional happy-path no-op, so it is reported as 'skipped'
        // (NOT 'error') to avoid surfacing a false failure in the stage briefs.
        final text = result.text.trim();
        return StudioStageBrief(
          agentId: agent.id,
          agentName: agent.name,
          brief: text,
          status: text.isNotEmpty ? 'ok' : 'skipped',
        );
      } on AgentRunFailedException catch (e) {
        lastError = e.reason;
      }
    }
    return StudioStageBrief(
      agentId: agent.id,
      agentName: agent.name,
      brief: '',
      status: 'error',
      error: lastError ?? 'tracker failed after 2 retries',
    );
  }

  /// Run one individual tracker (not part of any batch group). Reuses the
  /// existing per-agent prompt assembly + AgentRunner.
  Future<TrackerBatchResult> runIndividualTracker({
    required StudioAgent agent,
    required StudioConfig config,
    required PromptResult promptResult,
    required PromptPayload promptPayload,
    required ApiConfig apiConfig,
    required String sessionId,
    required CancelToken cancelToken,
  }) async {
    String? lastError;
    for (var attempt = 1; attempt <= 3; attempt++) {
      if (cancelToken.isCancelled) {
        return TrackerBatchResult.failed(
          agentId: agent.id,
          agentName: agent.name,
          reason: 'cancelled',
        );
      }
      try {
        final brief = await runTracker(
          agent: agent,
          promptResult: promptResult,
          promptPayload: promptPayload,
          apiConfig: apiConfig,
          config: config,
          sessionId: sessionId,
          cancelToken: cancelToken,
          onIntermediateUpdate: null,
        );
        if (brief.status == 'ok' && brief.brief.trim().isNotEmpty) {
          return TrackerBatchResult(
            agentId: agent.id,
            agentName: agent.name,
            text: brief.brief,
            status: brief.status,
            error: brief.error,
          );
        }
        lastError = brief.error ?? 'tracker returned an empty response';
      } catch (e) {
        lastError = formatError(e);
      }
    }
    return TrackerBatchResult.failed(
      agentId: agent.id,
      agentName: agent.name,
      reason: lastError ?? 'tracker failed after 2 retries',
    );
  }

  Future<StudioFinalRunResult> runFinalGenerator({
    required StudioAgent agent,
    required PromptResult promptResult,
    required PromptPayload promptPayload,
    required ApiConfig apiConfig,
    required StudioConfig config,
    required List<StudioStageBrief> priorBriefs,
    required String sessionId,
    required CancelToken cancelToken,
    void Function(String text, String? reasoning)? onFinalResponseUpdate,
  }) async {
    final messages = _messageBuilder.buildAgentMessages(
      agent: agent,
      promptResult: promptResult,
      promptPayload: promptPayload,
      config: config,
      priorBriefs: priorBriefs,
      isFinalResponse: true,
      finalContextOverride: _ref
          .read(pipelineSettingsProvider)
          .studioFinalContextSize,
    );
    final runner = _ref.read(agentRunnerProvider);
    final result = await runner.runAgent(
      agent: agent,
      messages: messages,
      apiConfig: apiConfig,
      sessionId: sessionId,
      isFinalResponse: true,
      cancelToken: cancelToken,
      onFinalResponseUpdate: onFinalResponseUpdate,
    );
    return StudioFinalRunResult(
      text: result.text,
      reasoning: result.reasoning,
      rawResponseJson: result.rawResponseJson,
    );
  }
}

/// Final-generator run result returned by [AgentRunner.runAgent] for the
/// final agent, adapted back to the pipeline-level shape used by
/// [StudioPipelineResult]. Public so the executor's host can read its
/// fields after the run.
class StudioFinalRunResult {
  final String text;
  final String reasoning;
  final String? rawResponseJson;

  const StudioFinalRunResult({
    required this.text,
    this.reasoning = '',
    this.rawResponseJson,
  });
}
