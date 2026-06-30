import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/repositories/memory_book_repo.dart';
import '../db/repositories/tracker_repo.dart';
import '../models/agent_operation_record.dart';
import '../models/memory_book.dart';
import '../models/pipeline_settings.dart';
import '../models/studio_ledger_export.dart';
import '../state/db_provider.dart';
import '../utils/id_generator.dart';
import '../utils/time_helpers.dart';
import 'sidecar_llm_client.dart';
import 'studio_ledger_export_parser.dart';
import 'studio_ledger_prompt.dart';

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
///   3. Call LLM (via [SidecarLlmClient]).
///   4. Parse + validate (via [StudioLedgerExportParser]).
///   5. Apply ops to [TrackerRepo].
///   6. Write durable facts to [MemoryBookRepo].
///
/// Constructor-injected [Ref] for accessing repos/providers.
class StudioLedgerService {
  final Ref _ref;
  final SidecarLlmClient _llm;
  final StudioLedgerExportParser _parser;
  final StudioLedgerPrompt _promptBuilder;

  StudioLedgerService(this._ref)
    : _llm = SidecarLlmClient(_ref),
      _parser = const StudioLedgerExportParser(),
      _promptBuilder = const StudioLedgerPrompt();

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
    required String finalAssistantText,
    required String recentHistoryText,
    required String messageId,
    required int swipeId,
    required int agentSwipeId,
    bool forceEnabled = false,
    bool Function()? isStillCurrent,
    CancelToken? cancelToken,
  }) async {
    if (!settings.studioLedgerEnabled && !forceEnabled) {
      return LedgerRunResult.disabled;
    }

    if (finalAssistantText.trim().isEmpty) {
      debugPrint('[StudioLedger] skipping — empty assistant text');
      return LedgerRunResult.skipped;
    }

    final token = cancelToken ?? CancelToken();
    if (token.isCancelled) return LedgerRunResult.aborted;

    final sw = Stopwatch()..start();

    try {
      // ── 1. Resolve LLM config ───────────────────────────────────────────
      final config = await _llm.resolveConfigForLedger(settings);
      if (token.isCancelled || isStillCurrent?.call() == false) {
        return LedgerRunResult.aborted;
      }

      // ── 2. Load context for prompt (current trackers, recent memory) ────
      final trackerRepo = _ref.read(trackerRepoProvider);
      final bookRepo = _ref.read(memoryBookRepoProvider);

      final currentTrackers = await trackerRepo.getBySessionId(sessionId);
      final book = await bookRepo.getBySessionId(sessionId);
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
      final maxTokens = settings.studioLedgerMaxTokens > 0
          ? settings.studioLedgerMaxTokens
          : 2000;
      final temperature = settings.studioLedgerTemperature >= 0
          ? settings.studioLedgerTemperature
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
        debugPrint(
          '[StudioLedger] LLM call failed session=$sessionId '
          'status=${outcome.attempts.lastOrNull?.status}',
        );
        return LedgerRunResult(
          status: 'error',
          error: 'LLM call failed: ${outcome.attempts.lastOrNull?.status}',
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
        await _storeVisibleLedger(
          sessionId: sessionId,
          messageId: messageId,
          swipeId: swipeId,
          agentSwipeId: agentSwipeId,
          visibleLedger: parseResult.visibleLedger,
          trackerRepo: trackerRepo,
        );
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
          await _applyOp(
            op: op,
            sessionId: sessionId,
            messageId: messageId,
            swipeId: swipeId,
            agentSwipeId: agentSwipeId,
            trackerRepo: trackerRepo,
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
        durableFactsWritten = await _writeDurableFacts(
          sessionId: sessionId,
          messageId: messageId,
          facts: export.durableFacts,
          bookRepo: bookRepo,
        );
        debugPrint(
          '[StudioLedger] wrote $durableFactsWritten durable facts '
          'session=$sessionId',
        );
      }

      // ── 8. Store visible ledger as internal diagnostics ─────────────────
      await _storeVisibleLedger(
        sessionId: sessionId,
        messageId: messageId,
        swipeId: swipeId,
        agentSwipeId: agentSwipeId,
        visibleLedger: parseResult.visibleLedger,
        trackerRepo: trackerRepo,
      );

      // ── 9. Snapshot post-ledger tracker state for rollback/swipe safety ──
      // The mutable tracker_rows table is only the live working store. Prompt
      // reads use committed tracker_snapshots, so every ledger write must also
      // capture an immutable snapshot at the assistant output anchor.
      if (token.isCancelled == false && isStillCurrent?.call() != false) {
        try {
          final updatedTrackers = await trackerRepo.getBySessionId(sessionId);
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

  // ── Op application ──────────────────────────────────────────────────────────

  Future<void> _applyOp({
    required LedgerOp op,
    required String sessionId,
    required String messageId,
    required int swipeId,
    required int agentSwipeId,
    required TrackerRepo trackerRepo,
  }) async {
    // Plan §Manual Overrides and Locks: if canon_lock:<key> = 'true',
    // Studio Ledger must not update that state key.
    final lockKey = 'canon_lock:${op.key}';
    final lock = await trackerRepo.get(sessionId, lockKey);
    if (lock != null && lock.value.trim().toLowerCase() == 'true') {
      debugPrint('[StudioLedger] op blocked by canon_lock key=${op.key}');
      return;
    }

    final provenance = _buildLedgerProvenance(
      messageId: messageId,
      swipeId: swipeId,
      agentSwipeId: agentSwipeId,
      evidence: op.evidence,
    );

    switch (op.op) {
      case 'set':
        await trackerRepo.upsertValue(
          sessionId,
          op.key,
          op.value,
          scope: 'ledger',
          provenance: provenance,
        );
      case 'append_unique':
        // Read current value and append if not already present.
        final existing = await trackerRepo.get(sessionId, op.key);
        final currentValue = existing?.value ?? '';
        if (_containsValue(currentValue, op.value)) {
          debugPrint(
            '[StudioLedger] append_unique skipped (already present) '
            'key=${op.key}',
          );
          return;
        }
        final newValue = currentValue.isEmpty
            ? op.value
            : '$currentValue\n${op.value}';
        await trackerRepo.upsertValue(
          sessionId,
          op.key,
          newValue,
          scope: 'ledger',
          provenance: provenance,
        );
      case 'delete':
        await trackerRepo.delete(sessionId, op.key);
    }
  }

  /// Returns true when [haystack] already contains [needle] as a line or
  /// substring (case-insensitive, trimmed). Used for append_unique semantics.
  bool _containsValue(String haystack, String needle) {
    if (haystack.isEmpty || needle.isEmpty) return false;
    final needleLower = needle.trim().toLowerCase();
    return haystack
        .split('\n')
        .any((line) => line.trim().toLowerCase() == needleLower);
  }

  // ── Durable facts ───────────────────────────────────────────────────────────

  /// Write [facts] to MemoryBook with dedup by title+content hash.
  /// Returns count of facts actually written.
  Future<int> _writeDurableFacts({
    required String sessionId,
    required String messageId,
    required List<LedgerDurableFact> facts,
    required MemoryBookRepo bookRepo,
  }) async {
    if (facts.isEmpty) return 0;
    var written = 0;

    // Load existing entries for dedup.
    final book = await bookRepo.getBySessionId(sessionId);
    final existing = book?.entries ?? const <MemoryEntry>[];
    final existingHashes = existing
        .map((MemoryEntry e) => e.sourceHash)
        .where((String h) => h.isNotEmpty)
        .toSet();

    final toAdd = <MemoryEntry>[];
    for (final fact in facts) {
      if (fact.title.trim().isEmpty || fact.content.trim().isEmpty) continue;
      final hash = _hashFact(fact.title, fact.content);
      if (existingHashes.contains(hash)) {
        debugPrint(
          '[StudioLedger] dedup: skipping existing fact "${fact.title}"',
        );
        continue;
      }
      existingHashes.add(hash);
      toAdd.add(
        MemoryEntry(
          id: generateId(),
          title: fact.title.trim(),
          content: fact.content.trim(),
          keys: fact.keys,
          kind: 'studio_ledger',
          source: 'studio_ledger',
          sourceHash: hash,
          messageIds: [messageId],
          importance: 0.6,
          status: 'active',
          createdAt: currentTimestampSeconds(),
        ),
      );
      written++;
    }

    if (toAdd.isNotEmpty) {
      await bookRepo.appendApprovedEntries(sessionId, toAdd);
    }

    return written;
  }

  /// Compute a stable dedup hash for a (title, content) pair.
  String _hashFact(String title, String content) {
    final normalized =
        '${title.trim().toLowerCase()}|${content.trim().toLowerCase()}';
    // Simple djb2 hash — enough for dedup without crypto overhead.
    var hash = 5381;
    for (final cp in normalized.codeUnits) {
      hash = ((hash << 5) + hash) ^ cp;
      hash &= 0xFFFFFFFF; // keep 32-bit
    }
    return 'sl_${hash.toRadixString(16)}';
  }

  // ── Visible ledger ──────────────────────────────────────────────────────────

  /// Store the visible ledger as an internal diagnostic tracker row.
  /// Key: `_ledger:$messageId` — scoped to this specific message.
  Future<void> _storeVisibleLedger({
    required String sessionId,
    required String messageId,
    required int swipeId,
    required int agentSwipeId,
    required String visibleLedger,
    required TrackerRepo trackerRepo,
  }) async {
    if (visibleLedger.isEmpty) return;
    try {
      await trackerRepo.upsertValue(
        sessionId,
        '_ledger:$messageId',
        visibleLedger.length > 8000
            ? '${visibleLedger.substring(0, 8000)}…[truncated]'
            : visibleLedger,
        scope: 'ledger_diagnostic',
        provenance: _buildLedgerProvenance(
          messageId: messageId,
          swipeId: swipeId,
          agentSwipeId: agentSwipeId,
        ),
      );
    } catch (e) {
      debugPrint('[StudioLedger] failed to store visible ledger: $e');
    }
  }

  String _buildLedgerProvenance({
    required String messageId,
    required int swipeId,
    required int agentSwipeId,
    String evidence = '',
  }) {
    final parts = <String>[
      'source=studio_ledger',
      'message=$messageId',
      'swipe=$swipeId',
      'agentSwipe=$agentSwipeId',
    ];
    final trimmedEvidence = evidence.trim();
    if (trimmedEvidence.isNotEmpty) {
      parts.add(
        'evidence=${trimmedEvidence.substring(0, trimmedEvidence.length.clamp(0, 80))}',
      );
    }
    return parts.join('|');
  }
}
