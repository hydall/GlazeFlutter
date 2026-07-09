import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../db/repositories/tracker_repo.dart';
import '../db/repositories/tracker_snapshot_repo.dart';
import '../models/agent_operation_record.dart';

import '../models/pipeline_settings.dart';
import '../models/studio_config.dart';
import '../models/tracker.dart';

import 'agentic_write_request_parser.dart';
import 'memory_agentic_policy.dart';
import 'memory_agentic_tools.dart';
import 'aux_llm_client.dart';
import 'macro_engine.dart';

/// Agentic write-loop service (Stage 1).
///
/// After a turn is finalized, this service runs an auxiliary LLM call that
/// updates lightweight structured trackers. MemoryBook range summaries and
/// raw-message recall own long-term history; this loop never writes memories.
///
/// Extracted from `MemoryAgenticService` to keep each service under 250 lines
/// and focused on one responsibility (CODE_STYLE: one class = one job).
class MemoryAgenticWriteService {
  final AuxLlmClient _llm;
  final TrackerRepo _trackerRepo;
  final TrackerSnapshotRepo _snapshotRepo;
  late final AgenticWriteRequestParser _parser = AgenticWriteRequestParser(
    _llm,
  );

  MemoryAgenticWriteService({
    required this._llm,
    required this._trackerRepo,
    required this._snapshotRepo,
  });

  /// Run the agentic write-loop after a turn is finalized.
  ///
  /// Returns [MemoryWriteLoopResult] with tracker write diagnostics.
  /// Never throws — errors are captured in the result.
  Future<MemoryWriteLoopResult> runWriteLoop({
    required String sessionId,
    required PipelineSettings settings,
    required AuxApiConfig config,
    required String recentHistoryText,
    required List<Tracker> currentTrackers,
    required String messageId,
    required int swipeId,
    required int agentSwipeId,
    CancelToken? cancelToken,
    bool Function()? isStillCurrent,
    List<StudioPresetBlock> writeloopBlocks = const [],
    MacroContext? macroCtx,
  }) async {
    // Tracker write-loop is always-on in Studio and runs subject to cadence.

    final token = cancelToken ?? CancelToken();
    if (token.isCancelled) {
      return const MemoryWriteLoopResult(status: 'aborted');
    }

    try {
      if (token.isCancelled) {
        return const MemoryWriteLoopResult(status: 'aborted');
      }

      final llmOutcome = await _parser.askLlmForWrites(
        config: config,
        settings: settings,
        recentHistoryText: recentHistoryText,
        currentTrackers: currentTrackers,
        cancelToken: token,

        writeloopBlocks: writeloopBlocks,
        macroCtx: macroCtx,
      );

      if (token.isCancelled || isStillCurrent?.call() == false) {
        return MemoryWriteLoopResult(
          status: 'aborted',
          attempts: llmOutcome.attempts,
          totalElapsedMs: llmOutcome.totalElapsedMs,
        );
      }
      final response = llmOutcome.response;
      if (response == null) {
        debugPrint(
          '[AgenticWrite] LLM returned null/unparseable response '
          '(model=${config.model})',
        );
        return MemoryWriteLoopResult(
          status: 'ok',
          attempts: llmOutcome.attempts,
          totalElapsedMs: llmOutcome.totalElapsedMs,
        );
      }

      debugPrint(
        '[AgenticWrite] LLM parsed trackers=${response.trackerRequests.length} '
        '(model=${config.model})',
      );

      final policy = MemoryAgenticPolicy(
        const MemoryAgenticSettings(
          enabled: true,
          readOnly: false,
          writeToolsEnabled: true,
          requireExplicitDiffApproval: false,
        ),
      );

      if (token.isCancelled || isStillCurrent?.call() == false) {
        return MemoryWriteLoopResult(
          status: 'aborted',
          attempts: llmOutcome.attempts,
          totalElapsedMs: llmOutcome.totalElapsedMs,
        );
      }

      final trackerResult = await _executeTrackerWrites(
        policy: policy,
        sessionId: sessionId,
        requests: response.trackerRequests,
        provenance: 'memory_agent',
        shouldAbort: () => token.isCancelled || isStillCurrent?.call() == false,
      );

      // Snapshot the post-write tracker state at the anchor
      // (messageId, swipeId, agentSwipeId) so delete/swipe/regen rollback is
      // emergent. `committed` stays false until the user sends a follow-up
      // (Phase 6). Re-read the full tracker list from the repo to capture the
      // merged state (pre-existing + newly written).
      if (!token.isCancelled && isStillCurrent?.call() != false) {
        try {
          final updatedTrackers = await _trackerRepo.getBySessionId(sessionId);
          await _snapshotRepo.upsertTrackers(
            sessionId: sessionId,
            messageId: messageId,
            swipeId: swipeId,
            agentSwipeId: agentSwipeId,
            trackers: updatedTrackers,
          );
        } catch (e) {
          debugPrint('[AgenticWrite] snapshot write failed: $e');
        }
      }

      return MemoryWriteLoopResult(
        status: 'ok',
        trackerResult: trackerResult,
        attempts: llmOutcome.attempts,
        totalElapsedMs: llmOutcome.totalElapsedMs,
      );
    } on TimeoutException {
      return const MemoryWriteLoopResult(status: 'timeout');
    } catch (e) {
      if (token.isCancelled || (e is DioException && CancelToken.isCancel(e))) {
        return const MemoryWriteLoopResult(status: 'aborted');
      }
      return MemoryWriteLoopResult(status: 'error', error: '$e');
    }
  }

  Future<TrackerWriteResult> _executeTrackerWrites({
    required MemoryAgenticPolicy policy,
    required String sessionId,
    required List<TrackerWriteRequest> requests,
    required String provenance,
    required bool Function() shouldAbort,
  }) async {
    if (requests.isEmpty) return const TrackerWriteResult();

    final repo = _trackerRepo;
    var written = 0;
    var denied = 0;
    final errors = <String>[];

    for (final req in requests) {
      if (shouldAbort()) break;
      final decision = policy.canUse(MemoryAgenticTool.writeTracker);
      if (!decision.allowed) {
        denied++;
        errors.add('Denied ${req.name}: ${decision.reason}');
        continue;
      }
      try {
        await repo.upsertValue(
          sessionId,
          req.name,
          req.value,
          scope: req.scope,
          provenance: provenance,
        );
        written++;
      } catch (e) {
        errors.add('Error ${req.name}: $e');
      }
    }

    return TrackerWriteResult(
      written: written,
      denied: denied,
      errors: errors,
      requests: requests,
    );
  }
}

class MemoryWriteLoopResult {
  final String status;
  final TrackerWriteResult? trackerResult;

  final String? error;
  final List<AgentOperationAttempt> attempts;
  final int totalElapsedMs;

  const MemoryWriteLoopResult({
    this.status = 'ok',
    this.trackerResult,

    this.error,
    this.attempts = const [],
    this.totalElapsedMs = 0,
  });

  int get totalWritten => trackerResult?.written ?? 0;

  bool get anyWrites => totalWritten > 0;
}
