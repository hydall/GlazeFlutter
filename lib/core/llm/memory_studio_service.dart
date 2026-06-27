import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/api_config.dart';
import '../models/studio_config.dart';
import '../state/db_provider.dart';
import '../utils/error_format.dart';
import 'agent_runner.dart';
import 'prompt_builder.dart';
import 'studio_activation_gate.dart';
import 'studio_brief_cache.dart';
import 'studio_brief_deduper.dart';
import 'studio_brief_parser.dart';
import 'studio_context_bucketizer.dart';
import 'studio_message_builder.dart';
import 'studio_prompt_text.dart';
import 'studio_stage_brief.dart';
import 'tracker_batcher.dart';

// Re-export so existing importers of `AgentPhaseSplit` via this file (e.g.
// tests, studio_post_processing) keep their import path after the move to
// studio_activation_gate.dart.
export 'studio_activation_gate.dart' show AgentPhaseSplit;


/// Session-bound Studio pipeline.
///
/// The Studio menu stores a user-editable [StudioConfig]. At generation time
/// this service runs enabled agents in order. Intermediate agents produce
/// compact briefs; the last enabled agent produces the actual RP response.
class MemoryStudioService {
  final Ref _ref;
  final StudioPromptText _promptText = const StudioPromptText();
  final StudioContextBucketizer _bucketizer = const StudioContextBucketizer();
  late final StudioBriefParser _briefParser = StudioBriefParser(_log);
  late final StudioBriefDeduper _briefDeduper = StudioBriefDeduper(_briefParser);
  late final StudioBriefCache _briefCache = StudioBriefCache(_briefParser);
  late final StudioMessageBuilder _messageBuilder = StudioMessageBuilder(
    _bucketizer,
    _promptText,
    _briefDeduper,
  );

  MemoryStudioService(this._ref);

  Future<StudioConfig?> getEnabledConfig(String sessionId) async {
    final config = await _ref
        .read(studioConfigRepoProvider)
        .getBySessionId(sessionId);
    if (config == null) {
      return null;
    }
    if (!config.enabled) {
      return null;
    }
    final enabledAgents = config.agents.where((a) => a.enabled).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    if (enabledAgents.isEmpty) {
      return null;
    }
    return config.copyWith(agents: enabledAgents);
  }

  /// Run the tracker cycle: pre-generation trackers (intermediate agents)
  /// run first, then the main generator (final agent) produces the response.
  /// Trackers receive compact briefs; the generator gets the full context
  /// plus the tracker briefs. See docs/PLAN_AGENTIC_STUDIO.md.
  Future<StudioPipelineResult> runTrackerCycle({
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
        return const StudioPipelineResult(status: 'disabled', response: '');
      }

      if (token.isCancelled) {
        return const StudioPipelineResult(status: 'aborted', response: '');
      }

      // Feature 6 — 3-phase split. Agents are partitioned by their `phase`
      // field (normalized via `StudioAgent.normalizeAgentPhaseForType`):
      //   - pre-gen trackers: `phase == 'pre_generation'` and NOT the final
      //     generator. Run first (batched), produce briefs → feed the generator.
      //   - the final generator: the LAST enabled pre-gen agent. Extends the
      //     old "last enabled agent = generator" rule to "last enabled
      //     PRE-GEN agent = generator" — post-gen agents are excluded from
      //     generator selection.
      //   - post-gen trackers: `phase == 'post_processing'`. Run AFTER the
      //     generator, receive its `mainResponse` in their context, and can
      //     produce an edited/rewritten version. The final post-gen tracker's
      //     non-empty output replaces the generator's response.
      // Fallback: if NO pre-gen agent is marked (e.g. all are post-processing),
      // the last enabled agent is treated as the generator regardless of
      // phase, so the pipeline never loses its writer. Documented + tested.
      final split = splitAgentsByPhase(agents);
      final finalAgent = split.finalAgent;
      if (finalAgent == null) {
        return const StudioPipelineResult(status: 'disabled', response: '');
      }
      final preGenTrackers = split.preGenTrackers;
      final postGenTrackers = split.postGenTrackers;

      final sceneKey = _briefCache.sceneCacheKey(promptPayload);
      final turnIndex = _briefCache.assistantTurnCount(promptPayload);

      // Phase 5.4 — runInterval: skip trackers whose interval doesn't fire
      // this turn. Final generator always runs.
      // Phase F5 — activationKeywords: skip trackers whose keyword gate
      // does not match the recent chat. Trackers with empty
      // activationKeywords always activate (subject to runInterval). The
      // scan window is [activationScanDepth] trailing history messages.
      final historyForScan = promptResult.messages
          .where((m) => m.isHistory)
          .map((m) => m.content)
          .toList();
      final dueTrackers = preGenTrackers.where((a) {
        final interval = a.runInterval <= 0 ? 1 : a.runInterval;
        if (turnIndex % interval != 0) return false;
        if (a.activationKeywords.isEmpty) return true;
        return matchesActivationKeywords(
          a.activationKeywords,
          historyForScan,
          a.activationScanDepth,
        );
      }).toList();

      // Cache-aware batching: probe cache for each due tracker. Hits become
      // final briefs directly; misses go to the batcher.
      final cachedBriefs = <StudioStageBrief>[];
      final fetchTrackers = <StudioAgent>[];
      final cacheProbeByAgent = <String, CacheProbe>{};
      for (final agent in dueTrackers) {
        final probe = _briefCache.probeCache(
          agent: agent,
          config: config,
          promptPayload: promptPayload,
          sceneKey: sceneKey,
          turnIndex: turnIndex,
        );
        cacheProbeByAgent[agent.id] = probe;
        if (probe.hit && probe.brief != null) {
          cachedBriefs.add(probe.brief!);
        } else {
          fetchTrackers.add(agent);
        }
      }

      // Phase 5 — group due+missed trackers into batch groups + individuals.
      final batcher = _ref.read(trackerBatcherProvider);
      final grouping = await batcher.groupAgents(
        agents: fetchTrackers,
        apiConfig: apiConfig,
        sessionId: sessionId,
      );

      final fetchedResults = await batcher.runPhase(
        batchGroups: grouping.batchGroups,
        individualAgents: grouping.individualAgents,
        runBatch: (group) => _runBatchGroup(
          group: group,
          config: config,
          promptResult: promptResult,
          promptPayload: promptPayload,
          apiConfig: apiConfig,
          sessionId: sessionId,
          cancelToken: token,
          batchContextSize: group.batchContextSize,
        ),
        runIndividual: (agent) => _runIndividualTracker(
          agent: agent,
          config: config,
          promptResult: promptResult,
          promptPayload: promptPayload,
          apiConfig: apiConfig,
          sessionId: sessionId,
          cancelToken: token,
        ),
      );

      // Convert batch results + individual results into StudioStageBriefs,
      // persist cache for the ones that succeeded.
      final fetchedBriefs = <StudioStageBrief>[];
      for (final result in fetchedResults) {
        final probe = cacheProbeByAgent[result.agentId];
        final agent = dueTrackers.firstWhere((a) => a.id == result.agentId);
        final sanitized = result.status == 'ok'
            ? _briefParser.sanitizeIntermediateAgentOutput(agent, result.text)
            : result.text;
        final brief = StudioStageBrief(
          agentId: result.agentId,
          agentName: result.agentName,
          brief: sanitized,
          status: result.status,
          error: result.error,
          refreshPolicy: probe?.policy ?? 'turn',
          cacheKey: _briefCache.isCacheablePolicy(probe?.policy ?? 'turn')
              ? probe?.cacheKey
              : null,
          cacheHit: false,
        );
        _briefCache.persistCacheIfCacheable(
          agent: agent,
          brief: brief,
          cacheKey: probe?.cacheKey ?? '',
          policy: probe?.policy ?? 'turn',
          turnIndex: turnIndex,
          cancelToken: token,
        );
        fetchedBriefs.add(brief);
      }

      // Re-assemble briefs in the original pipeline order (cached + fetched),
      // matching `preGenTrackers` order. Trackers skipped by runInterval are
      // omitted entirely — the final generator sees only the due briefs.
      final briefs = <StudioStageBrief>[];
      for (final agent in dueTrackers) {
        final cached = cachedBriefs.where((b) => b.agentId == agent.id).firstOrNull;
        if (cached != null) {
          briefs.add(cached);
          continue;
        }
        final fetched = fetchedBriefs.where((b) => b.agentId == agent.id).firstOrNull;
        if (fetched != null) briefs.add(fetched);
      }

      if (token.isCancelled) {
        return const StudioPipelineResult(status: 'aborted', response: '');
      }

      final agentResult = await _runFinalGenerator(
        agent: finalAgent,
        promptResult: promptResult,
        promptPayload: promptPayload,
        apiConfig: apiConfig,
        config: config,
        priorBriefs: briefs,
        sessionId: sessionId,
        cancelToken: token,
        onFinalResponseUpdate: onFinalResponseUpdate,
      );
      if (token.isCancelled) {
        return const StudioPipelineResult(status: 'aborted', response: '');
      }

      // The generator's response. Post-processing trackers (Feature 6) may
      // rewrite this.
      var mainResponse = agentResult.text;
      var mainReasoning = agentResult.reasoning;
      final rawResponseJson = agentResult.rawResponseJson;

      // Feature 6 — post-processing phase. Post-gen trackers run AFTER the
      // generator, receive `mainResponse` in their context, and can produce
      // an edited/rewritten version. They run sequentially in `order`, each
      // receiving the current `mainResponse` (the output of the previous
      // post-gen tracker, or the generator's response for the first one). The
      // final post-gen tracker's non-empty output replaces `mainResponse`. If
      // a post-gen tracker fails or produces empty output, `mainResponse`
      // stands unchanged for that step. Post-gen trackers do NOT stream to
      // the UI — they run after the generator completes, and only their final
      // result (if it replaces the response) is returned. Port of Marinara
      // `prose-guardian` / `continuity` post-processing model.
      final postBriefs = <StudioStageBrief>[];
      for (final agent in postGenTrackers) {
        if (token.isCancelled) {
          return const StudioPipelineResult(status: 'aborted', response: '');
        }
        // runInterval / activationKeywords apply to post-gen trackers too —
        // a post-gen tracker can be gated the same way as a pre-gen one.
        final interval = agent.runInterval <= 0 ? 1 : agent.runInterval;
        if (turnIndex % interval != 0) continue;
        if (agent.activationKeywords.isNotEmpty &&
            !matchesActivationKeywords(
              agent.activationKeywords,
              historyForScan,
              agent.activationScanDepth,
            )) {
          continue;
        }
        final result = await _runPostProcessingTracker(
          agent: agent,
          mainResponse: mainResponse,
          promptResult: promptResult,
          promptPayload: promptPayload,
          apiConfig: apiConfig,
          config: config,
          sessionId: sessionId,
          cancelToken: token,
        );
        postBriefs.add(result);
        if (result.status == 'ok' && result.brief.trim().isNotEmpty) {
          // This post-gen tracker produced a rewrite — it becomes the new
          // `mainResponse` for the next post-gen tracker (chained rewrites)
          // and for the final returned response. Reasoning is dropped: the
          // rewrite is the user-visible output, not a reasoning trace.
          mainResponse = result.brief.trim();
          mainReasoning = '';
        }
      }

      return StudioPipelineResult(
        status: 'ok',
        response: mainResponse,
        reasoning: mainReasoning,
        rawResponseJson: rawResponseJson,
        stageBriefs: [...briefs, ...postBriefs],
      );
    } on TimeoutException catch (e) {
      _log('tracker cycle timeout session=$sessionId error=${e.message}');
      return StudioPipelineResult(
        status: 'timeout',
        response: '',
        error: e.message?.isNotEmpty == true ? e.message : 'Studio timed out',
      );
    } catch (e) {
      if (token.isCancelled || (e is DioException && CancelToken.isCancel(e))) {
        return const StudioPipelineResult(status: 'aborted', response: '');
      }
      _log('tracker cycle error session=$sessionId error=$e');
      return StudioPipelineResult(status: 'error', response: '', error: '$e');
    }
  }

  /// Delegate the actual LLM call to [AgentRunner]. This method still
  /// builds the `messages` list (prompt assembly remains here) and adapts
  /// the result type to the internal [StudioStageBrief] pipeline.
  ///
  /// Per-agent failure isolation (Phase 5.7.5): when [isFinalResponse] is
  /// false, [AgentRunner.runAgent] wraps any failure into an
  /// [AgentRunFailedException]; here we unwrap it into a failed brief so the
  /// rest of the pipeline keeps going. The final generator rethrows.
  Future<StudioStageBrief> _runTracker({
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
      final sanitized = _briefParser.sanitizeIntermediateAgentOutput(agent, result.text);
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
  /// Failure isolation: a post-gen tracker failure (timeout, transport) is
  /// caught and returned as a failed brief so the pipeline keeps going with
  /// the previous `mainResponse` intact. This mirrors the pre-gen tracker
  /// failure isolation (Phase 5.7.5), since a single post-gen tracker
  /// crashing should not lose the generator's already-good response.
  Future<StudioStageBrief> _runPostProcessingTracker({
    required StudioAgent agent,
    required String mainResponse,
    required PromptResult promptResult,
    required PromptPayload promptPayload,
    required ApiConfig apiConfig,
    required StudioConfig config,
    required String sessionId,
    required CancelToken cancelToken,
  }) async {
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
      return StudioStageBrief(
        agentId: e.agentId,
        agentName: e.agentName,
        brief: '',
        status: 'error',
        error: e.reason,
      );
    }
  }


  /// [batchContextSize] = max contextSize across the group), per-agent task
  /// text, the batched system prompt, fire a single LLM request, parse the
  /// `<result>` blocks, and run the in-batch invalid-JSON retry (Phase 5.1
  /// layer 1) + individual fallback (layer 2) for any agents whose blocks
  /// came back empty/failed.
  Future<List<TrackerBatchResult>> _runBatchGroup({
    required TrackerBatchGroup group,
    required StudioConfig config,
    required PromptResult promptResult,
    required PromptPayload promptPayload,
    required ApiConfig apiConfig,
    required String sessionId,
    required CancelToken cancelToken,
    required int batchContextSize,
  }) async {
    final context = _bucketizer.bucketize(promptResult, promptPayload: promptPayload);
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
      final retried = await _retryFailedIndividually(
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
      return _retryFailedIndividually(
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
  Future<List<TrackerBatchResult>> _retryFailedIndividually({
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
          final brief = await _runTracker(
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

  /// Run one individual tracker (not part of any batch group). Reuses the
  /// existing per-agent prompt assembly + AgentRunner.
  Future<TrackerBatchResult> _runIndividualTracker({
    required StudioAgent agent,
    required StudioConfig config,
    required PromptResult promptResult,
    required PromptPayload promptPayload,
    required ApiConfig apiConfig,
    required String sessionId,
    required CancelToken cancelToken,
  }) async {
    try {
      final brief = await _runTracker(
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
  }

  bool _allOk(List<TrackerBatchResult> results) {
    return results.every((r) => r.status == 'ok' && r.text.isNotEmpty);
  }

  Future<_FinalRunResult> _runFinalGenerator({
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
    return _FinalRunResult(
      text: result.text,
      reasoning: result.reasoning,
      rawResponseJson: result.rawResponseJson,
    );
  }

  /// Keyword-activation gate for trackers (Marinara
  /// `agent-activation.ts:matchCustomAgentActivation` port). Returns true
  /// if at least one of [keywords] appears (case-insensitive substring
  /// match) in the last [scanDepth] entries of [historyContents]. When
  /// [scanDepth] is 0 or negative, scans the entire list. When [keywords]
  /// is empty, returns true (always activate — handled by the caller, but
  /// kept here for completeness).
  ///
  /// Match semantics: case-insensitive `contains` per keyword. We do NOT
  /// use regex (Marinara `activationKeywords` are plain strings, not
  /// patterns) and we do NOT require whole-word boundaries by default
  /// (cheaper, fewer false negatives on inflected forms). If a user wants
  /// exact word matching they can pad the keyword with spaces.
  /// Static delegator — see [StudioActivationGate.matchesActivationKeywords].
  /// Kept on this class because tests reference
  /// `MemoryStudioService.matchesActivationKeywords`.
  @visibleForTesting
  static bool matchesActivationKeywords(
    List<String> keywords,
    List<String> historyContents,
    int scanDepth,
  ) =>
      StudioActivationGate.matchesActivationKeywords(
        keywords,
        historyContents,
        scanDepth,
      );

  /// Feature 6 — split a sorted (by `order`) list of enabled agents into the
  /// three pipeline phases. Exposed `@visibleForTesting` so the splitting
  /// logic is unit-testable without a live `runTrackerCycle`.
  /// (`runTrackerCycle`'s 3-phase split is too entangled with caching /
  /// batcher / AgentRunner to mock cleanly; the split itself is pure.)
  ///
  /// Rules:
  /// - Each agent's `phase` is first normalized via
  ///   [StudioAgent.normalizeAgentPhaseForType] (currently a no-op).
  /// - `postGenTrackers` = agents whose normalized phase is
  ///   `'post_processing'`, in `order`.
  /// - `preGenTrackers` = agents whose normalized phase is
  ///   `'pre_generation'`, EXCLUDING the final generator, in `order`.
  /// - `finalAgent` = the LAST enabled pre-gen agent (the generator). This
  ///   extends the old "last enabled agent = generator" rule to "last enabled
  ///   PRE-GEN agent = generator" — post-gen agents are excluded from
  ///   generator selection.
  /// - Fallback: if NO pre-gen agent exists (e.g. all are post-processing),
  ///   the last enabled agent overall is treated as the generator regardless
  ///   of its phase, so the pipeline never loses its writer. In that fallback
  ///   the chosen generator is also removed from `postGenTrackers` (it
  ///   cannot be both generator and post-gen tracker).
  /// Static delegator — see [StudioActivationGate.splitAgentsByPhase]. Kept on
  /// this class because tests reference `MemoryStudioService.splitAgentsByPhase`.
  @visibleForTesting
  static AgentPhaseSplit splitAgentsByPhase(List<StudioAgent> agents) =>
      StudioActivationGate.splitAgentsByPhase(agents);

  void _log(String message) {
    debugPrint('[Studio] $message');
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

/// Final-generator run result returned by [AgentRunner.runAgent] for the
/// final agent, adapted back to the pipeline-level shape used by
/// [StudioPipelineResult].
class _FinalRunResult {
  final String text;
  final String reasoning;
  final String? rawResponseJson;

  const _FinalRunResult({
    required this.text,
    this.reasoning = '',
    this.rawResponseJson,
  });
}
