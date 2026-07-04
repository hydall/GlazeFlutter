import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../db/repositories/memory_book_repo.dart';
import '../db/repositories/tracker_repo.dart';
import '../db/repositories/tracker_snapshot_repo.dart';
import '../models/agent_operation_record.dart';
import '../models/memory_book.dart';
import '../models/pipeline_settings.dart';
import 'aux_llm_client.dart';
import 'ledger/durable_fact_writer.dart';
import 'ledger/ledger_op_applier.dart';
import 'ledger/visible_ledger_store.dart';
import 'studio_ledger_export_parser.dart';
import 'studio_ledger_prompt.dart';

export 'ledger/durable_fact_writer.dart';
export 'ledger/ledger_op_applier.dart';
export 'ledger/visible_ledger_store.dart';

// ─────────────────────────────────────────────────────────────────────────────
// StudioLedgerService
//
// Runs the Studio Ledger after each final assistant response (after the
// POST-cleaner when enabled). Maintains compact continuity state so long-
// running chats do not reset NPCs to card baseline.
//
// Pipeline placement (PLAN_STUDIO_LEDGER_MEMORY.md §Pipeline Placement):
//   1. Assistant response saved.
//   2. POST-cleaner runs if enabled.
//   3. User auto InfBlocks run if configured.
//   4. Studio Ledger runs on final cleaned text. ← this service
//   5. Visible ledger stored as internal diagnostics.
//   6. Export parsed and validated.
//   7. Durable facts written to MemoryBook.
//   8. Entity/relationship/arc/world/scene state written to tracker namespace.
//
// Failure behaviour:
//   - Ledger failure MUST NOT fail chat generation.
//   - On export-parse failure, store visible ledger only.
//   - On LLM failure, keep previous ledger. No writes.
//   - Cancelled/aborted: clean up, no writes.
// ─────────────────────────────────────────────────────────────────────────────

/// Result of a single Studio Ledger run.
class LedgerRunResult {
  final String
  status; // 'ok' | 'skipped' | 'disabled' | 'timeout' | 'error' | 'aborted'
  final String? visibleLedger;
  final int opsApplied;
  final int durableFactsWritten;
  final String? error;
  final int elapsedMs;
  final List<AgentOperationAttempt> attempts;
  final String? model;

  const LedgerRunResult({
    required this.status,
    this.visibleLedger,
    this.opsApplied = 0,
    this.durableFactsWritten = 0,
    this.error,
    this.elapsedMs = 0,
    this.attempts = const [],
    this.model,
  });

  static const LedgerRunResult disabled = LedgerRunResult(status: 'disabled');
  static const LedgerRunResult skipped = LedgerRunResult(status: 'skipped');
  static const LedgerRunResult aborted = LedgerRunResult(status: 'aborted');
}

/// Studio Ledger service.
///
/// Thin orchestrator:
///   1. Resolve LLM config.
///   2. Build prompt (via [StudioLedgerPrompt]).
///   3. Call LLM (via [AuxLlmClient]).
///   4. Parse + validate (via [StudioLedgerExportParser]).
///   5. Apply ops to [TrackerRepo].
///   6. Write durable facts to [MemoryBookRepo].
///
/// Constructor-injected deps (no `Ref` — all repos/client are injected).
class StudioLedgerService {
  final AuxLlmClient _llm;
  final TrackerRepo _trackerRepo;
  final MemoryBookRepo _bookRepo;
  final TrackerSnapshotRepo _snapshotRepo;
  final StudioLedgerExportParser _parser;
  final StudioLedgerPrompt _promptBuilder;
  final LedgerOpApplier _opApplier;
  final DurableFactWriter _factWriter;
  final VisibleLedgerStore _ledgerStore;

  StudioLedgerService({
    required AuxLlmClient llm,
    required TrackerRepo trackerRepo,
    required MemoryBookRepo bookRepo,
    required TrackerSnapshotRepo snapshotRepo,
  })  : _llm = llm,
        _trackerRepo = trackerRepo,
        _bookRepo = bookRepo,
        _snapshotRepo = snapshotRepo,
        _parser = const StudioLedgerExportParser(),
        _promptBuilder = const StudioLedgerPrompt(),
        _opApplier = const LedgerOpApplier(),
        _factWriter = const DurableFactWriter(),
        _ledgerStore = const VisibleLedgerStore();

  /// Run the Studio Ledger for [sessionId] on [finalAssistantText].
  ///
  /// [messageId], [swipeId], [agentSwipeId] are the provenance anchor for
  /// state writes — required for rollback.
  ///
  /// [isStillCurrent] is called before each write; returns false when a newer
  /// generation has started (abort guard).
  ///
  /// Never throws — all errors are captured in [LedgerRunResult].
  Future<LedgerRunResult> run({
    required String sessionId,
    required PipelineSettings settings,
    required AuxApiConfig config,
    required String finalAssistantText,
    required String recentHistoryText,
    required String messageId,
    required int swipeId,
    required int agentSwipeId,
    bool forceEnabled = false,
    bool Function()? isStillCurrent,
    CancelToken? cancelToken,
  }) async {
    // Studio Ledger is always-on when Studio is enabled. forceEnabled is
    // still respected for manual triggers.

    if (finalAssistantText.trim().isEmpty) {
      debugPrint('[StudioLedger] skipping — empty assistant text');
      return LedgerRunResult.skipped;
    }

    final token = cancelToken ?? CancelToken();
    if (token.isCancelled) return LedgerRunResult.aborted;

    final sw = Stopwatch()..start();

    try {
      // ── 1. LLM config is resolved by the caller via StudioSlotResolver ──
      if (token.isCancelled || isStillCurrent?.call() == false) {
        return LedgerRunResult.aborted;
      }

      // ── 2. Load context for prompt (current trackers, recent memory) ────
      final currentTrackers = await _trackerRepo.getBySessionId(sessionId);
      final book = await _bookRepo.getBySessionId(sessionId);
      final recentEntries =
          book?.entries.where((e) => e.status == 'active').take(20).toList() ??
          const <MemoryEntry>[];

      if (token.isCancelled || isStillCurrent?.call() == false) {
        return LedgerRunResult.aborted;
      }

      // ── 3. Build prompt ─────────────────────────────────────────────────
      final prompt = _promptBuilder.build(
        finalAssistantText: finalAssistantText,
        recentHistoryText: recentHistoryText,
        currentTrackers: currentTrackers,
        recentMemoryEntries: recentEntries,
      );

      // ── 4. Call LLM ─────────────────────────────────────────────────────
      final maxTokens = settings.ledger.studioLedgerMaxTokens > 0
          ? settings.ledger.studioLedgerMaxTokens
          : 2000;
      final temperature = settings.ledger.studioLedgerTemperature >= 0
          ? settings.ledger.studioLedgerTemperature
          : 0.2;
      final timeoutMs = _llm.resolveLedgerTimeout(settings);

      debugPrint(
        '[StudioLedger] starting session=$sessionId '
        'model=${config.model} '
        'timeoutMs=$timeoutMs '
        'textChars=${finalAssistantText.length}',
      );

      final outcome = await _llm.callOnceWithLog(
        config: config,
        prompt: prompt,
        maxTokens: maxTokens,
        temperature: temperature,
        timeoutMs: timeoutMs,
        cancelToken: token,
        omitReasoning: true,
      );

      if (token.isCancelled || isStillCurrent?.call() == false) {
        return LedgerRunResult.aborted;
      }

      if (!outcome.isOk || outcome.text == null || outcome.text!.isEmpty) {
        final lastAttempt = outcome.attempts.lastOrNull;
        debugPrint(
          '[StudioLedger] LLM call failed session=$sessionId '
          'status=${lastAttempt?.status} '
          'statusCode=${lastAttempt?.statusCode ?? 0} '
          'elapsedMs=${lastAttempt?.elapsedMs ?? 0} '
          'error=${lastAttempt?.error ?? "none"}',
        );
        return LedgerRunResult(
          status: 'error',
          error:
              'LLM call failed: ${lastAttempt?.status}'
              '${lastAttempt?.error != null ? ': ${lastAttempt!.error}' : ''}',
          elapsedMs: sw.elapsedMilliseconds,
          attempts: outcome.attempts,
          model: config.model,
        );
      }

      // ── 5. Parse + validate ─────────────────────────────────────────────
      final parseResult = _parser.parse(outcome.text!);

      debugPrint(
        '[StudioLedger] parsed session=$sessionId '
        'hasExport=${parseResult.hasExport} '
        'visibleLedgerChars=${parseResult.visibleLedger.length} '
        'rejection=${parseResult.rejectionReason ?? "none"}',
      );

      if (!parseResult.hasExport) {
        // Store visible ledger as diagnostics even when export is invalid.
        await _ledgerStore.storeVisibleLedger(
          sessionId: sessionId,
          messageId: messageId,
          swipeId: swipeId,
          agentSwipeId: agentSwipeId,
          visibleLedger: parseResult.visibleLedger,
          trackerRepo: _trackerRepo,
        );
        if (_isNoWriteLedgerOutput(parseResult)) {
          return LedgerRunResult(
            status: 'ok',
            visibleLedger: parseResult.visibleLedger,
            elapsedMs: sw.elapsedMilliseconds,
            attempts: outcome.attempts,
            model: config.model,
          );
        }
        return LedgerRunResult(
          status: 'error',
          visibleLedger: parseResult.visibleLedger,
          error: parseResult.rejectionReason,
          elapsedMs: sw.elapsedMilliseconds,
          attempts: outcome.attempts,
          model: config.model,
        );
      }

      if (token.isCancelled || isStillCurrent?.call() == false) {
        return LedgerRunResult.aborted;
      }

      // ── 6. Apply ops to tracker namespace ───────────────────────────────
      final export = parseResult.export!;
      var opsApplied = 0;

      for (final op in export.ops) {
        if (token.isCancelled || isStillCurrent?.call() == false) break;
        try {
          await _opApplier.applyOp(
            op: op,
            sessionId: sessionId,
            messageId: messageId,
            swipeId: swipeId,
            agentSwipeId: agentSwipeId,
            trackerRepo: _trackerRepo,
          );
          opsApplied++;
        } catch (e) {
          debugPrint('[StudioLedger] op failed key=${op.key} error=$e');
        }
      }

      debugPrint(
        '[StudioLedger] applied $opsApplied/${export.ops.length} ops '
        'session=$sessionId',
      );

      // ── 7. Write durable facts to MemoryBook ───────────────────────────
      var durableFactsWritten = 0;
      if (export.durableFacts.isNotEmpty &&
          token.isCancelled == false &&
          isStillCurrent?.call() != false) {
        durableFactsWritten = await _factWriter.writeDurableFacts(
          sessionId: sessionId,
          messageId: messageId,
          facts: export.durableFacts,
          bookRepo: _bookRepo,
        );
        debugPrint(
          '[StudioLedger] wrote $durableFactsWritten durable facts '
          'session=$sessionId',
        );
      }

      // ── 8. Store visible ledger as internal diagnostics ─────────────────
      await _ledgerStore.storeVisibleLedger(
        sessionId: sessionId,
        messageId: messageId,
        swipeId: swipeId,
        agentSwipeId: agentSwipeId,
        visibleLedger: parseResult.visibleLedger,
        trackerRepo: _trackerRepo,
      );

      // ── 9. Snapshot post-ledger tracker state for rollback/swipe safety ──
      // The mutable tracker_rows table is only the live working store. Prompt
      // reads use committed tracker_snapshots, so every ledger write must also
      // capture an immutable snapshot at the assistant output anchor.
      if (token.isCancelled == false && isStillCurrent?.call() != false) {
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
          debugPrint('[StudioLedger] snapshot write failed: $e');
        }
      }

      sw.stop();
      debugPrint(
        '[StudioLedger] done session=$sessionId '
        'ops=$opsApplied facts=$durableFactsWritten '
        'elapsedMs=${sw.elapsedMilliseconds}',
      );

      return LedgerRunResult(
        status: 'ok',
        visibleLedger: parseResult.visibleLedger,
        opsApplied: opsApplied,
        durableFactsWritten: durableFactsWritten,
        elapsedMs: sw.elapsedMilliseconds,
        attempts: outcome.attempts,
        model: config.model,
      );
    } on TimeoutException {
      sw.stop();
      debugPrint('[StudioLedger] timeout session=$sessionId');
      return LedgerRunResult(
        status: 'timeout',
        elapsedMs: sw.elapsedMilliseconds,
      );
    } catch (e) {
      sw.stop();
      if (token.isCancelled || (e is DioException && CancelToken.isCancel(e))) {
        return LedgerRunResult.aborted;
      }
      debugPrint('[StudioLedger] error session=$sessionId: $e');
      return LedgerRunResult(
        status: 'error',
        error: '$e',
        elapsedMs: sw.elapsedMilliseconds,
      );
    }
  }

  bool _isNoWriteLedgerOutput(LedgerParseResult parseResult) {
    final reason = parseResult.rejectionReason ?? '';
    if (reason == 'empty export (no ops, no durable facts)') return true;
    if (reason == 'no <glaze_memory_export> block found') return true;
    return false;
  }
}
