import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/agent_operation_record.dart';
import '../models/memory_book.dart';
import '../models/pipeline_settings.dart';
import '../models/tracker.dart';
import '../state/db_provider.dart';
import '../utils/id_generator.dart';
import 'memory_agentic_policy.dart';
import 'memory_agentic_tools.dart';
import 'sidecar_llm_client.dart';

/// Agentic write-loop service (Stage 1).
///
/// After a turn is finalized, this service runs a sidecar LLM call that
/// decides what to persist: trackers (lightweight key-value state) and/or
/// memory drafts (pending human-approval entries). All writes go through
/// the policy gate (default-deny).
///
/// Extracted from `MemoryAgenticService` to keep each service under 250 lines
/// and focused on one responsibility (CODE_STYLE: one class = one job).
class MemoryAgenticWriteService {
  final Ref _ref;
  final SidecarLlmClient _llm;

  MemoryAgenticWriteService(this._ref) : _llm = SidecarLlmClient(_ref);

  /// Run the agentic write-loop after a turn is finalized.
  ///
  /// Returns [MemoryWriteLoopResult] with counts of writes/denials/errors.
  /// Never throws — errors are captured in the result.
  Future<MemoryWriteLoopResult> runWriteLoop({
    required String sessionId,
    required PipelineSettings settings,
    required String recentHistoryText,
    required List<Tracker> currentTrackers,
    required String messageId,
    required int swipeId,
    required int agentSwipeId,
    CancelToken? cancelToken,
    bool Function()? isStillCurrent,
  }) async {
    if (!settings.agenticWriteEnabled) {
      return const MemoryWriteLoopResult(status: 'disabled');
    }

    final token = cancelToken ?? CancelToken();
    if (token.isCancelled) {
      return const MemoryWriteLoopResult(status: 'aborted');
    }

    try {
      final config = await _llm.resolveConfig(
        settings,
        errorLabel: 'agentic write-loop',
      );
      if (token.isCancelled) {
        return const MemoryWriteLoopResult(status: 'aborted');
      }

      final llmOutcome = await _askLlmForWrites(
        config: config,
        settings: settings,
        recentHistoryText: recentHistoryText,
        currentTrackers: currentTrackers,
        cancelToken: token,
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
          final updatedTrackers = await _ref
              .read(trackerRepoProvider)
              .getBySessionId(sessionId);
          await _ref
              .read(trackerSnapshotRepoProvider)
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
        requests: response.memoryRequests,
        shouldAbort: () => token.isCancelled || isStillCurrent?.call() == false,
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

  Future<_LlmOutcome> _askLlmForWrites({
    required SidecarApiConfig config,
    required PipelineSettings settings,
    required String recentHistoryText,
    required List<Tracker> currentTrackers,
    required CancelToken cancelToken,
  }) async {
    final trackersBlock = currentTrackers.isEmpty
        ? '(no active trackers)'
        : currentTrackers.map((t) => '- ${t.name}: ${t.value}').join('\n');

    final prompt =
        '''You are a memory agent for a roleplay conversation. After each turn, you decide what facts to persist so they survive context truncation.

Recent conversation:
$recentHistoryText

Current trackers:
$trackersBlock

Decide what to write. You have two tools:

1. updateTracker — lightweight key-value state that persists across turns (mood, location, relationship status, inventory, ongoing promises).
2. writeMemory — a pending memory draft for significant events, revelations, promises. These require user approval before becoming active.

Respond with ONLY a JSON object (no markdown, no explanation):
{
  "trackers": [
    {"name": "mood", "value": "happy", "scope": "chat"},
    {"name": "location", "value": "tavern"}
  ],
  "memories": [
    {"title": "Lucy reveals the chip", "content": "...", "keys": ["Lucy", "chip"]}
  ]
}

Rules:
- Only write trackers that CHANGED or are NEW. Don't repeat unchanged trackers.
- Only create memory drafts for SIGNIFICANT events (not every turn).
- If nothing is worth persisting, return: {"trackers": [], "memories": []}
- Keep tracker values short (1-5 words).
- Memory content should be 1-3 sentences describing what happened and why it matters.''';

    final outcome = await _llm.callOnceWithLog(
      config: config,
      prompt: prompt,
      maxTokens: 1000,
      temperature: 0.2,
      timeoutMs: settings.sidecarTimeoutMs,
      cancelToken: cancelToken,
    );
    if (!outcome.isOk || outcome.text == null) {
      return _LlmOutcome(
        response: null,
        attempts: outcome.attempts,
        totalElapsedMs: outcome.totalElapsedMs,
      );
    }
    _WriteLoopResponse? response;
    try {
      final decoded = jsonDecode(outcome.text!);
      if (decoded is! Map<String, dynamic>) {
        response = null;
      } else {
        final trackerRequests = <TrackerWriteRequest>[];
        final trackerRaw = decoded['trackers'];
        if (trackerRaw is List) {
          for (final item in trackerRaw) {
            if (item is Map<String, dynamic>) {
              final req = TrackerWriteRequest.fromJson(item);
              if (req.name.isNotEmpty && req.value.isNotEmpty) {
                trackerRequests.add(req);
              }
            }
          }
        }

        final memoryRequests = <MemoryWriteRequest>[];
        final memoryRaw = decoded['memories'];
        if (memoryRaw is List) {
          for (final item in memoryRaw) {
            if (item is Map<String, dynamic>) {
              final req = MemoryWriteRequest.fromJson(item);
              if (req.title.isNotEmpty && req.content.isNotEmpty) {
                memoryRequests.add(req);
              }
            }
          }
        }

        response = _WriteLoopResponse(
          trackerRequests: trackerRequests,
          memoryRequests: memoryRequests,
        );
      }
    } catch (_) {
      response = null;
    }
    return _LlmOutcome(
      response: response,
      attempts: outcome.attempts,
      totalElapsedMs: outcome.totalElapsedMs,
    );
  }

  Future<TrackerWriteResult> _executeTrackerWrites({
    required MemoryAgenticPolicy policy,
    required String sessionId,
    required List<TrackerWriteRequest> requests,
    required String provenance,
    required bool Function() shouldAbort,
  }) async {
    if (requests.isEmpty) return const TrackerWriteResult();

    final repo = _ref.read(trackerRepoProvider);
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
    required List<MemoryWriteRequest> requests,
    required bool Function() shouldAbort,
  }) async {
    if (requests.isEmpty) return const MemoryWriteResult();

    final repo = _ref.read(memoryBookRepoProvider);
    var written = 0;
    var denied = 0;
    final errors = <String>[];

    // Auto-approve: agent writes land directly as MemoryEntry (kind='agent',
    // source='agentic') instead of pending drafts. The user can still edit
    // or delete them afterwards via the MemoryBook UI. messageIds is set to
    // [messageId] so deleting the source assistant message drops the entry
    // via MemoryBookRepo.deleteForMessage.
    final entries = <MemoryEntry>[];
    for (final req in requests) {
      if (shouldAbort()) break;
      final decision = policy.canUse(MemoryAgenticTool.writeMemory);
      if (!decision.allowed) {
        denied++;
        errors.add('Denied "${req.title}": ${decision.reason}');
        continue;
      }
      entries.add(
        MemoryEntry(
          id: generateId().replaceAll('draft_', 'mem_'),
          title: req.title,
          content: req.content,
          keys: req.keys,
          messageIds: [messageId],
          status: 'active',
          createdAt: DateTime.now().millisecondsSinceEpoch,
          source: 'agentic',
          kind: 'agent',
        ),
      );
      written++;
    }

    if (entries.isNotEmpty && !shouldAbort()) {
      try {
        await repo.appendApprovedEntries(sessionId, entries);
      } catch (e) {
        debugPrint('[MemoryAgenticWriteService] appendApprovedEntries failed: $e');
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

class _WriteLoopResponse {
  final List<TrackerWriteRequest> trackerRequests;
  final List<MemoryWriteRequest> memoryRequests;

  const _WriteLoopResponse({
    this.trackerRequests = const [],
    this.memoryRequests = const [],
  });
}

class _LlmOutcome {
  final _WriteLoopResponse? response;
  final List<AgentOperationAttempt> attempts;
  final int totalElapsedMs;

  const _LlmOutcome({
    this.response,
    this.attempts = const [],
    this.totalElapsedMs = 0,
  });
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
