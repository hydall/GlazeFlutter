import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/api_config.dart';
import '../models/studio_config.dart';
import '../utils/error_format.dart';
import 'agent_runner.dart';
import 'prompt_builder.dart';
import 'studio_agent_executor.dart';
import 'studio_context_bucketizer.dart';
import 'studio_message_builder.dart';
import 'tracker_batcher.dart';

/// Runs a batch group of Studio chat-time trackers: builds the batched
/// system prompt + per-agent task text, fires a single LLM request, parses
/// the `<result>` blocks, and runs the 2-layer retry/fallback (in-batch
/// retry → individual fallback). Extracted from `MemoryStudioService`
/// (plan §2.9).
///
/// Deps: the shared [Ref] (for `trackerBatcherProvider` +
/// `agentRunnerProvider`), the injected [StudioContextBucketizer],
/// [StudioMessageBuilder], and [StudioAgentExecutor] (for the individual
/// fallback). `_log` is injected as a callback so this specialist does not
/// own the host's debug-print sink. Behavior preserved verbatim.
class StudioBatchCoordinator {
  final Ref _ref;
  final StudioContextBucketizer _bucketizer;
  final StudioMessageBuilder _messageBuilder;
  final StudioAgentExecutor _executor;
  final void Function(String message) _log;

  StudioBatchCoordinator(
    this._ref,
    this._bucketizer,
    this._messageBuilder,
    this._executor,
    this._log,
  );

  /// [batchContextSize] = max contextSize across the group), per-agent task
  /// text, the batched system prompt, fire a single LLM request, parse the
  /// `<result>` blocks, and run the in-batch invalid-JSON retry (Phase 5.1
  /// layer 1) + individual fallback (layer 2) for any agents whose blocks
  /// came back empty/failed.
  Future<List<TrackerBatchResult>> runBatchGroup({
    required TrackerBatchGroup group,
    required StudioConfig config,
    required PromptResult promptResult,
    required PromptPayload promptPayload,
    required ApiConfig apiConfig,
    required String sessionId,
    required CancelToken cancelToken,
    required int batchContextSize,
  }) async {
    final context = _bucketizer.bucketize(
      promptResult,
      promptPayload: promptPayload,
      studioConfig: config,
    );
    final sharedMessages = _messageBuilder.buildSharedBatchMessages(
      config: config,
      context: context,
      promptPayload: promptPayload,
      promptResult: promptResult,
      batchContextSize: batchContextSize,
    );
    final perAgentTask = <String, String>{};
    for (final agent in group.agents) {
      perAgentTask[agent.id] = _messageBuilder.buildPerAgentTaskText(
        agent: agent,
        config: config,
        promptResult: promptResult,
        promptPayload: promptPayload,
        context: context,
      );
    }
    final roleText = _messageBuilder.batchRoleText(
      config,
      context,
      promptPayload,
      promptResult,
    );
    final batcher = _ref.read(trackerBatcherProvider);
    final systemPrompt = batcher.buildBatchSystemPrompt(
      group: group,
      sharedMessages: sharedMessages,
      perAgentTaskText: perAgentTask,
      roleText: roleText,
    );
    // The batch instructions are the system prompt; we also send an explicit
    // user turn that triggers the batched response. A system-only message list
    // is rejected with HTTP 400 by several providers (e.g. z-ai/GLM), which
    // require at least one user message — so this user turn is mandatory, not
    // cosmetic. See docs/PLAN_AGENTIC_STUDIO.md Phase 5.
    final batchMessages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
      {
        'role': 'user',
        'content':
            'Produce the required <result> blocks now, one per agent_task '
            'listed above, in order.',
      },
    ];
    // Use a synthetic StudioAgent for the batch request: carry the group's
    // budget/temperature. The AgentRunner will resolve the API config from
    // this agent's fields (modelSource='current' → use the group's resolved
    // (provider, model) via runApiConfigId). We override maxTokens/temperature
    // on a per-call basis by passing them through ChatTransportRequest — but
    // AgentRunner.runAgent reads them off the agent. So we synthesize a
    // per-batch agent that carries the batch budget.
    final batchAgent = group.agents.first.copyWith(
      maxTokens: group.batchMaxTokens,
      temperature: group.batchTemperature,
      contextSize: batchContextSize,
    );
    final runner = _ref.read(agentRunnerProvider);
    try {
      final result = await runner.runAgent(
        agent: batchAgent,
        messages: batchMessages,
        apiConfig: apiConfig,
        sessionId: sessionId,
        isFinalResponse: false,
        cancelToken: cancelToken,
      );
      final parsed = batcher.parseBatchResponse(result.text, group);
      // Layer 1 — in-batch invalid-JSON retry: if ANY agent's block came back
      // empty/failed, re-request the WHOLE batch ONCE (the model may have
      // truncated mid-batch on the first try). If the retry succeeds, use
      // it; otherwise fall through to layer 2 (individual fallback).
      if (_allOk(parsed)) {
        return parsed;
      }
      final failedCount = parsed.where((r) => r.status != 'ok').length;
      _log(
        'batch group ${group.key} had $failedCount failed agents on first '
        'attempt — retrying batch',
      );
      final retryResult = await runner.runAgent(
        agent: batchAgent,
        messages: batchMessages,
        apiConfig: apiConfig,
        sessionId: sessionId,
        isFinalResponse: false,
        cancelToken: cancelToken,
      );
      final retryParsed = batcher.parseBatchResponse(retryResult.text, group);
      if (_allOk(retryParsed)) {
        return retryParsed;
      }
      // Layer 2 — individual fallback: take the union of failed agents from
      // BOTH attempts and re-run each one as its own LLM request, concurrency
      // limited to 2 (Phase 5.7.2).
      final failedIds = <String>{};
      for (final r in parsed.where((r) => r.status != 'ok')) {
        failedIds.add(r.agentId);
      }
      for (final r in retryParsed.where((r) => r.status != 'ok')) {
        failedIds.add(r.agentId);
      }
      // Keep the ok results from either attempt (an agent ok in attempt 1
      // but failed in attempt 2 should NOT be re-run — keep the ok version).
      final okResults = <TrackerBatchResult>[
        ...parsed.where((r) => r.status == 'ok' && !failedIds.contains(r.agentId)),
        ...retryParsed.where((r) => r.status == 'ok' && !failedIds.contains(r.agentId)),
      ];
      final failedAgents = group.agents
          .where((a) => failedIds.contains(a.id))
          .toList();
      final retried = await retryFailedIndividually(
        agents: failedAgents,
        config: config,
        promptResult: promptResult,
        promptPayload: promptPayload,
        apiConfig: apiConfig,
        sessionId: sessionId,
        cancelToken: cancelToken,
      );
      return [...okResults, ...retried];
    } on AgentRunFailedException catch (e) {
      // Whole batch request failed — fall back to individual for ALL agents
      // in this group (Phase 5.7.5 per-agent failure isolation at the batch
      // level: a single transport failure should not lose every agent).
      _log(
        'batch group ${group.key} request failed (${e.reason}) — falling '
        'back to individual for ${group.agents.length} agents',
      );
      return retryFailedIndividually(
        agents: group.agents,
        config: config,
        promptResult: promptResult,
        promptPayload: promptPayload,
        apiConfig: apiConfig,
        sessionId: sessionId,
        cancelToken: cancelToken,
      );
    }
  }

  /// Per-agent fallback (Phase 5.1 layer 2 + Phase 5.7.2). Run each failed
  /// agent as its own LLM request, concurrency-limited to 2.
  Future<List<TrackerBatchResult>> retryFailedIndividually({
    required List<StudioAgent> agents,
    required StudioConfig config,
    required PromptResult promptResult,
    required PromptPayload promptPayload,
    required ApiConfig apiConfig,
    required String sessionId,
    required CancelToken cancelToken,
  }) async {
    if (agents.isEmpty) return const [];
    final batcher = _ref.read(trackerBatcherProvider);
    return batcher.settleWithConcurrencyLimit(
      items: agents,
      limit: 2,
      run: (agent) async {
        try {
          final brief = await _executor.runTracker(
            agent: agent,
            promptResult: promptResult,
            promptPayload: promptPayload,
            apiConfig: apiConfig,
            config: config,
            sessionId: sessionId,
            cancelToken: cancelToken,
            onIntermediateUpdate: null,
          );
          return TrackerBatchResult(
            agentId: agent.id,
            agentName: agent.name,
            text: brief.brief,
            status: brief.status,
            error: brief.error,
          );
        } catch (e) {
          return TrackerBatchResult.failed(
            agentId: agent.id,
            agentName: agent.name,
            reason: formatError(e),
          );
        }
      },
    );
  }

  bool _allOk(List<TrackerBatchResult> results) {
    return results.every((r) => r.status == 'ok' && r.text.isNotEmpty);
  }
}
