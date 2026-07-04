import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/llm/aux_llm_client.dart' show AuxApiConfig;
import '../../../../core/llm/studio_ledger_service.dart';
import '../../../../core/llm/studio_slot_resolver.dart';
import '../../../../core/models/agent_operation_record.dart';
import '../../../../core/models/chat_message.dart';
import '../../../../core/models/pipeline_settings.dart';
import '../../../../core/state/db_provider.dart';
import '../../../../core/state/memory_agent_providers.dart';
import '../../../../shared/widgets/glaze_toast.dart';
import '../../state/agent_operations_log_provider.dart';
import '../../state/post_gen_status_provider.dart';
import '../pipeline_utils.dart';
import 'stage_context.dart';

/// Stage 7: Studio Ledger trigger.
///
/// Fire-and-forget — does not block generation or user interaction.
/// Extracts entity/relationship/arc/world state and durable MemoryBook facts
/// from the final assistant response and persists them via
/// [StudioLedgerService]. Only runs when Studio is enabled.
class LedgerStage {
  final StageContext ctx;

  LedgerStage(this.ctx);

  /// [finalAssistantText] — the text the ledger should analyse. When the
  /// POST-cleaner is enabled, this is the cleaned text (plan §Pipeline
  /// Placement: «Ledger must not run on pre-cleaner text»). When the cleaner
  /// is disabled this is the raw streamed assistant text.
  ///
  /// [targetMessage] — the assistant message the text belongs to. Used for
  /// provenance coordinates (messageId, swipeId, agentSwipeId).
  ///
  /// [messages] — full session message list for recent-history context.
  ///
  /// Staleness guard: checks [AbortHandler.isCurrentGen] before writing (after
  /// the LLM returns). The service itself never throws — errors land in
  /// [LedgerRunResult.status].
  Future<void> run({
    required String sessionId,
    required List<ChatMessage> messages,
    required int genId,
    required String finalAssistantText,
    required ChatMessage targetMessage,
  }) async {
    if (!ctx.ref.mounted) return;

    try {
      final pipeline = ctx.ref.read(pipelineSettingsProvider);

      // Ledger is always-on when Studio is enabled. We check
      // StudioConfig.enabled to decide whether the ledger should run.
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
        await _recordDiag(
          sessionId: sessionId,
          targetMessage: targetMessage,
          reason: 'skipped, studio disabled',
        );
        return;
      }

      // Cadence (plan §Model Cadence). Studio Ledger is mandatory while Studio
      // is enabled, so cadence only gates standalone Ledger outside Studio.
      final assistantTurnCount = messages
          .where((m) => m.role == 'assistant' && !m.isTyping)
          .length;
      final cadenceReason = studioConfigEnabled
          ? null
          : _resolveCadence(
              pipeline,
              assistantTurnCount,
              finalAssistantText,
            );
      if (cadenceReason != null) {
        await _recordDiag(
          sessionId: sessionId,
          targetMessage: targetMessage,
          reason: cadenceReason,
        );
        return;
      }

      if (finalAssistantText.trim().isEmpty) {
        await _recordDiag(
          sessionId: sessionId,
          targetMessage: targetMessage,
          reason: 'skipped, empty assistant text',
        );
        return;
      }
      if (!ctx.abortHandler.isCurrentGen(genId)) {
        await _recordDiag(
          sessionId: sessionId,
          targetMessage: targetMessage,
          reason: 'skipped, stale generation',
        );
        return;
      }

      // Resolve the Studio cleaner slot (fail-explicit).
      final AuxApiConfig ledgerConfig;
      try {
        ledgerConfig = await StudioSlotResolver(ctx.ref).resolve(
          apiConfigId: studioCleanerApiConfigId,
          errorLabel: 'studio-ledger',
          modelOverride: pipeline.cleaner.postCleanerModel,
        );
      } catch (e) {
        debugPrint('[StudioLedger] slot resolution failed: $e');
        await _recordDiag(
          sessionId: sessionId,
          targetMessage: targetMessage,
          reason: 'skipped, slot resolution failed: $e',
        );
        return;
      }

      final recentHistory = extractRecentHistoryText(messages, maxMessages: 10);

      if (ctx.ref.mounted) {
        ctx.ref.read(postGenStatusProvider.notifier).state =
            PostGenStatusState.running(
              sessionId: sessionId,
              task: PostGenTask.ledger,
            );
      }

      final service = ctx.ref.read(studioLedgerServiceProvider);
      final result = await service.run(
        sessionId: sessionId,
        settings: pipeline,
        config: ledgerConfig,
        finalAssistantText: finalAssistantText,
        recentHistoryText: recentHistory,
        messageId: targetMessage.id,
        swipeId: targetMessage.swipeId,
        agentSwipeId: targetMessage.agentSwipeId,
        forceEnabled: true,
        isStillCurrent: () =>
            ctx.ref.mounted && ctx.abortHandler.isCurrentGen(genId),
      );

      await _recordDiag(
        sessionId: sessionId,
        targetMessage: targetMessage,
        reason:
            'ran, ${result.status} '
            '(ops=${result.opsApplied}, facts=${result.durableFactsWritten})'
            '${result.error == null ? '' : ': ${result.error}'}',
      );

      _recordOperation(
        sessionId: sessionId,
        targetMessage: targetMessage,
        result: result,
      );

      if (ctx.ref.mounted) {
        final detail =
            'Ledger ${result.status} (ops=${result.opsApplied}, facts=${result.durableFactsWritten})';
        ctx.ref.read(postGenStatusProvider.notifier).state =
            result.status == 'ok'
                ? PostGenStatusState.done(
                    sessionId: sessionId,
                    task: PostGenTask.ledger,
                    detail: detail,
                  )
                : PostGenStatusState.error(
                    sessionId: sessionId,
                    task: PostGenTask.ledger,
                    detail: detail,
                  );
      }

      if (ledgerStatusToOp(result.status).isFailure) {
        GlazeToast.showWithoutContext(
          'Studio Ledger failed. Open Agentic Ops -> Last turn to inspect or rerun.',
          duration: 5000,
          position: ToastPosition.top,
          isError: true,
        );
      }

      debugPrint(
        '[StudioLedger] result session=$sessionId status=${result.status} '
        'opsApplied=${result.opsApplied} '
        'factsWritten=${result.durableFactsWritten} '
        'elapsedMs=${result.elapsedMs} '
        'error=${result.error ?? "none"}',
      );
    } catch (e) {
      debugPrint(
        '[StudioLedger] pipeline trigger failed session=$sessionId: $e',
      );
      await _recordDiag(
        sessionId: sessionId,
        targetMessage: targetMessage,
        reason: 'skipped, trigger error: $e',
      );
      _recordOperation(
        sessionId: sessionId,
        targetMessage: targetMessage,
        result: LedgerRunResult(status: 'error', error: 'trigger error: $e'),
      );
      GlazeToast.showWithoutContext(
        'Studio Ledger failed. Open Agentic Ops -> Last turn to inspect or rerun.',
        duration: 5000,
        position: ToastPosition.top,
        isError: true,
      );
    }
  }

  /// Returns a non-null skip reason when the cadence should suppress the
  /// ledger run, or null when the run should proceed. Applies the
  /// per-component run mode, interval, and conditional flags (plan §Model
  /// Cadence). The Studio forces the ledger on, but the user can opt into
  /// a lower-power cadence.
  String? _resolveCadence(
    PipelineSettings pipeline,
    int assistantTurnCount,
    String finalAssistantText,
  ) {
    switch (pipeline.ledger.studioLedgerRunMode) {
      case 'disabled':
        return 'skipped, runMode=disabled';
      case 'manual':
        return 'skipped, runMode=manual';
      case 'every_n':
        final n = pipeline.ledger.studioLedgerIntervalN < 1
            ? 1
            : pipeline.ledger.studioLedgerIntervalN;
        if (n > 1 && assistantTurnCount % n != 0) {
          return 'skipped, runMode=every_n interval=$n turn=$assistantTurnCount';
        }
        return null;
      case 'conditional':
        final reasons = <String>[];
        if (pipeline.ledger.studioLedgerRunWhenMentionedEntitiesChanged &&
            !finalAssistantText.trim().isNotEmpty) {
          reasons.add('no entities changed');
        }
        if (reasons.isNotEmpty) {
          return 'skipped, conditional: ${reasons.join(', ')}';
        }
        return null;
      case 'every_turn':
      default:
        return null;
    }
  }

  /// Stores the last run/skip reason for the Studio Ledger as a
  /// `_ledger_diag:<component>` tracker row so the diagnostics sheet can
  /// show it (plan §Model Cadence: "Diagnostics should show why a component
  /// ran or skipped"). The key is the message id, so the latest run
  /// overwrites prior rows.
  Future<void> _recordDiag({
    required String sessionId,
    required ChatMessage targetMessage,
    required String reason,
  }) async {
    if (!ctx.ref.mounted) return;
    try {
      final repo = ctx.ref.read(trackerRepoProvider);
      await repo.upsertValue(
        sessionId,
        '_ledger_diag:studio_ledger',
        'turn=${targetMessage.id} • $reason',
        scope: 'ledger_diagnostic',
        provenance:
            'message=${targetMessage.id}|swipe=${targetMessage.swipeId}|'
            'agentSwipe=${targetMessage.agentSwipeId}',
      );
    } catch (_) {}
  }

  void _recordOperation({
    required String sessionId,
    required ChatMessage targetMessage,
    required LedgerRunResult result,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final startedAt = result.attempts.isNotEmpty
        ? result.attempts.first.startedAtMs
        : now - result.elapsedMs;
    final finishedAt = result.attempts.isNotEmpty
        ? result.attempts.last.startedAtMs + result.attempts.last.elapsedMs
        : now;
    final status = ledgerStatusToOp(result.status);
    ctx.ref.read(agentOperationsLogProvider.notifier).state = ctx.ref
        .read(agentOperationsLogProvider)
        .append(
          AgentOperationRecord(
            id: 'studio-ledger-${targetMessage.id}-${DateTime.now().microsecondsSinceEpoch}',
            kind: AgentOperationKind.studioLedger,
            status: status,
            sessionId: sessionId,
            messageId: targetMessage.id,
            attempts: result.attempts,
            totalElapsedMs: result.elapsedMs,
            model: result.model,
            summary: status.isOk
                ? 'ops=${result.opsApplied}, facts=${result.durableFactsWritten}'
                : result.error ?? result.status,
            startedAtMs: startedAt,
            finishedAtMs: finishedAt,
            canRegenerate: status.isFailure,
          ),
        );
  }
}
