import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/api_config.dart';
import '../models/studio_config.dart';
import '../state/db_provider.dart';
import 'prompt_builder.dart';
import 'studio_activation_gate.dart';
import 'studio_agent_executor.dart';
import 'studio_batch_coordinator.dart';
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
  late final StudioBriefDeduper _briefDeduper = StudioBriefDeduper(
    _briefParser,
  );
  late final StudioBriefCache _briefCache = StudioBriefCache(_briefParser);
  late final StudioMessageBuilder _messageBuilder = StudioMessageBuilder(
    _bucketizer,
    _promptText,
    _briefDeduper,
  );
  late final StudioAgentExecutor _executor = StudioAgentExecutor(
    _ref,
    _messageBuilder,
    _briefParser,
  );
  late final StudioBatchCoordinator _batchCoordinator = StudioBatchCoordinator(
    _ref,
    _bucketizer,
    _messageBuilder,
    _executor,
    _log,
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

    // Resolve the DB Studio preset for this config.
    final presetRepo = _ref.read(studioPresetRepoProvider);
    final presetById = await presetRepo.getById(config.studioPresetId);
    final StudioPreset studioPreset;
    if (presetById != null) {
      studioPreset = presetById;
    } else {
      final presetDefault = await presetRepo.getDefault();
      if (presetDefault == null) {
        return const StudioPipelineResult(
          status: 'error',
          response: '',
          error: 'No Studio preset found in DB. Rebuild Studio.',
        );
      }
      studioPreset = presetDefault;
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
      final trackerContextOverride = _ref
          .read(pipelineSettingsProvider)
          .studioTrackerContextSize;
      final fetchedResults = await batcher.runPhase(
        batchGroups: grouping.batchGroups,
        individualAgents: grouping.individualAgents,
        runBatch: (group) => _batchCoordinator.runBatchGroup(
          group: group,
          config: config,
          studioPreset: studioPreset,
          promptResult: promptResult,
          promptPayload: promptPayload,
          apiConfig: apiConfig,
          sessionId: sessionId,
          cancelToken: token,
          batchContextSize: trackerContextOverride > 0
              ? trackerContextOverride
              : group.batchContextSize,
        ),
        runIndividual: (agent) => _executor.runIndividualTracker(
          agent: trackerContextOverride > 0
              ? agent.copyWith(contextSize: trackerContextOverride)
              : agent,
          config: config,
          studioPreset: studioPreset,
          promptResult: promptResult,
          promptPayload: promptPayload,
          apiConfig: apiConfig,
          sessionId: sessionId,
          cancelToken: token,
        ),
      );
      if (token.isCancelled) {
        return const StudioPipelineResult(status: 'aborted', response: '');
      }
      final trackerFailure = _firstFailedTrackerResult(fetchedResults);
      if (trackerFailure != null) {
        final failedBriefs = _trackerResultsToBriefs(
          fetchedResults,
          dueTrackers,
          cacheProbeByAgent,
        );
        final error = _trackerFailureMessage(trackerFailure);
        _log('tracker cycle failed session=$sessionId error=$error');
        return StudioPipelineResult(
          status: 'error',
          response: '',
          stageBriefs: failedBriefs,
          error: error,
        );
      }

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
        final cached = cachedBriefs
            .where((b) => b.agentId == agent.id)
            .firstOrNull;
        if (cached != null) {
          briefs.add(cached);
          continue;
        }
        final fetched = fetchedBriefs
            .where((b) => b.agentId == agent.id)
            .firstOrNull;
        if (fetched != null) briefs.add(fetched);
      }

      if (token.isCancelled) {
        return const StudioPipelineResult(status: 'aborted', response: '');
      }

      final agentResult = await _executor.runFinalGenerator(
        agent: finalAgent,
        promptResult: promptResult,
        promptPayload: promptPayload,
        apiConfig: apiConfig,
        config: config,
        studioPreset: studioPreset,
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
        final result = await _executor.runPostProcessingTracker(
          agent: agent,
          mainResponse: mainResponse,
          promptResult: promptResult,
          promptPayload: promptPayload,
          apiConfig: apiConfig,
          config: config,
          studioPreset: studioPreset,
          sessionId: sessionId,
          cancelToken: token,
        );
        postBriefs.add(result);
        if (token.isCancelled) {
          return const StudioPipelineResult(status: 'aborted', response: '');
        }
        if (result.status == 'error') {
          final error =
              'Studio tracker "${result.agentName}" failed after '
              '2 retries: ${result.error ?? 'tracker failed'}. Please '
              'restart generation.';
          _log('post tracker cycle failed session=$sessionId error=$error');
          return StudioPipelineResult(
            status: 'error',
            response: '',
            stageBriefs: [...briefs, ...postBriefs],
            error: error,
          );
        }
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
        status: mainResponse.trim().isEmpty ? 'error' : 'ok',
        response: mainResponse,
        reasoning: mainReasoning,
        rawResponseJson: rawResponseJson,
        stageBriefs: [...briefs, ...postBriefs],
        error: mainResponse.trim().isEmpty
            ? 'Final generator returned an empty response'
            : null,
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

  /// Tracker-only cycle: runs the pre-gen tracker phase and returns the
  /// produced briefs WITHOUT firing the final generator or post-gen
  /// trackers. Used by [TrackerMemoryRecoveryService] to restore lost
  /// `studioOutputs` without burning the final-generator model (e.g.
  /// Gemini Pro) on every historical message.
  ///
  /// Mirrors the pre-gen phase of [runTrackerCycle] verbatim (split,
  /// runInterval/activation gate, cache probing, batching, brief assembly).
  /// Returns only the `stageBriefs` (response/reasoning are empty).
  Future<StudioPipelineResult> runTrackersOnly({
    required StudioConfig config,
    required PromptResult promptResult,
    required PromptPayload promptPayload,
    required ApiConfig apiConfig,
    required String sessionId,
    CancelToken? cancelToken,
  }) async {
    final token = cancelToken ?? CancelToken();
    if (token.isCancelled) {
      return const StudioPipelineResult(status: 'aborted', response: '');
    }

    // Resolve the DB Studio preset for this config.
    final presetRepo = _ref.read(studioPresetRepoProvider);
    final presetById = await presetRepo.getById(config.studioPresetId);
    final StudioPreset studioPreset;
    if (presetById != null) {
      studioPreset = presetById;
    } else {
      final presetDefault = await presetRepo.getDefault();
      if (presetDefault == null) {
        return const StudioPipelineResult(
          status: 'error',
          response: '',
          error: 'No Studio preset found in DB. Rebuild Studio.',
        );
      }
      studioPreset = presetDefault;
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

      final split = splitAgentsByPhase(agents);
      final finalAgent = split.finalAgent;
      if (finalAgent == null) {
        return const StudioPipelineResult(status: 'disabled', response: '');
      }
      final preGenTrackers = split.preGenTrackers;

      final sceneKey = _briefCache.sceneCacheKey(promptPayload);
      final turnIndex = _briefCache.assistantTurnCount(promptPayload);

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

      final batcher = _ref.read(trackerBatcherProvider);
      final grouping = await batcher.groupAgents(
        agents: fetchTrackers,
        apiConfig: apiConfig,
        sessionId: sessionId,
      );

      final trackerContextOverride = _ref
          .read(pipelineSettingsProvider)
          .studioTrackerContextSize;
      final fetchedResults = await batcher.runPhase(
        batchGroups: grouping.batchGroups,
        individualAgents: grouping.individualAgents,
        runBatch: (group) => _batchCoordinator.runBatchGroup(
          group: group,
          config: config,
          studioPreset: studioPreset,
          promptResult: promptResult,
          promptPayload: promptPayload,
          apiConfig: apiConfig,
          sessionId: sessionId,
          cancelToken: token,
          batchContextSize: trackerContextOverride > 0
              ? trackerContextOverride
              : group.batchContextSize,
        ),
        runIndividual: (agent) => _executor.runIndividualTracker(
          agent: trackerContextOverride > 0
              ? agent.copyWith(contextSize: trackerContextOverride)
              : agent,
          config: config,
          studioPreset: studioPreset,
          promptResult: promptResult,
          promptPayload: promptPayload,
          apiConfig: apiConfig,
          sessionId: sessionId,
          cancelToken: token,
        ),
      );
      if (token.isCancelled) {
        return const StudioPipelineResult(status: 'aborted', response: '');
      }
      final trackerFailure = _firstFailedTrackerResult(fetchedResults);
      if (trackerFailure != null) {
        final failedBriefs = _trackerResultsToBriefs(
          fetchedResults,
          dueTrackers,
          cacheProbeByAgent,
        );
        final error = _trackerFailureMessage(trackerFailure);
        _log('tracker-only cycle failed session=$sessionId error=$error');
        return StudioPipelineResult(
          status: 'error',
          response: '',
          stageBriefs: failedBriefs,
          error: error,
        );
      }

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

      final briefs = <StudioStageBrief>[];
      for (final agent in dueTrackers) {
        final cached = cachedBriefs
            .where((b) => b.agentId == agent.id)
            .firstOrNull;
        if (cached != null) {
          briefs.add(cached);
          continue;
        }
        final fetched = fetchedBriefs
            .where((b) => b.agentId == agent.id)
            .firstOrNull;
        if (fetched != null) briefs.add(fetched);
      }

      if (token.isCancelled) {
        return const StudioPipelineResult(status: 'aborted', response: '');
      }

      return StudioPipelineResult(
        status: 'ok',
        response: '',
        stageBriefs: briefs,
      );
    } on TimeoutException catch (e) {
      _log('tracker-only cycle timeout session=$sessionId error=${e.message}');
      return StudioPipelineResult(
        status: 'timeout',
        response: '',
        error: e.message?.isNotEmpty == true ? e.message : 'Studio timed out',
      );
    } catch (e) {
      if (token.isCancelled || (e is DioException && CancelToken.isCancel(e))) {
        return const StudioPipelineResult(status: 'aborted', response: '');
      }
      _log('tracker-only cycle error session=$sessionId error=$e');
      return StudioPipelineResult(status: 'error', response: '', error: '$e');
    }
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
  ) => StudioActivationGate.matchesActivationKeywords(
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

  TrackerBatchResult? _firstFailedTrackerResult(
    List<TrackerBatchResult> results,
  ) {
    for (final result in results) {
      if (result.status != 'ok' || result.text.trim().isEmpty) {
        return result;
      }
    }
    return null;
  }

  List<StudioStageBrief> _trackerResultsToBriefs(
    List<TrackerBatchResult> results,
    List<StudioAgent> dueTrackers,
    Map<String, CacheProbe> cacheProbeByAgent,
  ) {
    final briefs = <StudioStageBrief>[];
    for (final result in results) {
      final probe = cacheProbeByAgent[result.agentId];
      final agent = dueTrackers.firstWhere((a) => a.id == result.agentId);
      final sanitized = result.status == 'ok'
          ? _briefParser.sanitizeIntermediateAgentOutput(agent, result.text)
          : result.text;
      briefs.add(
        StudioStageBrief(
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
        ),
      );
    }
    return briefs;
  }

  String _trackerFailureMessage(TrackerBatchResult result) {
    final reason = result.error ?? 'missing or unparseable tracker result';
    return 'Studio tracker "${result.agentName}" failed after 2 retries: '
        '$reason. Please restart generation.';
  }

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
