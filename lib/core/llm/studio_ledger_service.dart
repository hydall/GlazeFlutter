import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../db/repositories/character_knowledge_fact_repo.dart';
import '../db/repositories/memory_book_repo.dart';
import '../db/repositories/tracker_repo.dart';
import '../db/repositories/tracker_snapshot_repo.dart';
import '../models/agent_operation_record.dart';
import '../models/character_knowledge_fact.dart';
import '../models/memory_book.dart';
import '../models/pipeline_settings.dart';
import '../models/studio_config.dart';
import '../models/tracker.dart';
import '../utils/id_generator.dart';
import 'aux_llm_client.dart';
import 'ledger/ledger_op_applier.dart';
import 'macro_engine.dart';
import 'prompt/ledger_tracker_loader.dart';
import 'studio/studio_aux_prompt_assembler.dart';
import 'studio_ledger_export_parser.dart';
import 'studio_ledger_prompt.dart';

export 'ledger/ledger_op_applier.dart';

// ─────────────────────────────────────────────────────────────────────────────
// StudioLedgerService
//
// Runs the Studio Ledger after each final assistant response (after the
// POST-cleaner when enabled). Maintains compact continuity state so long-
// running chats do not reset NPCs to card baseline.
//
// Pipeline placement: after final assistant text is settled —
//   1. Assistant response saved.
//   2. POST-cleaner runs if enabled.
//   3. User auto InfBlocks run if configured.
//   4. Studio Ledger runs on final cleaned text. ← this service
//   5. Visible ledger returned for internal diagnostics.
//   6. Export parsed and validated.
//   7. Entity/relationship/arc/world/scene state written to tracker namespace.
//   8. Snapshot of tracker state saved for rollback/swipe safety.
// Ledger must not run on pre-cleaner text. Manual user InfBlocks do not delay
// canon state writes. User InfBlocks are auxiliary evidence only — the ledger
// can read them but must not promote their contents to canon unless supported
// by the final assistant text, visible accepted chat, or existing canon.
//
// Ledger canon lives in tracker_rows → <studio_session_state>. MemoryBook
// remains a separate, user-controlled long-term range-summary workflow.
//
// Failure behaviour:
//   - Ledger failure MUST NOT fail chat generation.
//   - On export-parse failure, return the visible ledger without writes.
//   - On LLM failure, keep previous ledger. No writes.
//   - Cancelled/aborted: clean up, no writes.
// ─────────────────────────────────────────────────────────────────────────────

/// Result of a single Studio Ledger run.
class LedgerRunResult {
  final String
  status; // 'ok' | 'skipped' | 'disabled' | 'timeout' | 'error' | 'aborted'
  final String? visibleLedger;
  final int opsApplied;
  final String? error;
  final int elapsedMs;
  final List<AgentOperationAttempt> attempts;
  final String? model;

  const LedgerRunResult({
    required this.status,
    this.visibleLedger,
    this.opsApplied = 0,
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
///   6. Snapshot tracker state for rollback safety.
///
/// Constructor-injected deps (no `Ref` — all repos/client are injected).
class StudioLedgerService {
  final AuxLlmClient _llm;
  final TrackerRepo _trackerRepo;
  final MemoryBookRepo _bookRepo;
  final TrackerSnapshotRepo _snapshotRepo;
  final CharacterKnowledgeFactRepo _knowledgeFactRepo;
  final LedgerTrackerLoader _ledgerTrackerLoader;
  final StudioLedgerExportParser _parser;
  final StudioLedgerPrompt _promptBuilder;
  final LedgerOpApplier _opApplier;

  StudioLedgerService({
    required this._llm,
    required this._trackerRepo,
    required this._bookRepo,
    required this._snapshotRepo,
    required this._knowledgeFactRepo,
    required this._ledgerTrackerLoader,
  }) : _parser = const StudioLedgerExportParser(),
       _promptBuilder = const StudioLedgerPrompt(),
       _opApplier = const LedgerOpApplier();

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
    List<StudioPresetBlock> ledgerBlocks = const [],
    MacroContext? macroCtx,
    bool commitSnapshot = false,
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

      // ── 2. Load prompt base (committed canon + live manual overrides) ────
      final promptTrackers = await _ledgerTrackerLoader
          .loadEffectiveLedgerTrackers(sessionId);
      final book = await _bookRepo.getBySessionId(sessionId);
      final recentEntries =
          book?.entries.where((e) => e.status == 'active').take(20).toList() ??
          const <MemoryEntry>[];

      if (token.isCancelled || isStillCurrent?.call() == false) {
        return LedgerRunResult.aborted;
      }

      // ── 3. Build prompt ─────────────────────────────────────────────────
      final prompt = _buildLedgerPrompt(
        finalAssistantText: finalAssistantText,
        recentHistoryText: recentHistoryText,
        currentTrackers: promptTrackers,
        recentMemoryEntries: recentEntries,
        ledgerBlocks: ledgerBlocks,
        macroCtx: macroCtx,
      );

      debugPrint(
        '[StudioLedger] prompt session=$sessionId '
        'chars=${prompt.length} '
        'usingPresetBlocks=${ledgerBlocks.isNotEmpty && macroCtx != null} '
        'first500=${prompt.length > 500 ? prompt.substring(0, 500) : prompt}',
      );

      // ── 4. Call LLM ─────────────────────────────────────────────────────
      final maxTokens = settings.ledger.studioLedgerMaxTokens > 0
          ? settings.ledger.studioLedgerMaxTokens
          : 15000;
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
      final rawResponse = outcome.text!;
      debugPrint(
        '[StudioLedger] raw response session=$sessionId '
        'chars=${rawResponse.length} '
        'first1000=${rawResponse.length > 1000 ? rawResponse.substring(0, 1000) : rawResponse}',
      );

      final parseResult = _parser.parse(rawResponse);

      debugPrint(
        '[StudioLedger] parsed session=$sessionId '
        'hasExport=${parseResult.hasExport} '
        'visibleLedgerChars=${parseResult.visibleLedger.length} '
        'rejection=${parseResult.rejectionReason ?? "none"}',
      );

      if (!parseResult.hasExport) {
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

      // Atomic facts use the same tentative assistant-swipe anchor as the
      // tracker snapshot. They become visible only when the next user turn
      // commits that anchor.
      if (export.knowledgeFacts.isNotEmpty &&
          token.isCancelled == false &&
          isStillCurrent?.call() != false) {
        try {
          await _knowledgeFactRepo.insertAllTentative(
            export.knowledgeFacts
                .map(
                  (fact) => CharacterKnowledgeFact(
                    id: generateId(),
                    chatSessionId: sessionId,
                    knowerKey: fact.knowerKey,
                    knowerName: fact.knowerName,
                    subjectKey: fact.subjectKey,
                    subjectName: fact.subjectName,
                    factClass: CharacterKnowledgeFactClass.fromWireName(
                      fact.factClass,
                    ),
                    scopeKey: fact.scopeKey,
                    predicate: fact.predicate,
                    object: fact.object,
                    epistemicState:
                        CharacterKnowledgeEpistemicState.fromWireName(
                          fact.epistemicState,
                        ),
                    confidence: fact.confidence,
                    importance: fact.importance,
                    entities: fact.entities,
                    topics: fact.topics,
                    sourceMessageId: messageId,
                    sourceSwipeId: swipeId,
                    sourceAgentSwipeId: agentSwipeId,
                    supersedesId: fact.supersedesId,
                  ),
                )
                .toList(growable: false),
          );
        } catch (e) {
          debugPrint('[StudioLedger] knowledge fact write failed: $e');
        }
      }

      // ── 7. Snapshot post-ledger tracker state for rollback/swipe safety ──
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
            committed: commitSnapshot,
          );
        } catch (e) {
          debugPrint('[StudioLedger] snapshot write failed: $e');
        }
      }

      sw.stop();
      debugPrint(
        '[StudioLedger] done session=$sessionId '
        'ops=$opsApplied '
        'elapsedMs=${sw.elapsedMilliseconds}',
      );

      return LedgerRunResult(
        status: 'ok',
        visibleLedger: parseResult.visibleLedger,
        opsApplied: opsApplied,
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

  /// Builds the ledger prompt from preset blocks when available, falling
  /// back to [StudioLedgerPrompt] when no preset blocks are supplied.
  /// The output structure template (`<glaze_memory_export>` +
  /// `<studio_ledger>`) is always code-appended — the parser depends on it.
  String _buildLedgerPrompt({
    required String finalAssistantText,
    required String recentHistoryText,
    required List<Tracker> currentTrackers,
    required List<MemoryEntry> recentMemoryEntries,
    List<StudioPresetBlock> ledgerBlocks = const [],
    MacroContext? macroCtx,
  }) {
    if (ledgerBlocks.isEmpty || macroCtx == null) {
      return _promptBuilder.build(
        finalAssistantText: finalAssistantText,
        recentHistoryText: recentHistoryText,
        currentTrackers: currentTrackers,
        recentMemoryEntries: recentMemoryEntries,
      );
    }

    final trackerBlock = _promptBuilder.buildCurrentStateBlock(
      currentTrackers,
      '$recentHistoryText\n$finalAssistantText',
    );
    final keyCatalog = _promptBuilder.buildExistingKeyCatalog(currentTrackers);
    final memoryBlock = _buildMemoryBlock(recentMemoryEntries);

    final runtimeSuffix =
        '''
<current_state>
$trackerBlock
</current_state>

<existing_keys>
$keyCatalog
</existing_keys>

<existing_memory>
$memoryBlock
</existing_memory>

<recent_chat>
$recentHistoryText
</recent_chat>

<final_assistant_response>
$finalAssistantText
</final_assistant_response>

Now produce the Studio Ledger output. You MUST return BOTH blocks below.
The <glaze_memory_export> block is MANDATORY — even when there is nothing
to write, include it with empty arrays. Do not omit it under any circumstance.

Required response template (follow this exact structure):
<glaze_memory_export>
{"ops":[],"durableFacts":[]}
</glaze_memory_export>
<studio_ledger>
Compact continuity snapshot here.
</studio_ledger>

The <glaze_memory_export> block MUST come first, before <studio_ledger>.
It must contain a single JSON object with "ops" and "durableFacts" arrays.
When there are no state changes or durable facts, output empty arrays —
do NOT skip the block.

Ops format:
{"ops":[{"op":"set","key":"npc:Name.field","value":"…","evidence":"…","eventState":"completed"},…],"durableFacts":[{"title":"…","content":"…","keys":["…"],"entities":["…"]}]}

Allowed namespaces: npc:, relationship:, arc:, world:, scene.
Allowed ops: set, append_unique, delete.
Reuse an exact key from <current_state> or <existing_keys> for the same fact; update it with set instead of creating a synonym key.
Allowed eventState: planned, suggested, threatened, attempted, completed, failed, cancelled, unknown (or omit).''';

    return const StudioAuxPromptAssembler().assemble(
      blocks: ledgerBlocks,
      section: 'ledger',
      macroCtx: macroCtx,
      runtimeSuffix: runtimeSuffix,
    );
  }

  String _buildMemoryBlock(List<MemoryEntry> entries) {
    if (entries.isEmpty) return '(no existing memory)';
    return entries
        .take(20)
        .map((e) {
          final keys = e.keys.isEmpty ? '' : ' [${e.keys.join(', ')}]';
          final locked = e.locked ? ' [locked]' : '';
          return '- ${e.title.isNotEmpty ? e.title : e.id}$keys$locked';
        })
        .join('\n');
  }

  bool _isNoWriteLedgerOutput(LedgerParseResult parseResult) {
    final reason = parseResult.rejectionReason ?? '';
    if (reason == 'no <glaze_memory_export> block found') return true;
    if (reason ==
        'empty export (no ops, no durable facts, no knowledge facts)') {
      return true;
    }
    return false;
  }
}
