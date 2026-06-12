import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/llm/lorebook_providers.dart';
import '../../../core/llm/memory_draft_planner.dart';
import '../../../core/llm/memory_injection_service.dart';
import '../../../core/models/memory_book.dart';
import '../../../core/state/memory_book_ops_provider.dart';
import '../../../core/state/memory_settings_provider.dart';
import '../../chat/chat_provider.dart';
import '../../chat/memory_draft_generator.dart';
import '../../settings/api_list_provider.dart';
import '../state/memory_active_drafts_provider.dart';

/// Controller for memory book operations, separating business logic from UI.
class MemoryBookController {
  final WidgetRef _ref;
  final String _sessionId;
  final String _charId;

  MemoryBook? _book;
  bool _loading = true;
  bool _isReindexing = false;
  final Map<String, bool> _generatingDrafts = {};
  final Map<String, DateTime> _genStartTimes = {};
  final Map<String, CancelToken> _cancelTokens = {};
  Timer? _genElapsedTimer;

  MemoryBookController(this._ref, this._sessionId, this._charId);

  MemoryBook? get book => _book;
  bool get loading => _loading;
  bool get isReindexing => _isReindexing;
  Map<String, bool> get generatingDrafts => Map.unmodifiable(_generatingDrafts);
  Map<String, DateTime> get genStartTimes => Map.unmodifiable(_genStartTimes);

  MemoryGlobalSettings get globalSettings =>
      _ref.read(memoryGlobalSettingsProvider);

  Future<void> load() async {
    _book = await _ref.read(memoryBookOpsProvider).ensureForSession(_sessionId);
    _loading = false;
  }

  Future<void> save() async {
    if (_book == null) return;
    await _ref.read(memoryBookOpsProvider).saveMemoryBook(_book!);
  }

  MemoryBookSettings globalSettingsAsBookSettings() {
    final g = globalSettings;
    return MemoryBookSettings(
      enabled: g.enabled,
      memoryMode: g.memoryMode,
      autoCreateEnabled: g.autoCreateEnabled,
      autoGenerateEnabled: g.autoGenerateEnabled,
      maxInjectedEntries: g.maxInjectedEntries,
      memoryExcerptingEnabled: g.memoryExcerptingEnabled,
      maxInjectedTokens: g.maxInjectedTokens,
      memoryBudgetPreset: g.memoryBudgetPreset,
      autoCreateInterval: g.autoCreateInterval,
      autoCreateLagMessages: g.autoCreateLagMessages,
      useDelayedAutomation: g.useDelayedAutomation,
      injectionTarget: g.injectionTarget,
      batchSize: g.batchSize,
      vectorSearchEnabled: g.vectorSearchEnabled,
      keyMatchMode: g.keyMatchMode,
      generationSource: g.generationSource,
      generationModel: g.generationModel,
      generationEndpoint: g.generationEndpoint,
      generationApiKey: g.generationApiKey,
      generationTemperature: g.generationTemperature,
      generationMaxTokens: g.generationMaxTokens,
      promptPreset: g.promptPreset,
      diversityAware: g.diversityAware,
      diversityPenalty: g.diversityPenalty,
      recencyBoost: g.recencyBoost,
      recencyHalfLifeDays: g.recencyHalfLifeDays,
      importanceBoost: g.importanceBoost,
      importanceWeight: g.importanceWeight,
      sourceWindowExclusion: g.sourceWindowExclusion,
      factualContinuityGuardEnabled: g.factualContinuityGuardEnabled,
      classifierEnabled: g.classifierEnabled,
      classifierSource: g.classifierSource,
      classifierModel: g.classifierModel,
      classifierEndpoint: g.classifierEndpoint,
      classifierApiKey: g.classifierApiKey,
      classifierTimeoutMs: g.classifierTimeoutMs,
      sidecarEnabled: g.sidecarEnabled,
      sidecarSource: g.sidecarSource,
      sidecarModel: g.sidecarModel,
      sidecarEndpoint: g.sidecarEndpoint,
      sidecarApiKey: g.sidecarApiKey,
      sidecarTimeoutMs: g.sidecarTimeoutMs,
      queryIncludeAssistant: g.queryIncludeAssistant,
      queryRecentTurns: g.queryRecentTurns,
      queryMaxChars: g.queryMaxChars,
    );
  }

  String get settingsSummary {
    if (_book == null) return '';
    final s = globalSettings;
    final mode = switch (s.memoryMode) {
      'balanced' => 'Balanced',
      'deep' => 'Deep',
      'legacy' => 'Legacy',
      _ => 'Fast',
    };
    final interval = s.autoCreateInterval;
    final autoCreate = s.autoCreateEnabled ? 'Auto ON' : 'Auto OFF';
    final autoGen = s.autoGenerateEnabled ? 'Auto-gen' : 'Manual';
    final delayed = s.useDelayedAutomation ? 'Delayed' : 'Immediate';
    final target = s.injectionTarget == 'macro' ? '{{memory}}' : 'Hard Block';
    final vectorThreshold = s.vectorThreshold.toStringAsFixed(2);
    final maxEntries = s.maxInjectedEntries;
    final memoryBudget = s.maxInjectedTokens == null
        ? 'Auto memory budget'
        : '${s.maxInjectedTokens} memory tokens';
    final batchSize = s.batchSize;
    final outTokens =
        (s.generationMaxTokens != null && s.generationMaxTokens! > 0)
        ? '${s.generationMaxTokens} out'
        : 'Auto out';
    return '$mode • $interval msgs • Batch $batchSize • $outTokens • $autoCreate • $autoGen • $delayed • $target • th=$vectorThreshold • $maxEntries entries • $memoryBudget';
  }

  String get searchModelLabel {
    final s = globalSettings;
    return s.generationModel.isNotEmpty
        ? s.generationModel
        : 'Current LLM model';
  }

  String get searchTypeLabel {
    final s = _book?.settings;
    if (s == null) return 'Vector';
    if (!s.vectorSearchEnabled) return 'Keys';
    if (s.keyMatchMode == 'both') return 'Vector + Keys';
    return 'Vector';
  }

  /// Scans chat messages and creates draft segments for uncovered messages.
  /// Returns a result message to display to the user.
  Future<String?> scanChat() async {
    if (_book == null) return null;
    final chatState = _ref.read(chatProvider(_charId));
    final session = chatState.value?.session;
    if (session == null) return null;

    final plan = MemoryDraftPlanner.plan(
      book: _book!,
      messages: session.messages,
      interval: globalSettings.autoCreateInterval,
      lagMessages: globalSettings.autoCreateLagMessages,
      source: 'scan_chat',
      nowMillis: DateTime.now().millisecondsSinceEpoch,
    );
    if (plan.stableMessageCount == 0) {
      return 'No stable messages to scan';
    }
    if (plan.eligibleMessageCount == 0) {
      return 'Waiting for ${globalSettings.autoCreateLagMessages} newer messages before creating a draft';
    }
    if (plan.uncoveredMessageCount == 0) {
      return 'All messages are already covered';
    }
    if (plan.drafts.isEmpty) {
      return 'Need more uncovered messages before creating a draft';
    }

    _book = _book!.copyWith(
      pendingDrafts: [..._book!.pendingDrafts, ...plan.drafts],
    );
    await save();
    return '${plan.drafts.length} drafts created';
  }

  void generateAllPending() {
    if (_book == null) return;
    final needsGen = _book!.pendingDrafts
        .where(
          (d) =>
              d.content.isEmpty &&
              (d.status == 'pending_generation' ||
                  d.status == 'needs_regeneration') &&
              _generatingDrafts[d.id] != true,
        )
        .toList();

    for (final draft in needsGen) {
      generateDraft(
        draft.id,
        onStart: () {},
        onComplete: () {},
        onError: (e) {},
      );
    }
  }

  /// Generates a draft. Callbacks are for UI updates.
  Future<void> generateDraft(
    String draftId, {
    required void Function() onStart,
    required void Function() onComplete,
    required void Function(String error) onError,
  }) async {
    if (_book == null || _generatingDrafts[draftId] == true) return;
    final chatState = _ref.read(chatProvider(_charId));
    if (chatState.value?.isGenerating == true) {
      onError(
        'Chat generation is active — wait for it to finish before generating a memory draft',
      );
      return;
    }
    final draftIndex = _book!.pendingDrafts.indexWhere((d) => d.id == draftId);
    if (draftIndex < 0) return;

    final session = chatState.value?.session;
    if (session == null) return;

    final draft = _book!.pendingDrafts[draftIndex];
    final draftMessages = session.messages
        .where((m) => draft.messageIds.contains(m.id))
        .toList();
    if (draftMessages.isEmpty) {
      onError('Messages not found for this draft');
      return;
    }

    final historyText = draftMessages
        .map((m) => '${m.role}: ${m.content}')
        .join('\n\n');
    final cancelToken = CancelToken();
    _cancelTokens[draftId] = cancelToken;

    _generatingDrafts[draftId] = true;
    _genStartTimes[draftId] = DateTime.now();
    _startGenElapsedTimer();
    _ref.read(memoryActiveDraftsProvider.notifier).markActive(_sessionId);
    onStart();

    try {
      final generator = MemoryDraftGenerator(_ref);
      final result = await generator.generate(
        draft: draft,
        settings: globalSettingsAsBookSettings(),
        historyText: historyText,
        cancelToken: cancelToken,
      );

      final updatedDrafts = [..._book!.pendingDrafts];
      updatedDrafts[draftIndex] = result;
      _book = _book!.copyWith(pendingDrafts: updatedDrafts);
      _generatingDrafts.remove(draftId);
      _genStartTimes.remove(draftId);
      _stopGenElapsedTimer();
      _ref.read(memoryActiveDraftsProvider.notifier).markInactive(_sessionId);
      await save();
      onComplete();
    } catch (e) {
      final updatedDrafts = [..._book!.pendingDrafts];
      updatedDrafts[draftIndex] = updatedDrafts[draftIndex].copyWith(
        status: 'needs_regeneration',
        error: e.toString(),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      _book = _book!.copyWith(pendingDrafts: updatedDrafts);
      _generatingDrafts.remove(draftId);
      _genStartTimes.remove(draftId);
      _stopGenElapsedTimer();
      _ref.read(memoryActiveDraftsProvider.notifier).markInactive(_sessionId);
      await save();
      onError(e.toString());
    } finally {
      _cancelTokens.remove(draftId);
    }
  }

  void cancelDraftGeneration(String draftId) {
    _cancelTokens[draftId]?.cancel();
    _generatingDrafts.remove(draftId);
    if (_generatingDrafts.isEmpty) {
      _ref.read(memoryActiveDraftsProvider.notifier).markInactive(_sessionId);
    }
  }

  Future<void> batchGenerate({
    required void Function() onStart,
    required void Function() onComplete,
    required void Function(String error) onError,
  }) async {
    if (_book == null) return;
    final needsGen = _book!.pendingDrafts
        .where(
          (d) =>
              d.content.isEmpty &&
              (d.status == 'pending_generation' ||
                  d.status == 'needs_regeneration') &&
              _generatingDrafts[d.id] != true,
        )
        .toList();
    final batchSize = globalSettings.batchSize;
    final toGenerate = needsGen.take(batchSize).toList();

    for (final draft in toGenerate) {
      await generateDraft(
        draft.id,
        onStart: onStart,
        onComplete: onComplete,
        onError: onError,
      );
    }
  }

  Future<void> approveDraft(String draftId) async {
    if (_book == null) return;
    final draftIndex = _book!.pendingDrafts.indexWhere((d) => d.id == draftId);
    if (draftIndex < 0) return;
    final draft = _book!.pendingDrafts[draftIndex];
    if (draft.content.isEmpty) return;

    final entry = MemoryEntry(
      id: draft.id.replaceAll('draft_', 'mem_'),
      title: draft.title,
      content: draft.content,
      keys: draft.keys,
      vectorSearch: draft.vectorSearch,
      messageIds: draft.messageIds,
      messageRange: draft.messageRange,
      status: 'active',
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

    _book = _book!.copyWith(
      entries: [..._book!.entries, entry],
      pendingDrafts: _book!.pendingDrafts
          .where((d) => d.id != draftId)
          .toList(),
    );
    await save();
    await _autoIndexEntry(entry);
  }

  Future<void> deleteDraft(String draftId) async {
    if (_book == null) return;
    _book = _book!.copyWith(
      pendingDrafts: _book!.pendingDrafts
          .where((d) => d.id != draftId)
          .toList(),
    );
    await save();
  }

  Future<void> deleteAllDrafts() async {
    if (_book == null) return;
    _book = _book!.copyWith(pendingDrafts: []);
    await save();
  }

  Future<void> deleteEntry(String entryId) async {
    if (_book == null) return;
    _book = _book!.copyWith(
      entries: _book!.entries.where((e) => e.id != entryId).toList(),
    );
    await save();
    await _ref.read(memoryBookOpsProvider).deleteEmbeddingEntry(entryId);
  }

  Future<MemoryGlobalSettings?> updateSettings(
    MemoryBookSettings newSettings,
    double vectorThreshold,
  ) async {
    final currentGlobal = globalSettings;
    final newGlobal = MemoryGlobalSettings(
      enabled: newSettings.enabled,
      memoryMode: newSettings.memoryMode,
      autoCreateEnabled: newSettings.autoCreateEnabled,
      autoGenerateEnabled: newSettings.autoGenerateEnabled,
      maxInjectedEntries: newSettings.maxInjectedEntries,
      memoryExcerptingEnabled: newSettings.memoryExcerptingEnabled,
      maxInjectedTokens: newSettings.maxInjectedTokens,
      memoryBudgetPreset: newSettings.memoryBudgetPreset,
      autoCreateInterval: newSettings.autoCreateInterval,
      autoCreateLagMessages: newSettings.autoCreateLagMessages,
      useDelayedAutomation: newSettings.useDelayedAutomation,
      injectionTarget: newSettings.injectionTarget,
      batchSize: newSettings.batchSize,
      parallelJobs: currentGlobal.parallelJobs,
      vectorSearchEnabled: newSettings.vectorSearchEnabled,
      vectorThreshold: vectorThreshold,
      keyMatchMode: newSettings.keyMatchMode,
      generationSource: newSettings.generationSource,
      generationModel: newSettings.generationModel,
      generationUseCurrentModelOverride:
          currentGlobal.generationUseCurrentModelOverride,
      generationEndpoint: newSettings.generationEndpoint,
      generationApiKey: newSettings.generationApiKey,
      generationTemperature: newSettings.generationTemperature,
      generationMaxTokens: newSettings.generationMaxTokens,
      promptPreset: newSettings.promptPreset,
      diversityAware: newSettings.diversityAware,
      diversityPenalty: newSettings.diversityPenalty,
      recencyBoost: newSettings.recencyBoost,
      recencyHalfLifeDays: newSettings.recencyHalfLifeDays,
      importanceBoost: newSettings.importanceBoost,
      importanceWeight: newSettings.importanceWeight,
      sourceWindowExclusion: newSettings.sourceWindowExclusion,
      factualContinuityGuardEnabled: newSettings.factualContinuityGuardEnabled,
      classifierEnabled: newSettings.classifierEnabled,
      classifierSource: newSettings.classifierSource,
      classifierModel: newSettings.classifierModel,
      classifierEndpoint: newSettings.classifierEndpoint,
      classifierApiKey: newSettings.classifierApiKey,
      classifierTimeoutMs: newSettings.classifierTimeoutMs,
      sidecarEnabled: newSettings.sidecarEnabled,
      sidecarSource: newSettings.sidecarSource,
      sidecarModel: newSettings.sidecarModel,
      sidecarEndpoint: newSettings.sidecarEndpoint,
      sidecarApiKey: newSettings.sidecarApiKey,
      sidecarTimeoutMs: newSettings.sidecarTimeoutMs,
      queryIncludeAssistant: newSettings.queryIncludeAssistant,
      queryRecentTurns: newSettings.queryRecentTurns,
      queryMaxChars: newSettings.queryMaxChars,
      customPrompts: currentGlobal.customPrompts,
    );
    await _ref.read(memoryGlobalSettingsProvider.notifier).save(newGlobal);
    if (_book != null) {
      _book = _book!.copyWith(settings: newSettings);
      await _ref
          .read(memoryBookOpsProvider)
          .updateSettings(_sessionId, newSettings);
    }
    return newGlobal;
  }

  /// Reindexes all memory entries. Returns a result message.
  Future<String?> reindexAll() async {
    if (_book == null) return null;
    await _ref.read(apiListProvider.future);
    final config = _ref.read(embeddingConfigProvider);
    if (config.endpoint.isEmpty) {
      return 'Set up embedding API in Embedding Settings first';
    }

    _isReindexing = true;
    try {
      final service = _ref.read(memoryEmbeddingServiceProvider);
      final result = await service.reindexAll(
        _book!,
        charId: _charId,
        sessionId: _sessionId,
        config: config,
        embeddingTarget: globalSettings.vectorSearchEnabled
            ? 'content'
            : 'content',
      );
      return 'Indexed: ${result.indexed}, Skipped: ${result.skipped}, Failed: ${result.failed}';
    } catch (e) {
      return 'Reindex failed: $e';
    } finally {
      _isReindexing = false;
    }
  }

  Future<void> _autoIndexEntry(MemoryEntry entry) async {
    if (!globalSettings.vectorSearchEnabled) return;
    if (entry.content.trim().isEmpty) return;
    final config = _ref.read(embeddingConfigProvider);
    if (config.endpoint.isEmpty) return;
    try {
      await _ref
          .read(memoryEmbeddingServiceProvider)
          .indexMemoryEntry(
            entry,
            charId: _charId,
            sessionId: _sessionId,
            config: config,
          );
    } catch (_) {}
  }

  Future<void> deleteAllMemoryIndexes() async {
    await _ref.read(memoryEmbeddingServiceProvider).deleteAllMemoryIndexes();
  }

  Future<MemoryEntry?> editEntry(MemoryEntry entry, MemoryEntry result) async {
    if (_book == null) return null;
    final entries = [..._book!.entries];
    final idx = entries.indexWhere((e) => e.id == entry.id);
    if (idx >= 0) entries[idx] = result;
    _book = _book!.copyWith(entries: entries);
    await save();
    await _ref.read(memoryBookOpsProvider).deleteEmbeddingEntry(result.id);
    await _autoIndexEntry(result);
    return result;
  }

  Future<MemoryEntry?> addEntry(MemoryEntry result) async {
    if (_book == null) return null;
    _book = _book!.copyWith(entries: [..._book!.entries, result]);
    await save();
    await _autoIndexEntry(result);
    return result;
  }

  Future<void> editDraft(MemoryDraft draft, MemoryEntry result) async {
    if (_book == null) return;
    final drafts = [..._book!.pendingDrafts];
    final idx = drafts.indexWhere((d) => d.id == draft.id);
    if (idx >= 0) {
      drafts[idx] = drafts[idx].copyWith(
        title: result.title,
        content: result.content,
        keys: result.keys,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
    }
    _book = _book!.copyWith(pendingDrafts: drafts);
    await save();
  }

  Future<void> cycleSearchType() async {
    final s = globalSettings;
    String nextMode;
    bool nextVector;
    if (!s.vectorSearchEnabled) {
      nextVector = true;
      nextMode = 'glaze';
    } else if (s.keyMatchMode == 'glaze') {
      nextVector = true;
      nextMode = 'both';
    } else if (s.keyMatchMode == 'both') {
      nextVector = false;
      nextMode = 'plain';
    } else {
      nextVector = false;
      nextMode = 'plain';
    }
    await _ref
        .read(memoryGlobalSettingsProvider.notifier)
        .save(
          s.copyWith(vectorSearchEnabled: nextVector, keyMatchMode: nextMode),
        );
  }

  void _startGenElapsedTimer() {
    _genElapsedTimer ??= Timer.periodic(
      const Duration(milliseconds: 200),
      (_) {},
    );
  }

  void _stopGenElapsedTimer() {
    if (_generatingDrafts.isEmpty) {
      _genElapsedTimer?.cancel();
      _genElapsedTimer = null;
    }
  }

  void dispose() {
    _genElapsedTimer?.cancel();
  }

  /// Updates the book state (called from UI when state changes).
  void updateBook(MemoryBook newBook) {
    _book = newBook;
  }

  List<MemoryDraft> get draftsNeedingGeneration {
    if (_book == null) return [];
    return _book!.pendingDrafts
        .where(
          (d) =>
              d.content.isEmpty &&
              (d.status == 'pending_generation' ||
                  d.status == 'needs_regeneration') &&
              _generatingDrafts[d.id] != true,
        )
        .toList();
  }

  bool get isGenerating => _generatingDrafts.values.any((v) => v);

  int get activeEntryCount =>
      _book?.entries.where((e) => e.status == 'active').length ?? 0;
  int get needsRebuildCount =>
      _book?.entries.where((e) => e.status == 'needs_rebuild').length ?? 0;
}
