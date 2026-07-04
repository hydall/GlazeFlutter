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
import 'studio/studio_tracker_phase_runner.dart';
import 'studio/studio_tracker_result_mapper.dart';

// Re-export so existing importers of `AgentPhaseSplit` via this file (e.g.
// tests, studio_post_processing) keep their import path after the move to
// studio_activation_gate.dart.
export 'studio_activation_gate.dart' show AgentPhaseSplit;
export 'studio/studio_tracker_phase_runner.dart' show PreGenPhaseResult;

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
  late final StudioTrackerResultMapper _resultMapper = StudioTrackerResultMapper(
    _briefParser,
    _briefCache,
  );
  late final StudioTrackerPhaseRunner _phaseRunner = StudioTrackerPhaseRunner(
    ref: _ref,
    briefCache: _briefCache,
    briefParser: _briefParser,
    batchCoordinator: _batchCoordinator,
    executor: _executor,
    resultMapper: _resultMapper,
    log: _log,
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
    PromptResult? finalPromptResult,
    PromptPayload? finalPromptPayload,
    required ApiConfig apiConfig,
    required String sessionId,
    CancelToken? cancelToken,
    void Function(String text, String? reasoning)? onFinalResponseUpdate,
  }) async {
    final token = cancelToken ?? CancelToken();
    if (token.isCancelled) {
      return const StudioPipelineResult(status: 'aborted', response: '');
    }

    final phaseResult = await _phaseRunner.run(
      config: config,
      promptResult: promptResult,
      promptPayload: promptPayload,
      apiConfig: apiConfig,
      sessionId: sessionId,
      token: token,
    );

    if (phaseResult.status != 'ok') {
      return StudioPipelineResult(
        status: phaseResult.status,
        response: '',
        stageBriefs: phaseResult.briefs,
        error: phaseResult.error,
      );
    }

    final briefs = phaseResult.briefs;
    final split = phaseResult.split!;
    final turnIndex = phaseResult.turnIndex;
    final historyForScan = phaseResult.historyForScan;
    final studioPreset = phaseResult.studioPreset!;
    final finalAgent = split.finalAgent!;
    final postGenTrackers = split.postGenTrackers;

    final generatorPromptResult = finalPromptResult ?? promptResult;
    final generatorPromptPayload = finalPromptPayload ?? promptPayload;
    final agentResult = await _executor.runFinalGenerator(
      agent: finalAgent,
      promptResult: generatorPromptResult,
      promptPayload: generatorPromptPayload,
      apiConfig: apiConfig,
      config: config,
      studioPreset: studioPreset,
      priorBriefs: briefs,
      sessionId: sessionId,
      cancelToken: token,
      apiConfigId: config.expensiveApiConfigId,
      onFinalResponseUpdate: onFinalResponseUpdate,
    );
    if (token.isCancelled) {
      return const StudioPipelineResult(status: 'aborted', response: '');
    }

    var mainResponse = agentResult.text;
    var mainReasoning = agentResult.reasoning;
    final rawResponseJson = agentResult.rawResponseJson;

    // Feature 6 — post-processing phase. Post-gen trackers run AFTER the
    // generator, receive `mainResponse` in their context, and can produce
    // an edited/rewritten version. They run sequentially in `order`, each
    // receiving the current `mainResponse`. The final post-gen tracker's
    // non-empty output replaces `mainResponse`. Post-gen trackers do NOT
    // stream to the UI.
    final postBriefs = <StudioStageBrief>[];
    for (final agent in postGenTrackers) {
      if (token.isCancelled) {
        return const StudioPipelineResult(status: 'aborted', response: '');
      }
      final interval = agent.runInterval <= 0 ? 1 : agent.runInterval;
      if (turnIndex % interval != 0) continue;
      if (agent.activationKeywords.isNotEmpty &&
          !StudioActivationGate.matchesActivationKeywords(
            agent.activationKeywords,
            historyForScan,
            agent.activationScanDepth,
          )) {
        continue;
      }
      final result = await _executor.runPostProcessingTracker(
        agent: agent,
        mainResponse: mainResponse,
        promptResult: generatorPromptResult,
        promptPayload: generatorPromptPayload,
        apiConfig: apiConfig,
        config: config,
        studioPreset: studioPreset,
        sessionId: sessionId,
        cancelToken: token,
        apiConfigId: config.cleanerApiConfigId,
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
  }

  /// Tracker-only cycle: runs the pre-gen tracker phase and returns the
  /// produced briefs WITHOUT firing the final generator or post-gen
  /// trackers. Used by [TrackerMemoryRecoveryService] to restore lost
  /// `studioOutputs` without burning the final-generator model on every
  /// historical message.
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

    final phaseResult = await _phaseRunner.run(
      config: config,
      promptResult: promptResult,
      promptPayload: promptPayload,
      apiConfig: apiConfig,
      sessionId: sessionId,
      token: token,
    );

    return StudioPipelineResult(
      status: phaseResult.status,
      response: '',
      stageBriefs: phaseResult.briefs,
      error: phaseResult.error,
    );
  }

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
