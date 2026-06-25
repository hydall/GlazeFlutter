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
        generationSource: global.generationSource,
        generationModel: global.generationModel,
        generationEndpoint: global.generationEndpoint,
        generationApiKey: global.generationApiKey,
        generationTemperature: global.generationTemperature,
        generationMaxTokens: global.generationMaxTokens,
        promptPreset: global.promptPreset,
        diversityAware: global.diversityAware,
        diversityPenalty: global.diversityPenalty,
        recencyBoost: global.recencyBoost,
        recencyHalfLifeDays: global.recencyHalfLifeDays,
        importanceBoost: global.importanceBoost,
        importanceWeight: global.importanceWeight,
        sourceWindowExclusion: global.sourceWindowExclusion,
        factualContinuityGuardEnabled: global.factualContinuityGuardEnabled,
        classifierEnabled: global.classifierEnabled,
        classifierSource: global.classifierSource,
        classifierModel: global.classifierModel,
        classifierEndpoint: global.classifierEndpoint,
        classifierApiKey: global.classifierApiKey,
        classifierTimeoutMs: global.classifierTimeoutMs,
        sidecarEnabled: global.sidecarEnabled,
        sidecarSource: global.sidecarSource,
        sidecarModel: global.sidecarModel,
        sidecarEndpoint: global.sidecarEndpoint,
        sidecarApiKey: global.sidecarApiKey,
        sidecarTimeoutMs: global.sidecarTimeoutMs,
        queryIncludeAssistant: global.queryIncludeAssistant,
        queryRecentTurns: global.queryRecentTurns,
        queryMaxChars: global.queryMaxChars,
        cadenceInterval: global.cadenceInterval,
        consolidationEnabled: global.consolidationEnabled,
        consolidationThreshold: global.consolidationThreshold,
        consolidationSource: global.consolidationSource,
        consolidationModel: global.consolidationModel,
        consolidationEndpoint: global.consolidationEndpoint,
        consolidationApiKey: global.consolidationApiKey,
        consolidationTimeoutMs: global.consolidationTimeoutMs,
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
