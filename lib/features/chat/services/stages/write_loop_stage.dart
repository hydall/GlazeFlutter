import 'package:flutter/foundation.dart';

import '../../../../core/llm/aux_llm_client.dart' show AuxApiConfig;
import '../../../../core/llm/studio_slot_resolver.dart';
import '../../../../core/models/agent_operation_record.dart';
import '../../../../core/models/chat_message.dart';
import '../../../../core/models/pipeline_settings.dart';
import '../../../../core/state/db_provider.dart';
import '../../../../core/state/memory_agent_providers.dart';
import '../../state/agent_operations_log_provider.dart';
import '../../state/post_gen_status_provider.dart';
import '../pipeline_utils.dart';
import 'stage_context.dart';

/// Stage 6: Agentic write-loop trigger.
///
/// Fire-and-forget — does not block generation or user interaction.
/// Only called on the normal (non-regen) path, after the assistant message
/// is persisted to DB. Reads MemoryBook settings, fetches current trackers,
/// extracts recent history text, and delegates to
/// [MemoryAgenticService.runWriteLoop].
///
/// Studio-only — gates by `StudioConfig.enabled`.
class WriteLoopStage {
  final StageContext ctx;

  WriteLoopStage(this.ctx);

  /// Staleness guard: checks `abortHandler.isCurrentGen(genId)` before
  /// executing writes (after the LLM call returns). The write-loop itself
  /// creates its own CancelToken and checks it after each await.
  Future<void> run({
    required String sessionId,
    required List<ChatMessage> messages,
    required int genId,
    String? regenTargetId,
  }) async {
    if (!ctx.ref.mounted) return;

    final pipeline = ctx.ref.read(pipelineSettingsProvider);

    try {
      // Write-loop is Studio-only. Gate by StudioConfig.enabled.
      var studioConfigEnabled = false;
      var studioCleanerApiConfigId = '';
      try {
        final studioConfig = await ctx.ref
            .read(studioConfigRepoProvider)
            .getBySessionId(sessionId);
        studioConfigEnabled = studioConfig?.enabled == true;
        studioCleanerApiConfigId = studioConfig?.cleanerApiConfigId ?? '';
      } catch (_) {}
      if (!studioConfigEnabled) {
        debugPrint('[AgenticWrite] skipping — Studio not enabled');
        return;
      }
      if (!ctx.ref.mounted || !ctx.abortHandler.isCurrentGen(genId)) return;

      final bookRepo = ctx.ref.read(memoryBookRepoProvider);
      final book = await bookRepo.getBySessionId(sessionId);
      if (!ctx.ref.mounted || !ctx.abortHandler.isCurrentGen(genId)) return;
      if (book == null) return;

      // Cadence: the write-loop runs every 5 assistant turns (hardcoded).
      // Studio-only — without Studio config, trackers don't update.
      final assistantTurnCount = messages
          .where((m) => m.role == 'assistant' && !m.isTyping)
          .length;
      final cadenceReason = _resolveCadence(
        pipeline,
        assistantTurnCount,
      );
      if (cadenceReason != null) {
        debugPrint('[AgenticWrite] $cadenceReason');
        return;
      }

      // Read the current tracker state from snapshots (preferred) with a
      // tracker_rows fallback for legacy sessions pre-migration. On regen,
      // exclude the regenerating message's own stale snapshot so the base
      // state does not read the pre-regen tracker values.
      final snapshotRepo = ctx.ref.read(trackerSnapshotRepoProvider);
      final trackerRepo = ctx.ref.read(trackerRepoProvider);
      final snapshot = regenTargetId != null
          ? await snapshotRepo.getLatestCommittedExcludingMessage(
              sessionId,
              regenTargetId,
            )
          : await snapshotRepo.getLatestCommitted(sessionId);
      final trackers =
          snapshot?.trackers ?? await trackerRepo.getBySessionId(sessionId);
      if (!ctx.ref.mounted || !ctx.abortHandler.isCurrentGen(genId)) return;

      final recentHistory = extractRecentHistoryText(
        messages,
        maxMessages: 12,
        // Historical replay (Marinara `buildHistoricalLorebookKeeperContext`
        // analog): at regen, slice messages up to AND INCLUDING the regen
        // target so the write-loop sees the same context the original turn
        // saw, not the current post-regen state. Without this, regen
        // would produce different entries than the original turn.
        // See docs/plans/PLAN_MEMORY_CONTINUITY.md §2.2.
        upToMessageId: regenTargetId,
      );

      // Anchor for the tracker snapshot: the just-finished assistant turn.
      // On both normal send and regen, SavedMessageWriter seeds a single
      // 'final' agentSwipe (agentSwipeId=0), so the anchor is
      // (messageId, swipeId, 0). Guard against non-assistant trailing
      // messages defensively.
      final lastAssistant = messages.lastWhere(
        (m) => m.role == 'assistant',
        orElse: () => messages.last,
      );

      // Guard: if the user deleted the assistant message between the
      // generation finishing and the write-loop starting, the message no
      // longer exists in the session. Writing trackers/memory for a deleted
      // message would create orphaned entries tied to a non-existent
      // messageId. Re-read the session and abort if the target is gone.
      final currentSession = await ctx.ref
          .read(chatRepoProvider)
          .getById(sessionId);
      if (currentSession == null ||
          !currentSession.messages.any((m) => m.id == lastAssistant.id)) {
        debugPrint(
          '[AgenticWrite] target message ${lastAssistant.id} no longer exists '
          'in session $sessionId — aborting write-loop',
        );
        return;
      }

      // Resolve the Studio cleaner slot for the write-loop (fail-explicit).
      final AuxApiConfig writeLoopConfig;
      try {
        writeLoopConfig = await StudioSlotResolver(ctx.ref).resolve(
          apiConfigId: studioCleanerApiConfigId,
          errorLabel: 'agentic write-loop',
          modelOverride: pipeline.cleaner.postCleanerModel,
        );
      } catch (e) {
        debugPrint('[AgenticWrite] slot resolution failed: $e');
        return;
      }
      if (!ctx.ref.mounted || !ctx.abortHandler.isCurrentGen(genId)) return;

      debugPrint(
        '[AgenticWrite] starting write-loop session=$sessionId '
        'model=${writeLoopConfig.model} '
        'timeoutMs=${pipeline.memoryPipeline.auxTimeoutMs} '
        'existingTrackers=${trackers.length} '
        'historyChars=${recentHistory.length}',
      );

      if (ctx.ref.mounted) {
        ctx.ref.read(postGenStatusProvider.notifier).state =
            PostGenStatusState.running(
              sessionId: sessionId,
              task: PostGenTask.writeLoop,
            );
      }

      final agenticService = ctx.ref.read(memoryAgenticWriteServiceProvider);
      final result = await agenticService.runWriteLoop(
        sessionId: sessionId,
        settings: pipeline,
        config: writeLoopConfig,
        recentHistoryText: recentHistory,
        currentTrackers: trackers,
        messageId: lastAssistant.id,
        swipeId: lastAssistant.swipeId,
        agentSwipeId: lastAssistant.agentSwipeId,
        isStillCurrent: () =>
            ctx.ref.mounted && ctx.abortHandler.isCurrentGen(genId),
      );

      debugPrint(
        '[AgenticWrite] result session=$sessionId status=${result.status} '
        'trackersWritten=${result.trackerResult?.written ?? 0} '
        'trackersDenied=${result.trackerResult?.denied ?? 0} '
        'memoriesWritten=${result.memoryResult?.written ?? 0} '
        'error=${result.error ?? "none"}',
      );

      if (ctx.ref.mounted) {
        final detail =
            'Write-loop done (${result.trackerResult?.written ?? 0} trackers, '
            '${result.memoryResult?.written ?? 0} memories)';
        ctx.ref.read(postGenStatusProvider.notifier).state =
            result.status == 'ok'
                ? PostGenStatusState.done(
                    sessionId: sessionId,
                    task: PostGenTask.writeLoop,
                    detail: detail,
                  )
                : PostGenStatusState.error(
                    sessionId: sessionId,
                    task: PostGenTask.writeLoop,
                    detail: 'Write-loop ${result.status}',
                  );
      }

      // Post-write guard: the user may have deleted the assistant message
      // WHILE the write-loop was running (it can take 60s+). If so, the
      // trackers and memory entries just written are now orphaned — tied to
      // a messageId that no longer exists. Clean them up so the UI doesn't
      // show stale state for a deleted turn.
      if (result.status == 'ok' && ctx.ref.mounted) {
        final postCheck = await ctx.ref.read(chatRepoProvider).getById(sessionId);
        if (postCheck == null ||
            !postCheck.messages.any((m) => m.id == lastAssistant.id)) {
          debugPrint(
            '[AgenticWrite] message ${lastAssistant.id} deleted during '
            'write-loop — purging orphaned trackers + memory',
          );
          await ctx.ref
              .read(memoryBookRepoProvider)
              .deleteForMessage(sessionId, lastAssistant.id)
              .catchError((Object _) {});
          await ctx.ref
              .read(trackerSnapshotRepoProvider)
              .deleteForMessage(sessionId, lastAssistant.id)
              .catchError((Object _) {});
          final snapshot = await ctx.ref
              .read(trackerSnapshotRepoProvider)
              .getLatestCommitted(sessionId);
          if (snapshot == null) {
            await ctx.ref.read(trackerRepoProvider).clearForSession(sessionId);
          } else {
            await ctx.ref
                .read(trackerRepoProvider)
                .replaceForSession(sessionId, snapshot.trackers);
          }
        }
      }

      // Record the agentic write-loop in the operations log so the user
      // can inspect retries (e.g. 502 → 200) from the Agentic Ops UI.
      if (result.status != 'disabled' && result.attempts.isNotEmpty) {
        final status = agenticWriteStatusToOp(result.status);
        final totalWritten = result.totalWritten;
        ctx.ref.read(agentOperationsLogProvider.notifier).state = ctx.ref
            .read(agentOperationsLogProvider)
            .append(
              AgentOperationRecord(
                id: 'agentic-write-$sessionId-${DateTime.now().microsecondsSinceEpoch}',
                kind: AgentOperationKind.agenticWrite,
                status: status,
                sessionId: sessionId,
                messageId: messages.isNotEmpty ? messages.last.id : null,
                attempts: result.attempts,
                totalElapsedMs: result.totalElapsedMs,
                model: pipeline.memoryBookApi.generationModel.isEmpty
                    ? null
                    : pipeline.memoryBookApi.generationModel,
                summary: status == AgentOperationStatus.ok
                    ? (totalWritten > 0
                          ? 'wrote $totalWritten item${totalWritten > 1 ? 's' : ''}'
                          : 'no changes')
                    : result.status,
                startedAtMs: result.attempts.first.startedAtMs,
                finishedAtMs:
                    result.attempts.last.startedAtMs +
                    result.attempts.last.elapsedMs,
                canRegenerate: status.isFailure,
              ),
            );
      }
    } catch (e) {
      debugPrint('[AgenticWrite] failed session=$sessionId error=$e');
    }
  }

  /// Returns a non-null skip reason when the cadence should suppress the
  /// agentic write-loop, or null when the run should proceed.
  ///
  /// Cadence is hardcoded: the write-loop runs every 5 assistant turns
  /// (batch mode — the LLM analyzes 5 U-A turns at once).
  String? _resolveCadence(
    PipelineSettings pipeline,
    int assistantTurnCount,
  ) {
    const n = 5;
    if (n > 1 && assistantTurnCount % n != 0) {
      return 'skipping write-loop — hardcoded every $n turns, turn=$assistantTurnCount (not a multiple)';
    }
    return null;
  }
}
