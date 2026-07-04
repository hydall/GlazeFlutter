import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../db/repositories/memory_book_repo.dart';
import '../db/repositories/tracker_repo.dart';
import '../db/repositories/tracker_snapshot_repo.dart';
import '../models/agent_operation_record.dart';
import '../models/memory_book.dart';
import '../models/pipeline_settings.dart';
import '../models/studio_config.dart';
import '../models/tracker.dart';
import '../utils/id_generator.dart';
import 'agentic_write_request_parser.dart';
import 'memory_agentic_policy.dart';
import 'memory_agentic_tools.dart';
import 'aux_llm_client.dart';
import 'macro_engine.dart';

/// Agentic write-loop service (Stage 1).
///
/// After a turn is finalized, this service runs an auxiliary LLM call that
/// decides what to persist: trackers (lightweight key-value state) and/or
/// memory drafts (pending human-approval entries). All writes go through
/// the policy gate (default-deny).
///
/// Extracted from `MemoryAgenticService` to keep each service under 250 lines
/// and focused on one responsibility (CODE_STYLE: one class = one job).
class MemoryAgenticWriteService {
  final AuxLlmClient _llm;
  final MemoryBookRepo _bookRepo;
  final TrackerRepo _trackerRepo;
  final TrackerSnapshotRepo _snapshotRepo;
  late final AgenticWriteRequestParser _parser = AgenticWriteRequestParser(
    _llm,
  );

  MemoryAgenticWriteService({
    required this._llm,
    required this._bookRepo,
    required this._trackerRepo,
    required this._snapshotRepo,
  });

  /// Run the agentic write-loop after a turn is finalized.
  ///
  /// Returns [MemoryWriteLoopResult] with counts of writes/denials/errors.
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
    // Agentic write-loop is always-on (Studio-only). The write-loop always
    // runs subject to cadence. Agent writes always require manual approval.

    final token = cancelToken ?? CancelToken();
    if (token.isCancelled) {
      return const MemoryWriteLoopResult(status: 'aborted');
    }

    try {
      if (token.isCancelled) {
        return const MemoryWriteLoopResult(status: 'aborted');
      }

      // NEW (patch #4): pass existing MemoryBook entries to the LLM so it
      // can avoid duplicates and write append-only newFacts to existing
      // entries instead of rewriting them. Mirrors Marinara's
      // `<existing_entries>` prompt block. See
      // docs/plans/PLAN_MEMORY_CONTINUITY.md §1.
      List<MemoryEntry> existingMemories = const [];
      try {
        final book = await _bookRepo
            .getBySessionId(sessionId);
        if (book != null) {
          existingMemories = book.entries;
        }
      } catch (e) {
        debugPrint(
          '[AgenticWrite] failed to load existing entries for prompt: $e',
        );
      }

      final llmOutcome = await _parser.askLlmForWrites(
        config: config,
        settings: settings,
        recentHistoryText: recentHistoryText,
        currentTrackers: currentTrackers,
        cancelToken: token,
        existingMemories: existingMemories,
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
        'memories=${response.memoryRequests.length} '
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
          final updatedTrackers = await _trackerRepo
              .getBySessionId(sessionId);
          await _snapshotRepo
              .upsertTrackers(
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

      if (token.isCancelled || isStillCurrent?.call() == false) {
        return MemoryWriteLoopResult(
          status: 'aborted',
          trackerResult: trackerResult,
          attempts: llmOutcome.attempts,
          totalElapsedMs: llmOutcome.totalElapsedMs,
        );
      }

      final memoryResult = await _executeMemoryWrites(
        policy: policy,
        sessionId: sessionId,
        messageId: messageId,
        swipeId: swipeId,
        agentSwipeId: agentSwipeId,
        requests: response.memoryRequests,
        shouldAbort: () => token.isCancelled || isStillCurrent?.call() == false,
        requireApproval: true,
      );

      return MemoryWriteLoopResult(
        status: 'ok',
        trackerResult: trackerResult,
        memoryResult: memoryResult,
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

  Future<MemoryWriteResult> _executeMemoryWrites({
    required MemoryAgenticPolicy policy,
    required String sessionId,
    required String messageId,
    required int swipeId,
    required int agentSwipeId,
    required List<MemoryWriteRequest> requests,
    required bool Function() shouldAbort,
    bool requireApproval = false,
  }) async {
    if (requests.isEmpty) return const MemoryWriteResult();

    final repo = _bookRepo;
    var written = 0;
    var denied = 0;
    final errors = <String>[];

    // Three write paths:
    // - requireApproval=true (hardcoded) → ALL requests become MemoryDrafts
    //   in pendingDrafts for manual user review. Append-only updates to
    //   existing entries are also deferred: the newFacts are written as
    //   a draft whose content is the appended text, NOT merged into the
    //   existing entry until the user approves. See
    //   docs/plans/PLAN_MEMORY_CONTINUITY.md §4.
    // - existingEntryId empty → CREATE a new MemoryEntry (kind='agent',
    //   source='agentic') and batch-append via appendApprovedEntries.
    // - existingEntryId non-empty → APPEND-only newFacts to the existing
    //   entry via appendFactsToEntry (atomic RMW, Marinara append-only
    //   semantics). The existing entry is NOT rewritten.
    if (requireApproval) {
      final drafts = <MemoryDraft>[];
      for (final req in requests) {
        if (shouldAbort()) break;
        final decision = policy.canUse(MemoryAgenticTool.writeMemory);
        if (!decision.allowed) {
          denied++;
          errors.add('Denied "${req.title}": ${decision.reason}');
          continue;
        }
        drafts.add(
          MemoryDraft(
            id: generateId(),
            title: req.title,
            content: req.content,
            keys: req.keys,
            messageIds: [messageId],
            sourceSwipeId: swipeId,
            sourceAgentSwipeId: agentSwipeId,
            status: 'pending_generation',
            source: 'agentic',
            createdAt: DateTime.now().millisecondsSinceEpoch,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
        written++;
      }
      if (drafts.isNotEmpty && !shouldAbort()) {
        try {
          await repo.appendDrafts(sessionId, drafts);
        } catch (e) {
          debugPrint(
            '[MemoryAgenticWriteService] appendDrafts (approval) failed: $e',
          );
          errors.add('Batch write error: $e');
          written = 0;
        }
      }
      return MemoryWriteResult(
        written: written,
        denied: denied,
        errors: errors,
        requests: requests,
      );
    }

    final newEntries = <MemoryEntry>[];
    final appendRequests = <MemoryWriteRequest>[];
    for (final req in requests) {
      if (shouldAbort()) break;
      final decision = policy.canUse(MemoryAgenticTool.writeMemory);
      if (!decision.allowed) {
        denied++;
        errors.add('Denied "${req.title}": ${decision.reason}');
        continue;
      }
      if (req.existingEntryId.isNotEmpty) {
        appendRequests.add(req);
      } else {
        newEntries.add(
          MemoryEntry(
            id: generateId().replaceAll('draft_', 'mem_'),
            title: req.title,
            content: req.content,
            keys: req.keys,
            messageIds: [messageId],
            sourceSwipeId: swipeId,
            sourceAgentSwipeId: agentSwipeId,
            status: 'active',
            createdAt: DateTime.now().millisecondsSinceEpoch,
            source: 'agentic',
            kind: 'agent',
          ),
        );
        written++;
      }
    }

    // Append-only updates to existing entries (atomic per-entry RMW).
    for (final req in appendRequests) {
      if (shouldAbort()) break;
      try {
        final updated = await repo.appendFactsToEntry(
          sessionId: sessionId,
          entryId: req.existingEntryId,
          newFacts: req.content,
          newKeys: req.keys,
        );
        if (updated) {
          written++;
        } else {
          // Entry was deleted between the LLM call and this write —
          // fall back to creating a new entry so the fact is not lost.
          newEntries.add(
            MemoryEntry(
              id: generateId().replaceAll('draft_', 'mem_'),
              title: req.title,
              content: req.content,
              keys: req.keys,
              messageIds: [messageId],
              sourceSwipeId: swipeId,
              sourceAgentSwipeId: agentSwipeId,
              status: 'active',
              createdAt: DateTime.now().millisecondsSinceEpoch,
              source: 'agentic',
              kind: 'agent',
            ),
          );
          written++;
        }
      } catch (e) {
        debugPrint('[MemoryAgenticWriteService] appendFactsToEntry failed: $e');
        errors.add('Append error on "${req.title}": $e');
      }
    }

    if (newEntries.isNotEmpty && !shouldAbort()) {
      try {
        await repo.appendApprovedEntries(sessionId, newEntries);
      } catch (e) {
        debugPrint(
          '[MemoryAgenticWriteService] appendApprovedEntries failed: $e',
        );
        errors.add('Batch write error: $e');
        written = 0;
      }
    }

    return MemoryWriteResult(
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
  final MemoryWriteResult? memoryResult;
  final String? error;
  final List<AgentOperationAttempt> attempts;
  final int totalElapsedMs;

  const MemoryWriteLoopResult({
    this.status = 'ok',
    this.trackerResult,
    this.memoryResult,
    this.error,
    this.attempts = const [],
    this.totalElapsedMs = 0,
  });

  int get totalWritten =>
      (trackerResult?.written ?? 0) + (memoryResult?.written ?? 0);

  bool get anyWrites => totalWritten > 0;
}
