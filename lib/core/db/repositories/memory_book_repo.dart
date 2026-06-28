import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_db.dart';
import '../tables.dart';
import '../../models/memory_book.dart';
import '../../state/memory_settings_provider.dart';
import '../../utils/time_helpers.dart';
import '../../../features/cloud_sync/sync_repo_interfaces.dart';

part 'memory_book_repo.g.dart';

@DriftAccessor(tables: [MemoryBookRows])
class MemoryBookRepo extends DatabaseAccessor<AppDatabase>
    with _$MemoryBookRepoMixin
    implements SyncMemoryBookStore {
  MemoryBookRepo(super.db, this._ref);

  final Ref _ref;

  Future<MemoryBook> ensureForSession(String sessionId) async {
    final existing = await getBySessionId(sessionId);
    if (existing != null) return existing;
    final global = _ref.read(memoryGlobalSettingsProvider);
    final book = MemoryBook(
      id: 'memorybook_$sessionId',
      sessionId: sessionId,
      settings: MemoryBookSettings(
        enabled: global.enabled,
        memoryMode: global.memoryMode,
        autoCreateEnabled: global.autoCreateEnabled,
        autoGenerateEnabled: global.autoGenerateEnabled,
        maxInjectedEntries: global.maxInjectedEntries,
        memoryExcerptingEnabled: global.memoryExcerptingEnabled,
        memoryPackingMode: global.memoryPackingMode,
        memoryExcerptTokensPerChunk: global.memoryExcerptTokensPerChunk,
        memoryExcerptChunksPerEntry: global.memoryExcerptChunksPerEntry,
        chunkFirstTopEntries: global.chunkFirstTopEntries,
        chunkFirstTopChunks: global.chunkFirstTopChunks,
        maxInjectedTokens: global.maxInjectedTokens,
        memoryBudgetPreset: global.memoryBudgetPreset,
        autoCreateInterval: global.autoCreateInterval,
        autoCreateLagMessages: global.autoCreateLagMessages,
        useDelayedAutomation: global.useDelayedAutomation,
        injectionTarget: global.injectionTarget,
        batchSize: global.batchSize,
        vectorSearchEnabled: global.vectorSearchEnabled,
        keyMatchMode: global.keyMatchMode,
        promptPreset: global.promptPreset,
        diversityAware: global.diversityAware,
        diversityPenalty: global.diversityPenalty,
        recencyBoost: global.recencyBoost,
        recencyHalfLifeDays: global.recencyHalfLifeDays,
        importanceBoost: global.importanceBoost,
        importanceWeight: global.importanceWeight,
        sourceWindowExclusion: global.sourceWindowExclusion,
        factualContinuityGuardEnabled: global.factualContinuityGuardEnabled,
        queryIncludeAssistant: global.queryIncludeAssistant,
        queryRecentTurns: global.queryRecentTurns,
        queryMaxChars: global.queryMaxChars,
        cadenceInterval: global.cadenceInterval,
      ),
    );
    await put(book);
    return book;
  }

  @override
  Future<List<MemoryBook>> getAll() async {
    final rows = await select(memoryBookRows).get();
    return rows.map(_rowToModel).toList();
  }

  @override
  Future<void> put(MemoryBook book) {
    return into(memoryBookRows).insertOnConflictUpdate(
      MemoryBookRowsCompanion.insert(
        sessionId: book.sessionId,
        entriesJson: Value(
          jsonEncode(book.entries.map((e) => e.toJson()).toList()),
        ),
        pendingDraftsJson: Value(
          jsonEncode(book.pendingDrafts.map((d) => d.toJson()).toList()),
        ),
        settingsJson: Value(jsonEncode(book.settings.toJson())),
        lastProcessedMessageCount: Value(book.lastProcessedMessageCount),
        updatedAt: Value(currentTimestampSeconds()),
      ),
    );
  }

  Future<void> updateSettings(String sessionId, MemoryBookSettings settings) {
    return (update(
      memoryBookRows,
    )..where((t) => t.sessionId.equals(sessionId))).write(
      MemoryBookRowsCompanion(
        settingsJson: Value(jsonEncode(settings.toJson())),
        updatedAt: Value(currentTimestampSeconds()),
      ),
    );
  }

  /// Atomically appends [drafts] to the pending drafts of the memory book
  /// for [sessionId]. Wraps the read-modify-write in a transaction so
  /// concurrent writes cannot interleave (database.md Rule 3).
  ///
  /// Used by the agentic write-loop (Stage 1) to append agent-generated
  /// drafts without racing with other memory book writes.
  Future<void> appendDrafts(String sessionId, List<MemoryDraft> drafts) async {
    if (drafts.isEmpty) return;
    await transaction(() async {
      final existing = await getBySessionId(sessionId);
      final book = existing ??
          MemoryBook(
            id: 'memorybook_$sessionId',
            sessionId: sessionId,
          );
      await put(
        book.copyWith(
          pendingDrafts: [...book.pendingDrafts, ...drafts],
        ),
      );
    });
  }

  /// Atomically appends [entries] to the approved entries of the memory book
  /// for [sessionId]. Wraps the read-modify-write in a transaction so
  /// concurrent writes cannot interleave (database.md Rule 3).
  ///
  /// Used by the agentic write-loop (Stage 1) to auto-approve agent-generated
  /// memory entries: instead of landing in `pendingDrafts` for manual approval,
  /// each validated agent write is promoted to a `MemoryEntry` (kind='agent',
  /// source='agentic') immediately and persisted to `entriesJson`. The user
  /// can still delete or edit the entry afterwards via the MemoryBook UI.
  Future<void> appendApprovedEntries(
    String sessionId,
    List<MemoryEntry> entries,
  ) async {
    if (entries.isEmpty) return;
    await transaction(() async {
      final existing = await getBySessionId(sessionId);
      final book = existing ??
          MemoryBook(
            id: 'memorybook_$sessionId',
            sessionId: sessionId,
          );
      await put(
        book.copyWith(
          entries: [...book.entries, ...entries],
        ),
      );
    });
  }

  /// Atomically appends [newFacts] to the `content` of the existing entry
  /// with [entryId] in the memory book for [sessionId], and merges [newKeys]
  /// into that entry's `keys` (case-insensitive dedup). Wraps the
  /// read-modify-write in a transaction (database.md Rule 3).
  ///
  /// Append-only semantics (patch #4 — Marinara analog): the existing
  /// entry's content is NEVER rewritten — only appended to. This preserves
  /// prior agent writes and protects against regen-time fact loss (the
  /// agentic write-loop at regen sees the existing entry via
  /// `<existing_memory_entries>` in its prompt and only appends new facts).
  ///
  /// Returns true if the entry was found and updated, false if no entry
  /// with [entryId] exists in the book (caller may fall back to creating
  /// a new entry via [appendApprovedEntries]).
  ///
  /// See docs/plans/PLAN_MEMORY_CONTINUITY.md §1 (patch #4) and §2.2.
  Future<bool> appendFactsToEntry({
    required String sessionId,
    required String entryId,
    required String newFacts,
    List<String> newKeys = const [],
  }) async {
    if (newFacts.trim().isEmpty) return false;
    var didAppend = false;
    await transaction(() async {
      final existing = await getBySessionId(sessionId);
      if (existing == null) return;
      final idx = existing.entries.indexWhere((e) => e.id == entryId);
      if (idx < 0) return;
      final entry = existing.entries[idx];
      // Locked entries are user-protected — agent cannot modify them.
      // Mirrors Marinara's `locked` flag. See
      // docs/plans/PLAN_MEMORY_CONTINUITY.md §2.4.
      if (entry.locked) return;
      didAppend = true;
      final appendedContent = entry.content.isEmpty
          ? newFacts
          : '${entry.content}\n\n$newFacts';
      // Case-insensitive key merge — preserves existing keys and adds new
      // ones without duplicates.
      final existingLower = entry.keys
          .map((k) => k.toLowerCase())
          .toSet();
      final mergedKeys = <String>[...entry.keys];
      for (final k in newKeys) {
        if (k.isEmpty) continue;
        if (existingLower.add(k.toLowerCase())) {
          mergedKeys.add(k);
        }
      }
      final updatedEntry = entry.copyWith(
        content: appendedContent,
        keys: mergedKeys,
      );
      final updatedEntries = List<MemoryEntry>.from(existing.entries);
      updatedEntries[idx] = updatedEntry;
      await put(existing.copyWith(entries: updatedEntries));
    });
    return didAppend;
  }

  /// Atomically removes all `MemoryEntry` and `MemoryDraft` items whose
  /// `messageIds` contain [messageId] from the memory book for [sessionId].
  /// Wraps the read-modify-write in a transaction (database.md Rule 3).
  ///
  /// Called by `ChatMessageService.deleteMessage` so deleting an assistant
  /// message also drops the memory entries/drafts that were sourced from it.
  /// Items whose `messageIds` does NOT contain [messageId] are preserved
  /// (they were sourced from other messages and should survive).
  Future<void> deleteForMessage(String sessionId, String messageId) async {
    await transaction(() async {
      final existing = await getBySessionId(sessionId);
      if (existing == null) return;
      final keptEntries = existing.entries
          .where((e) => !e.messageIds.contains(messageId))
          .toList();
      final keptDrafts = existing.pendingDrafts
          .where((d) => !d.messageIds.contains(messageId))
          .toList();
      if (keptEntries.length == existing.entries.length &&
          keptDrafts.length == existing.pendingDrafts.length) {
        return;
      }
      await put(
        existing.copyWith(entries: keptEntries, pendingDrafts: keptDrafts),
      );
    });
  }

  Future<void> copyForSessionBranch({
    required String fromSessionId,
    required String toSessionId,
  }) async {
    final source = await getBySessionId(fromSessionId);
    if (source == null) return;
    await put(
      source.copyWith(id: 'memorybook_$toSessionId', sessionId: toSessionId),
    );
  }

  @override
  Future<void> deleteBySessionId(String sessionId) {
    return (delete(
      memoryBookRows,
    )..where((t) => t.sessionId.equals(sessionId))).go();
  }

  @override
  Future<MemoryBook?> getBySessionId(String sessionId) async {
    final row = await (select(
      memoryBookRows,
    )..where((t) => t.sessionId.equals(sessionId))).getSingleOrNull();
    if (row == null) return null;
    return _rowToModel(row);
  }

  MemoryBook _rowToModel(MemoryBookRow row) {
    List<MemoryEntry> entries;
    try {
      final list = jsonDecode(row.entriesJson) as List<dynamic>;
      entries = list
          .map((e) => MemoryEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      entries = [];
    }

    List<MemoryDraft> pendingDrafts;
    try {
      final list = jsonDecode(row.pendingDraftsJson) as List<dynamic>;
      pendingDrafts = list
          .map((e) => MemoryDraft.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      pendingDrafts = [];
    }

    MemoryBookSettings settings;
    try {
      settings = MemoryBookSettings.fromJson(
        jsonDecode(row.settingsJson) as Map<String, dynamic>,
      );
    } catch (_) {
      settings = const MemoryBookSettings();
    }

    return MemoryBook(
      id: 'memorybook_${row.sessionId}',
      sessionId: row.sessionId,
      entries: entries,
      pendingDrafts: pendingDrafts,
      settings: settings,
      lastProcessedMessageCount: row.lastProcessedMessageCount,
      updatedAt: row.updatedAt,
    );
  }
}
