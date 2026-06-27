import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/api_config.dart';
import '../models/preset.dart';
import '../models/studio_config.dart';
import '../state/db_provider.dart';
import '../utils/cast_helpers.dart';
import '../utils/error_format.dart';
import 'agent_runner.dart';
import 'json_repair.dart';
import 'history_assembler.dart';
import 'macro_engine.dart';
import 'prompt_builder.dart';
import 'studio_request_preset.dart';
import 'tracker_batcher.dart';

const _mandatoryBlockIds = {'char_card', 'char_personality', 'user_persona'};
const _studioMetaPolicyAgentName = 'Meta-Weaver / Lumia Policy';

/// Session-bound Studio pipeline.
///
/// The Studio menu stores a user-editable [StudioConfig]. At generation time
/// this service runs enabled agents in order. Intermediate agents produce
/// compact briefs; the last enabled agent produces the actual RP response.
class MemoryStudioService {
  final Ref _ref;
  final Map<String, _CachedStudioBrief> _briefCache = {};

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

      final finalAgent = agents.last;
      final allTrackers = agents.sublist(0, agents.length - 1);

      final sceneKey = _sceneCacheKey(promptPayload);
      final turnIndex = _assistantTurnCount(promptPayload);

      // Phase 5.4 — runInterval: skip trackers whose interval doesn't fire
      // this turn. Final generator always runs.
      final dueTrackers = allTrackers.where((a) {
        final interval = a.runInterval <= 0 ? 1 : a.runInterval;
        return turnIndex % interval == 0;
      }).toList();

      // Cache-aware batching: probe cache for each due tracker. Hits become
      // final briefs directly; misses go to the batcher.
      final cachedBriefs = <StudioStageBrief>[];
      final fetchTrackers = <StudioAgent>[];
      final cacheProbeByAgent = <String, _CacheProbe>{};
      for (final agent in dueTrackers) {
        final probe = _probeCache(
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
            ? _sanitizeIntermediateAgentOutput(agent, result.text)
            : result.text;
        final brief = StudioStageBrief(
          agentId: result.agentId,
          agentName: result.agentName,
          brief: sanitized,
          status: result.status,
          error: result.error,
          refreshPolicy: probe?.policy ?? 'turn',
          cacheKey: _isCacheablePolicy(probe?.policy ?? 'turn')
              ? probe?.cacheKey
              : null,
          cacheHit: false,
        );
        _persistCacheIfCacheable(
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
      // matching `allTrackers` order. Trackers skipped by runInterval are
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

      return StudioPipelineResult(
        status: 'ok',
        response: agentResult.text,
        reasoning: agentResult.reasoning,
        rawResponseJson: agentResult.rawResponseJson,
        stageBriefs: briefs,
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

  /// Cache probe result for one tracker. [hit] = true when a usable cached
  /// brief exists for this turn; [brief] carries the sanitized cached brief.
  /// Used by `runTrackerCycle` to split trackers into cached (skip LLM) vs.
  /// batchable/individual before invoking `TrackerBatcher`.
  _CacheProbe _probeCache({
    required StudioAgent agent,
    required StudioConfig config,
    required PromptPayload promptPayload,
    required String sceneKey,
    required int turnIndex,
  }) {
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
      final sanitizedCachedBrief = _sanitizeIntermediateAgentOutput(
        agent,
        cached.brief,
      );
      return _CacheProbe(
        hit: true,
        policy: policy,
        cacheKey: cacheKey,
        brief: StudioStageBrief(
          agentId: agent.id,
          agentName: agent.name,
          brief: sanitizedCachedBrief,
          status: 'cached',
          refreshPolicy: policy,
          cacheKey: cacheKey,
          cacheHit: true,
        ),
      );
    }
    return _CacheProbe(hit: false, policy: policy, cacheKey: cacheKey);
  }

  /// Persist a freshly-fetched brief into `_briefCache` if its refresh policy
  /// is cacheable and the run was successful.
  void _persistCacheIfCacheable({
    required StudioAgent agent,
    required StudioStageBrief brief,
    required String cacheKey,
    required String policy,
    required int turnIndex,
    required CancelToken cancelToken,
  }) {
    if (cancelToken.isCancelled) return;
    if (brief.status != 'ok') return;
    if (!_isCacheablePolicy(policy)) return;
    _briefCache[cacheKey] = _CachedStudioBrief(
      brief: brief.brief,
      policy: policy,
      createdTurnIndex: turnIndex,
    );
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
    if (_isMetaPolicyAgent(agent)) {
      return StudioStageBrief(
        agentId: agent.id,
        agentName: agent.name,
        brief: _metaPolicyBrief(agent),
      );
    }
    try {
      final messages = _buildAgentMessages(
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
      final sanitized = _sanitizeIntermediateAgentOutput(agent, result.text);
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

  /// Run one batch group: build the shared messages (trimmed to
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
    final context = _studioContextBuckets(promptResult, promptPayload: promptPayload);
    final sharedMessages = _buildSharedBatchMessages(
      config: config,
      context: context,
      promptPayload: promptPayload,
      promptResult: promptResult,
      batchContextSize: batchContextSize,
    );
    final perAgentTask = <String, String>{};
    for (final agent in group.agents) {
      perAgentTask[agent.id] = _buildPerAgentTaskText(
        agent: agent,
        config: config,
        promptResult: promptResult,
        promptPayload: promptPayload,
        context: context,
      );
    }
    final roleText = _batchRoleText(config, context, promptPayload, promptResult);
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

  /// Shared messages for a batch: `static_context` + `dynamic_context` +
  /// `chat_history` (trimmed to [batchContextSize]). The per-agent
  /// `agent_instruction` blocks are NOT here — they go into `<agent_task>`
  /// XML in the batch system prompt.
  ///
  /// Phase 6.1 — cache-friendly order: `static_context` (char card, persona,
  /// scenario — stable across turns) FIRST, then `dynamic_context` (MemoryBook
  /// injection, worldInfo, summary — stable within a scene), then
  /// `chat_history` (volatile, last). Combined with the batch system prompt
  /// layout (`<role>` + `<lore>` prefix, `<agents>` tail), this gives the
  /// provider's prompt cache a long stable prefix to hit on subsequent turns.
  List<Map<String, dynamic>> _buildSharedBatchMessages({
    required StudioConfig config,
    required _StudioContextBuckets context,
    required PromptPayload promptPayload,
    required PromptResult promptResult,
    required int batchContextSize,
  }) {
    final messages = <Map<String, dynamic>>[];
    messages.addAll(context.staticContext.map((m) => m.toApiMap()));
    messages.addAll(context.dynamicContext.map((m) => m.toApiMap()));
    final history = _limitTrackerHistory(context.history, batchContextSize);
    messages.addAll(history.map((m) => m.toApiMap()));
    return messages;
  }

  /// Per-agent task text: the agent's `promptShard` + the preset's
  /// `agent_instruction` block content + the runtime envelope (lane contract).
  /// Already macro-expanded.
  String _buildPerAgentTaskText({
    required StudioAgent agent,
    required StudioConfig config,
    required PromptResult promptResult,
    required PromptPayload promptPayload,
    required _StudioContextBuckets context,
  }) {
    final studioPreset = studioRequestPresetById(
      config.agentStudioPresetId,
      finalPreset: false,
      overrides: config.studioPresetOverrides,
    );
    final blocks = studioPreset.blocks
        .where((b) => b.enabled && b.kind == 'agent_instruction')
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    final buf = StringBuffer();
    final promptShard = _expandStudioBlockContent(
      agent.promptShard,
      promptPayload: promptPayload,
      promptResult: promptResult,
      context: context,
    ).trim();
    if (promptShard.isNotEmpty) {
      buf.writeln(promptShard);
      buf.writeln();
    }
    for (final block in blocks) {
      final content = _expandStudioBlockContent(
        block.content,
        promptPayload: promptPayload,
        promptResult: promptResult,
        context: context,
      ).trim();
      if (content.isNotEmpty) {
        buf.writeln(content);
        buf.writeln();
      }
    }
    buf.writeln(_intermediateRuntimeEnvelope(agent));
    return buf.toString().trim();
  }

  /// Role text for the `<role>` element: the shared role/instruction text
  /// from the preset's non-`agent_instruction` blocks (e.g. global rules,
  /// output language). Kept short — most guidance goes into per-agent
  /// `<agent_task>`.
  String _batchRoleText(
    StudioConfig config,
    _StudioContextBuckets context,
    PromptPayload promptPayload,
    PromptResult promptResult,
  ) {
    final studioPreset = studioRequestPresetById(
      config.agentStudioPresetId,
      finalPreset: false,
      overrides: config.studioPresetOverrides,
    );
    final blocks = studioPreset.blocks
        .where((b) => b.enabled && b.kind != 'agent_instruction')
        .where((b) => b.kind != 'static_context')
        .where((b) => b.kind != 'chat_history')
        .where((b) => b.kind != 'dynamic_context')
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    final buf = StringBuffer();
    for (final block in blocks) {
      final promptMessages = context.messagesForKind(block.kind);
      if (promptMessages.isNotEmpty) {
        for (final m in promptMessages) {
          if (m.content.isNotEmpty) buf.writeln(m.content);
        }
        continue;
      }
      final content = _expandStudioBlockContent(
        block.content,
        promptPayload: promptPayload,
        promptResult: promptResult,
        context: context,
      ).trim();
      if (content.isNotEmpty) {
        buf.writeln(content);
      }
    }
    return buf.toString().trim();
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
    final messages = _buildAgentMessages(
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
          if (!isFinalResponse) {
            control
              ..writeln()
              ..writeln(_intermediateRuntimeEnvelope(agent));
          }
          if (isFinalResponse) {
            control
              ..writeln()
              ..writeln(_finalBriefUsageNote());
            final styleContract = _finalHardStyleContract(config);
            if (styleContract.isNotEmpty) {
              control
                ..writeln()
                ..writeln(styleContract);
            }
          }
          messages.add({
            'role': _normalizeRole(
              block.role.isNotEmpty ? block.role : agent.role,
            ),
            'content': control.toString().trim(),
          });
          break;
        case 'previous_agents':
          if (!isFinalResponse) break;
          final sanitized = priorBriefs
              .where((b) => b.brief.trim().isNotEmpty)
              .map((b) => _sanitizePriorBriefForFinal(b, config))
              .toList();
          final deduped = _dedupePriorBriefs(sanitized);
          messages.addAll(
            deduped
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
          final history = isFinalResponse
              ? _limitFinalHistory(context.history, config)
              : _limitTrackerHistory(context.history, agent.contextSize);
          messages.addAll(history.map((m) => m.toApiMap()));
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

  /// Cap how many trailing chat messages reach the FINAL responder.
  ///
  /// Intermediate agents always analyze the full transcript; the final writer
  /// is intentionally limited (default 15) so it relies on the compact agent
  /// briefs instead of re-reading the whole history. We keep the most recent
  /// [StudioConfig.maxFinalHistoryMessages] messages, which always preserves
  /// the current user turn (it is last). 0 (or negative) means no limit.
  List<PromptMessage> _limitFinalHistory(
    List<PromptMessage> history,
    StudioConfig config,
  ) {
    final limit = config.maxFinalHistoryMessages;
    if (limit <= 0 || history.length <= limit) return history;
    final trimmed = history.sublist(history.length - limit);
    return trimmed;
  }

  /// Hard cap on tracker context size (Marinara MAX_AGENT_CONTEXT_MESSAGES).
  static const _maxTrackerContextSize = 200;

  /// Trim trailing chat history for a tracker (intermediate agent).
  ///
  /// Returns the last [contextSize] messages (clamped to
  /// `1..[_maxTrackerContextSize]`), each truncated via
  /// [_truncateAgentText] and stripped of HTML via [_stripHtmlTags].
  ///
  /// Only the `chat_history` block is trimmed — `static_context` (card,
  /// persona, lorebooks) and `dynamic_context` (memory, summary, worldInfo)
  /// remain untouched. MemoryBook injection survives the refactor because it
  /// flows through `dynamic_context`, not `chat_history`. See
  /// docs/PLAN_AGENTIC_STUDIO.md Phase 3.
  List<PromptMessage> _limitTrackerHistory(
    List<PromptMessage> history,
    int contextSize,
  ) {
    final normalized = contextSize.clamp(
      1,
      _maxTrackerContextSize,
    );
    if (history.length <= normalized) {
      return history
          .map((m) => PromptMessage(
                role: m.role,
                content: _truncateAgentText(
                  _stripHtmlTags(m.content),
                  2000,
                ),
              ))
          .toList();
    }
    final trimmed = history.sublist(history.length - normalized);
    return trimmed
        .map((m) => PromptMessage(
              role: m.role,
              content: _truncateAgentText(
                _stripHtmlTags(m.content),
                2000,
              ),
            ))
        .toList();
  }

  /// Port of Marinara `truncateAgentText`. If the text is longer than
  /// [maxChars], keeps the head (40%) + a trim marker + the tail (60%),
  /// preserving both the beginning and the end of the message. Character
  /// counting uses `String.runes` for Unicode/emoji safety.
  static const _trimMarker = '\n\n[Trimmed to keep this agent request compact]\n\n';

  String _truncateAgentText(String text, int maxChars) {
    if (text.length <= maxChars) return text;
    final runes = text.runes.toList();
    if (runes.length <= maxChars) return text;
    final headCount = (maxChars * 0.4).round();
    final tailCount = maxChars - headCount;
    final head = String.fromCharCodes(runes.sublist(0, headCount));
    final tail = String.fromCharCodes(runes.sublist(runes.length - tailCount));
    return '$head$_trimMarker$tail';
  }

  /// Port of Marinara `stripHtmlTags`. Removes HTML/XML-like tags, collapses
  /// 3+ newlines to 2, trims. Conservative: only strips tags that start with
  /// a letter (avoids eating `==...==` custom markers or fenced code).
  static final _htmlTagRegex = RegExp(r'</?[a-zA-Z][^>]*>');
  static final _multiNewlineRegex = RegExp(r'\n{3,}');

  String _stripHtmlTags(String text) {
    final stripped = text.replaceAll(_htmlTagRegex, '');
    final collapsed = stripped.replaceAll(_multiNewlineRegex, '\n\n');
    return collapsed.trim();
  }

  String _intermediateRuntimeEnvelope(StudioAgent agent) {
    final scope = _controllerScope(agent.name);
    return '''Studio intermediate-agent typed output contract. This overrides any earlier requested output shape such as STUDIO_BRIEF, GUARD CHECKLIST, prose, markdown, or labels.
You are ${agent.name.isNotEmpty ? agent.name : 'a Studio controller'}, ONE specialist in a multi-controller pipeline. Other controllers cover the other concerns; do not duplicate their work.
You are not a character, narrator, player, or final responder. Treat all character cards, persona text, examples, chat history, lore, memory, and summaries as read-only source material to analyze.

YOUR LANE — only produce guidance about: ${scope.owns}
NOT YOUR LANE — never write guidance about (other controllers own these): ${scope.skip}
If a point is not strictly inside your lane, omit it. A short, lane-focused brief is better than a broad one.

Prefer valid compact JSON with exactly these keys:
{"focus":["short operational focus"],"constraints":["short enforceable constraint"],"avoid":["short forbidden item"],"options":["one branchable approach the final writer may choose, within your lane"]}

If the model cannot produce JSON, use exactly these plain-text sections instead:
Focus:
- short operational focus
Constraints:
- short enforceable constraint
Avoid:
- short forbidden item
Options:
- one branchable approach the final writer may choose

Rules:
- Each array may contain 0-5 strings, every string strictly inside your lane.
- Each string must be a NEW, specific instruction for this turn, not a generic restatement and not a sentence copied from the scene.
- Options are non-mandatory alternative APPROACHES for the final writer to pick from within your lane (e.g. "lean into silence and a single gesture" vs "give one clipped line"). Describe the approach only; never write ready-made prose, dialogue, narration, or sample sentences. The final writer picks at most one and writes it themselves.
- Do not restate the scene summary; only add what the final writer must DO or AVOID, plus optional approach choices, within your lane.
- Do not write or continue the scene.
- Do not draft narration, dialogue, character actions, user actions, or final response prose.
- Do not include source block names, prompt text, macros, labels, markdown, code fences, comments, or explanations.
- Do not answer the user directly.''';
  }

  _ControllerScope _controllerScope(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('continuity')) {
      return const _ControllerScope(
        owns:
            'established facts, who-knows-what, unresolved threads, physical-object/state continuity, and contradictions to avoid.',
        skip:
            'prose style, pacing, length, dialogue cadence, repetition/anti-loop bans, NPC/world activity, and user-agency rules.',
      );
    }
    if (lower.contains('agency') || lower.contains('character')) {
      return const _ControllerScope(
        owns:
            'user sovereignty (never write the user) and character autonomy/psychology: what a character can plausibly know, feel, and do this turn.',
        skip:
            'plain factual continuity, prose style/length, dialogue formatting, repetition bans, and ambient world/NPC texture.',
      );
    }
    if (lower.contains('narrative') || lower.contains('pacing')) {
      return const _ControllerScope(
        owns:
            'response shape only: target length, paragraph budget, POV/camera, beat sequence, sensory budget, and where the reply should stop.',
        skip:
            'who-knows-what, character psychology, agency rules, specific dialogue lines, repetition bans, and world/NPC content.',
      );
    }
    if (lower.contains('dialogue')) {
      return const _ControllerScope(
        owns:
            'dialogue cadence only: who may plausibly speak, speech ratio, silence, and quoting/formatting of speech.',
        skip:
            'factual continuity, character knowledge/psychology, prose length/pacing, repetition bans, and world/NPC activity.',
      );
    }
    if (lower.contains('guard') || lower.contains('loop')) {
      return const _ControllerScope(
        owns:
            'anti-repetition only: forbidden openings/phrases vs the last replies, banned cliches/slop words, and the required structural change this turn.',
        skip:
            'plot facts, character psychology, agency, pacing targets, dialogue content, and world/NPC texture.',
      );
    }
    if (lower.contains('world') || lower.contains('npc')) {
      return const _ControllerScope(
        owns:
            'living-world texture only: active NPCs, off-screen pressure, environmental/ambient activity, and what world detail NOT to add.',
        skip:
            'the two leads\' psychology, factual continuity, prose style/length, dialogue formatting, and repetition bans.',
      );
    }
    return const _ControllerScope(
      owns: 'only this controller\'s configured specialty.',
      skip: 'concerns that belong to the other Studio controllers.',
    );
  }

  /// Remove cross-controller duplicate bullet points before sending briefs to
  /// the final responder. The first controller to mention a point keeps it;
  /// later controllers drop the duplicate so the final prompt does not repeat
  /// the same instruction many times (which over-weights it and produces
  /// repetitive replies). Meta briefs are passed through unchanged.
  List<StudioStageBrief> _dedupePriorBriefs(List<StudioStageBrief> briefs) {
    final seen = <String>{};
    final result = <StudioStageBrief>[];
    for (final brief in briefs) {
      if (_isMetaBriefName(brief.agentName)) {
        result.add(brief);
        continue;
      }
      final deduped = _dedupeBriefBody(brief.brief, seen);
      result.add(
        StudioStageBrief(
          agentId: brief.agentId,
          agentName: brief.agentName,
          brief: deduped,
          status: brief.status,
          error: brief.error,
          refreshPolicy: brief.refreshPolicy,
          cacheKey: brief.cacheKey,
          cacheHit: brief.cacheHit,
        ),
      );
    }
    return result;
  }

  /// Walk the Focus/Constraints/Avoid sections of one brief, dropping any
  /// bullet whose normalized form was already emitted by an earlier brief.
  /// Empty sections are removed. [seen] accumulates across briefs.
  String _dedupeBriefBody(String brief, Set<String> seen) {
    final lines = brief.split('\n');
    final out = <String>[];
    var currentHeading = '';
    final pendingHeadingItems = <String>[];

    void flushHeading() {
      if (currentHeading.isEmpty) return;
      if (pendingHeadingItems.isNotEmpty) {
        out.add(currentHeading);
        out.addAll(pendingHeadingItems);
      }
      currentHeading = '';
      pendingHeadingItems.clear();
    }

    for (final rawLine in lines) {
      final line = rawLine.trimRight();
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final heading = _studioBriefHeading(trimmed);
      if (heading != null) {
        flushHeading();
        currentHeading = line;
        continue;
      }
      final item = _cleanBriefItem(trimmed);
      if (item == null) {
        // Non-bullet line outside a known section; keep verbatim once.
        final key = 'raw:${_dedupeKey(trimmed)}';
        if (seen.add(key)) {
          if (currentHeading.isNotEmpty) {
            pendingHeadingItems.add(line);
          } else {
            out.add(line);
          }
        }
        continue;
      }
      final key = _dedupeKey(item);
      if (!seen.add(key)) continue;
      pendingHeadingItems.add('- $item');
    }
    flushHeading();
    return out.join('\n').trim();
  }

  String _dedupeKey(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9а-яё ]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _isMetaPolicyAgent(StudioAgent agent) {
    final text = '${agent.id}\n${agent.name}\n${agent.sourceBlockNames}'
        .toLowerCase();
    return text.contains('meta-weaver') ||
        text.contains('lumia') ||
        text.contains('ghost in the machine');
  }

  String _metaPolicyBrief(StudioAgent agent) {
    final buffer = StringBuffer()
      ..writeln('Meta policy:')
      ..writeln('- Silent during normal in-character roleplay.')
      ..writeln('- Never write scene prose, dialogue, actions, or narration.')
      ..writeln('- Do not draft or continue the assistant reply.')
      ..writeln(
        '- Apply only as hidden policy for continuity, tone, and OOC routing.',
      )
      ..writeln(
        '- If the user explicitly addresses OOC/Lumia/meta, answer as an OOC interface; otherwise stay invisible.',
      );
    return buffer.toString().trim();
  }

  StudioStageBrief _sanitizePriorBriefForFinal(
    StudioStageBrief brief,
    StudioConfig config,
  ) {
    if (!_isMetaBriefName(brief.agentName)) {
      final agent = _agentForBrief(brief, config);
      return StudioStageBrief(
        agentId: brief.agentId,
        agentName: brief.agentName,
        brief: _sanitizeIntermediateAgentOutput(agent, brief.brief),
        status: brief.status,
        error: brief.error,
        refreshPolicy: brief.refreshPolicy,
        cacheKey: brief.cacheKey,
        cacheHit: brief.cacheHit,
      );
    }
    return StudioStageBrief(
      agentId: brief.agentId,
      agentName: brief.agentName,
      brief: _sanitizeMetaBrief(brief.brief),
      status: brief.status,
      error: brief.error,
      refreshPolicy: brief.refreshPolicy,
      cacheKey: brief.cacheKey,
      cacheHit: brief.cacheHit,
    );
  }

  StudioAgent _agentForBrief(StudioStageBrief brief, StudioConfig config) {
    return config.agents.firstWhere(
      (agent) => agent.id == brief.agentId || agent.name == brief.agentName,
      orElse: () => StudioAgent(id: brief.agentId, name: brief.agentName),
    );
  }

  String _sanitizeIntermediateAgentOutput(StudioAgent agent, String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return trimmed;
    if (_isMetaBriefName(agent.name)) return _sanitizeMetaBrief(trimmed);
    final typed = _typedStudioBrief(agent, trimmed);
    if (typed != null) return typed;
    final sectioned = _sectionStudioBrief(trimmed);
    if (sectioned != null) return sectioned;

    final fallback = _safeControllerFallback(agent);
    _log(
      'brief leaked scene prose; replacing agent="${agent.name}" '
      'chars=${trimmed.length} first200=${trimmed.substring(0, trimmed.length > 200 ? 200 : trimmed.length)}',
    );
    return fallback;
  }

  String? _typedStudioBrief(StudioAgent agent, String text) {
    final raw = _extractJsonObject(text);
    if (raw == null) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(repairJson(raw));
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    final focus = _safeJsonStringList(decoded['focus']);
    final constraints = _safeJsonStringList(decoded['constraints']);
    final avoid = _safeJsonStringList(decoded['avoid']);
    final options = _safeJsonStringList(decoded['options']);
    final all = [...focus, ...constraints, ...avoid, ...options];
    if (all.isEmpty) {
      _log(
        'brief typed-JSON all items rejected agent="${agent.name}" '
        'focus=${(decoded['focus'] as List?)?.length ?? 0} '
        'constraints=${(decoded['constraints'] as List?)?.length ?? 0} '
        'avoid=${(decoded['avoid'] as List?)?.length ?? 0} '
        'options=${(decoded['options'] as List?)?.length ?? 0}',
      );
      return null;
    }

    return _buildStudioBrief(
      focus: focus,
      constraints: constraints,
      avoid: avoid,
      options: options,
    );
  }

  String? _sectionStudioBrief(String text) {
    if (_looksLikeSceneProse(text)) return null;
    final focus = <String>[];
    final constraints = <String>[];
    final avoid = <String>[];
    final options = <String>[];
    var section = '';

    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final heading = _studioBriefHeading(line);
      if (heading != null) {
        section = heading;
        continue;
      }
      if (section.isEmpty) continue;
      final cleaned = _cleanBriefItem(line);
      if (cleaned == null) continue;
      final target = switch (section) {
        'focus' => focus,
        'avoid' => avoid,
        'options' => options,
        _ => constraints,
      };
      if (target.any(
        (existing) => existing.toLowerCase() == cleaned.toLowerCase(),
      )) {
        continue;
      }
      target.add(cleaned);
      if (target.length >= 6) section = '';
    }

    if ([...focus, ...constraints, ...avoid, ...options].isEmpty) return null;
    return _buildStudioBrief(
      focus: focus,
      constraints: constraints,
      avoid: avoid,
      options: options,
    );
  }

  String? _studioBriefHeading(String line) {
    final normalized = line
        .toLowerCase()
        .replaceAll(RegExp(r'^#+\s*'), '')
        .replaceAll(RegExp(r'[:：]+$'), '')
        .trim();
    if (normalized == 'focus' || normalized == 'фокус') return 'focus';
    if (normalized == 'constraints' ||
        normalized == 'constraint' ||
        normalized == 'guard checklist' ||
        normalized == 'checklist' ||
        normalized == 'rules' ||
        normalized == 'ограничения' ||
        normalized == 'правила') {
      return 'constraints';
    }
    if (normalized == 'avoid' ||
        normalized == 'forbidden' ||
        normalized == 'forbidden this turn' ||
        normalized == 'do not' ||
        normalized == 'избегать' ||
        normalized == 'запреты') {
      return 'avoid';
    }
    if (normalized == 'options' ||
        normalized == 'option' ||
        normalized == 'approaches' ||
        normalized == 'choices' ||
        normalized == 'варианты' ||
        normalized == 'подходы' ||
        normalized == 'на выбор') {
      return 'options';
    }
    return null;
  }

  String _buildStudioBrief({
    required List<String> focus,
    required List<String> constraints,
    required List<String> avoid,
    List<String> options = const [],
  }) {
    final buffer = StringBuffer();
    void writeSection(String title, List<String> items) {
      if (items.isEmpty) return;
      buffer.writeln(title);
      for (final item in items) {
        buffer.writeln('- $item');
      }
    }

    writeSection('Focus:', focus);
    writeSection('Constraints:', constraints);
    writeSection('Avoid:', avoid);
    writeSection('Options:', options);
    return buffer.toString().trim();
  }

  String? _extractJsonObject(String text) {
    var trimmed = text.trim();
    final fenced = RegExp(
      r'^```(?:json)?\s*([\s\S]*?)\s*```$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (fenced != null) trimmed = fenced.group(1)?.trim() ?? trimmed;
    final start = trimmed.indexOf('{');
    final end = trimmed.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    return trimmed.substring(start, end + 1);
  }

  List<String> _safeJsonStringList(Object? value) {
    if (value is String) return _safeJsonStringList([value]);
    if (value is! List) return const [];
    final result = <String>[];
    for (final item in value) {
      if (item is! String) continue;
      final cleaned = _cleanBriefItem(item);
      if (cleaned == null) continue;
      if (result.any(
        (existing) => existing.toLowerCase() == cleaned.toLowerCase(),
      )) {
        continue;
      }
      result.add(cleaned);
      if (result.length >= 6) break;
    }
    return result;
  }

  String? _cleanBriefItem(String item) {
    final cleaned = item
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^[-*•\d.\s]+'), '')
        .trim();
    if (cleaned.isEmpty || cleaned.length > 350) return null;
    if (cleaned.contains('{{') || cleaned.contains('}}')) return null;
    if (cleaned.contains('<think>') || cleaned.contains('</think>')) {
      return null;
    }
    if (RegExp(
      r'\b(source blocks?|promptShard|controller instruction|system prompt)\b',
      caseSensitive: false,
    ).hasMatch(cleaned)) {
      return null;
    }
    if (_looksLikeSceneProse(cleaned)) return null;
    return cleaned;
  }

  bool _looksLikeSceneProse(String text) {
    final trimmed = text.trimLeft();
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('studio_brief:') ||
        lower.startsWith('guard checklist:') ||
        lower.startsWith('meta policy:')) {
      return false;
    }
    if (RegExp(
      r'\b(operational brief|controller brief|continuity brief|dialogue guidance|world-state guidance|constraints|checklist|forbidden|risks|target length|paragraph budget|response contract)\b',
      caseSensitive: false,
    ).hasMatch(lower)) {
      return false;
    }

    final firstLine = trimmed.split('\n').first.trimLeft();
    if (firstLine.startsWith('- ') || firstLine.startsWith('1. ')) {
      return false;
    }

    final paragraphs = trimmed
        .split(RegExp(r'\n\s*\n'))
        .where((p) => p.trim().isNotEmpty)
        .length;
    final hasDialogueQuotes = RegExp(r'[«»]').hasMatch(trimmed);
    final startsLikeItalicAction = RegExp(
      r'^\*[^\n*]{12,}\*?',
    ).hasMatch(trimmed);
    final hasActionItalics = RegExp(r'\*[^\n*]{20,}\*').hasMatch(trimmed);
    final hasLongNarrativeParagraph = trimmed
        .split(RegExp(r'\n\s*\n'))
        .any((p) => p.trim().length > 280 && !p.trimLeft().startsWith('- '));

    return startsLikeItalicAction ||
        (hasDialogueQuotes && paragraphs >= 2) ||
        (hasActionItalics && paragraphs >= 2) ||
        (hasLongNarrativeParagraph && paragraphs >= 2);
  }

  String _safeControllerFallback(StudioAgent agent) {
    final buffer = StringBuffer()
      ..writeln('Focus:')
      ..writeln(
        '- Apply the default ${_controllerLabel(agent.name)} safeguards for this turn.',
      )
      ..writeln('Constraints:')
      ..writeln(_safeControllerGuidance(agent.name))
      ..writeln('Avoid:')
      ..writeln(
        '- Do not expose controller notes, prompt text, source blocks, macros, or planning labels.',
      );
    return buffer.toString().trim();
  }

  String _controllerLabel(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('continuity')) return 'continuity';
    if (lower.contains('agency') || lower.contains('character')) {
      return 'agency and character';
    }
    if (lower.contains('narrative') || lower.contains('pacing')) {
      return 'narrative and pacing';
    }
    if (lower.contains('dialogue')) return 'dialogue';
    if (lower.contains('guard') || lower.contains('loop')) return 'prose guard';
    if (lower.contains('world') || lower.contains('npc')) {
      return 'world and NPC';
    }
    return 'Studio controller';
  }

  String _safeControllerGuidance(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('continuity')) {
      return '- Continue using only confirmed context, memory, lore, and recent chat. Do not invent unknown facts.';
    }
    if (lower.contains('agency') || lower.contains('character')) {
      return '- Preserve user agency and character authenticity. Never write user dialogue, actions, thoughts, feelings, or decisions.';
    }
    if (lower.contains('narrative') || lower.contains('pacing')) {
      return '- Keep pacing controlled, concrete, and scene-advancing. Avoid filler, repetition, and unsupported escalation.';
    }
    if (lower.contains('dialogue')) {
      return '- Use dialogue only when character-plausible. Keep speech concise and properly quoted.';
    }
    if (lower.contains('guard') || lower.contains('loop')) {
      return '- Avoid repeated openings, recycled phrasing, cliches, echoing the user, and banned prose habits.';
    }
    if (lower.contains('world') || lower.contains('npc')) {
      return '- Add world/NPC activity only when supported by the scene and never let it steal focus.';
    }
    return '- Apply this controller only as hidden operational guidance.';
  }

  bool _isMetaBriefName(String name) {
    final lower = name.toLowerCase();
    return lower.contains('meta-weaver') || lower.contains('lumia');
  }

  String _sanitizeMetaBrief(String brief) {
    final lower = brief.toLowerCase();
    if (lower.contains('meta policy:') &&
        lower.contains('never write scene prose')) {
      return brief;
    }
    return _metaPolicyBrief(
      const StudioAgent(id: 'meta_sanitized', name: _studioMetaPolicyAgentName),
    );
  }

  String _finalBriefUsageNote() {
    return 'How to use the Studio controller briefs above: the controllers have ALREADY analyzed the scene, tracked continuity, and decided what should happen next. Do NOT re-analyze the scene, re-derive character motivations, or plan the beat structure in your reasoning — that work is done. Your only job is to WRITE the prose that implements their direction.\n\nTreat Focus and Constraints as binding direction and Avoid as hard prohibitions. Any "Options:" items are non-binding alternative approaches — choose at most one per brief (or none) that best fits the moment, then write it in your own words. Do not list, mention, or copy the options or any brief text in your reply; weave the chosen direction into natural in-scene prose.\n\nKeep your reasoning SHORT — a few sentences at most confirming which option you picked and any immediate sensory/structural choices. Do NOT draft full prose in reasoning, do NOT re-check constraints line-by-line, do NOT restate the briefs. Write the final prose directly.';
  }

  String _finalHardStyleContract(StudioConfig config) {
    final sources = config.agents
        .map(
          (agent) =>
              '${agent.name}\n${agent.sourceBlockNames}\n${agent.promptShard}',
        )
        .join('\n\n');
    final rules = <String>[];
    if (RegExp(
      r'—|длинн.{0,24}тире|long.{0,24}dash|em dash',
      caseSensitive: false,
    ).hasMatch(sources)) {
      rules.add('- Do not use em dashes / long dashes: avoid "—".');
    }
    if (RegExp(
      r'кавыч|quote|quotation|direct speech|прям.{0,24}реч',
      caseSensitive: false,
    ).hasMatch(sources)) {
      rules.add(
        '- Wrap direct spoken dialogue in quotation marks; do not use bare dialogue lines.',
      );
    }
    if (rules.isEmpty) return '';
    return 'Hard final formatting constraints from Studio controllers:\n${rules.join('\n')}';
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

class StudioStageBrief {
  final String agentId;
  final String agentName;
  final String brief;
  final String status;
  final String? error;
  final String refreshPolicy;
  final String? cacheKey;
  final bool cacheHit;

  const StudioStageBrief({
    required this.agentId,
    required this.agentName,
    required this.brief,
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

/// Result of probing `_briefCache` for one tracker before batching.
class _CacheProbe {
  final bool hit;
  final String policy;
  final String cacheKey;
  final StudioStageBrief? brief;

  const _CacheProbe({
    required this.hit,
    required this.policy,
    required this.cacheKey,
    this.brief,
  });
}

class _ControllerScope {
  final String owns;
  final String skip;

  const _ControllerScope({required this.owns, required this.skip});
}
