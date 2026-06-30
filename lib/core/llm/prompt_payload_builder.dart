import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../../features/settings/api_list_provider.dart';
import '../../shared/widgets/glaze_toast.dart' show GlazeToast, ToastPosition;
import '../models/api_config.dart';
import '../models/character.dart';
import '../models/chat_message.dart';
import '../utils/cast_helpers.dart';
import '../models/lorebook.dart';
import '../models/memory_book.dart';
import '../models/persona.dart';
import '../models/tracker.dart';
import '../models/preset.dart';
import '../state/active_selection_provider.dart';
import '../state/db_provider.dart';
import '../state/global_regex_provider.dart';
import '../state/lorebook_provider.dart';
import '../state/memory_settings_provider.dart';
import 'embedding_types.dart';
import 'lorebook_providers.dart';
import 'memory_injection_service.dart';
import 'message_recall_service.dart';
import 'memory_selector.dart';
import '../../features/extensions/services/ext_blocks_prompt_injection.dart';
import '../../features/extensions/services/runtime_prompt_injection_service.dart';
import 'prompt_builder.dart';
import 'prompt_inputs.dart';
import 'prompt_inputs_collector.dart';
import 'summary_service.dart';

class PromptPayloadBuilder {
  final Ref _ref;
  late final PromptInputsCollector _inputsCollector = PromptInputsCollector(
    _ref,
  );

  PromptPayloadBuilder(this._ref);

  /// Collects raw inputs from DB/providers for isolate-based processing.
  /// Fast path: DB reads only, no memory injection or vector search.
  /// Delegates to [PromptInputsCollector].
  Future<PromptInputs> collectInputs({
    required String charId,
    required ChatSession? session,
    String? guidanceText,
  }) => _inputsCollector.collectInputs(
    charId: charId,
    session: session,
    guidanceText: guidanceText,
  );

  Future<PromptPayload> buildFromSession({
    required String charId,
    required ChatSession? session,
    String? guidanceText,
    bool skipVectorSearch = false,
    bool skipMemoryLlmSidecars = false,
    bool Function()? shouldAbort,
    CancelToken? cancelToken,
  }) async {
    void throwIfAborted() {
      if (shouldAbort?.call() == true) {
        throw const _GenerationAbortedException();
      }
    }

    throwIfAborted();
    final charRepo = _ref.read(characterRepoProvider);
    final presetRepo = _ref.read(presetRepoProvider);
    final personaRepo = _ref.read(personaRepoProvider);
    final lorebookRepo = _ref.read(lorebookRepoProvider);

    final character = await charRepo.getById(charId);
    throwIfAborted();
    if (character == null) throw StateError('Character not found: $charId');

    await _ref.read(apiListProvider.future);
    throwIfAborted();
    final chatApi = _ref.read(activeApiConfigProvider);
    if (chatApi == null || chatApi.mode == 'embedding') {
      throw StateError('No chat API config available');
    }

    final activePresetId = _ref.read(activePresetIdProvider);
    final presets = await presetRepo.getAll();
    throwIfAborted();
    final preset = activePresetId != null
        ? presets.where((p) => p.id == activePresetId).firstOrNull
        : (presets.isNotEmpty ? presets.first : null);

    final personas = await personaRepo.getAll();
    throwIfAborted();
    final connections = _ref.read(personaConnectionsProvider);
    final activePersonaId = _ref.read(activePersonaIdProvider);
    final sessionId = session?.id;

    final persona = getEffectivePersona(
      personas,
      charId,
      sessionId,
      activePersonaId,
      connections,
    );

    final lorebooks = await lorebookRepo.getAll();
    throwIfAborted();
    final lorebookSettings = _ref.read(lorebookSettingsProvider);
    final lorebookActivations = _ref.read(lorebookActivationsProvider);

    String? summaryContent;
    Map<String, dynamic> memoryCoverage = {};
    List<TriggeredEntry> triggeredMemories = [];
    List<RuntimePromptBlock> runtimePromptBlocks = const [];
    List<ChatMessage> history = session?.messages ?? [];
    Map<String, String> sessionVars = session?.sessionVars ?? {};
    List<LorebookEntry> vectorEntries = [];
    MemorySelection? memorySelection;
    var memoryInjectionTarget = 'hard_block';
    // NEW (patch #3): raw-message recall content for <recalled_messages>.
    String? recalledMessagesContent;
    final g = _ref.read(memoryGlobalSettingsProvider);
    var memorySettings = MemoryBookSettings(
      memoryExcerptingEnabled: g.memoryExcerptingEnabled,
      memoryPackingMode: g.memoryPackingMode,
      memoryExcerptTokensPerChunk: g.memoryExcerptTokensPerChunk,
      memoryExcerptChunksPerEntry: g.memoryExcerptChunksPerEntry,
      chunkFirstTopEntries: g.chunkFirstTopEntries,
      chunkFirstTopChunks: g.chunkFirstTopChunks,
    );

    if (session != null) {
      history = await _ref
          .read(extBlocksPromptInjectionProvider)
          .injectIntoHistory(sessionId: session.id, messages: history);
      throwIfAborted();
      runtimePromptBlocks = _ref
          .read(runtimePromptInjectionProvider.notifier)
          .bySession(session.id)
          .map(
            (block) => RuntimePromptBlock(
              id: block.id,
              content: block.content,
              depth: block.depth,
              role: block.role,
            ),
          )
          .toList(growable: false);

      final summaryService = _ref.read(summaryServiceProvider);
      summaryContent = await summaryService.getSummary(session.id);
      throwIfAborted();

      final memoryService = _ref.read(memoryInjectionServiceProvider);
      final embeddingConfig = _ref.read(embeddingConfigProvider);
      final currentText = session.messages.lastOrNull?.content ?? '';

      // Run memory candidate collection and lorebook vector search in
      // parallel. They hit different data sources and are independent;
      // sequential execution doubles wall-clock time when the embedding
      // endpoint is slow. The final memory refilter against the visible
      // window happens later inside buildPrompt (see
      // docs/INVARIANTS.md §5.5).
      final lorebookFuture = (!skipVectorSearch)
          ? _runVectorSearch(
              session.messages,
              currentText,
              character.world,
              character,
              chatId: session.id,
              cancelToken: cancelToken,
            ).timeout(const Duration(seconds: 15))
          : Future<List<LorebookEntry>>.value(const []);

      final memoryFuture = memoryService.buildCandidatesWithDiagnostics(
        sessionId: session.id,
        history: session.messages,
        currentText: currentText,
        embeddingConfig: embeddingConfig,
        shouldAbort: shouldAbort,
        cancelToken: cancelToken,
        contextBudgetTokens: chatApi.contextSize,
        skipLlmSidecars: skipMemoryLlmSidecars,
      );

      // NEW (patch #3): raw-message recall — cosine search over
      // `sourceType='chat_message'` chunks embedded by
      // ChatMessageEmbeddingService after each generation. Lossless
      // backstop for the lossy MemoryBook compression. Empty / no-op when
      // embeddingConfig.endpoint is empty or no chunks exist yet.
      // See docs/plans/PLAN_MEMORY_CONTINUITY.md §1.
      final recallFuture = _ref
          .read(messageRecallServiceProvider)
          .recall(
            sessionId: session.id,
            currentText: currentText,
            config: embeddingConfig,
            cancelToken: cancelToken,
            shouldAbort: shouldAbort,
          )
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => const MessageRecallResult(),
          );

      throwIfAborted();
      final results = await Future.wait([
        memoryFuture,
        lorebookFuture,
        recallFuture,
      ]);
      throwIfAborted();
      final memoryResult = results[0] as MemoryCandidateBuildResult;
      memorySelection = memoryResult.selection;
      memorySettings = memoryResult.settings ?? memorySettings;
      memoryInjectionTarget = memorySettings.injectionTarget == 'macro'
          ? 'macro'
          : 'hard_block';
      vectorEntries = results[1] as List<LorebookEntry>;
      final recallResult = results[2] as MessageRecallResult;
      if (recallResult.matches.isNotEmpty) {
        final block = StringBuffer();
        block.writeln('<recalled_messages>');
        block.writeln(
          'Semantically relevant raw message chunks from earlier in this chat. '
          'Do not explicitly reference "remembering" these — use them as ground '
          'truth context.',
        );
        for (final match in recallResult.matches) {
          block.writeln('---');
          block.writeln(match.text);
        }
        block.writeln('</recalled_messages>');
        recalledMessagesContent = block.toString();
      }
      throwIfAborted();
      memoryCoverage = {
        'entryIds': memorySelection.entries.map((e) => e.id).toList(),
        'needsRebuild': false,
        'stale': false,
        'injected': false,
        'candidatesTotal': memorySelection.allScores.length,
        'excludedBySourceWindow': memorySelection.excludedBySourceWindow,
        'budgetTokens': memorySelection.budgetTokens,
        'budgetTrimmed': memorySelection.budgetTrimmed,
        'packingMode': memorySettings.memoryPackingMode,
        'excerptTokensPerChunk': memorySettings.memoryExcerptTokensPerChunk,
        'excerptChunksPerEntry': memorySettings.memoryExcerptChunksPerEntry,
        'chunkFirstTopEntries': memorySettings.chunkFirstTopEntries,
        'chunkFirstTopChunks': memorySettings.chunkFirstTopChunks,
        if (memoryResult.diagnostics != null)
          'diagnostics': memoryResult.diagnostics!.toJson(),
      };
      if (memorySelection.entries.isNotEmpty) {
        triggeredMemories = memorySelection.entries
            .map(
              (e) => TriggeredEntry(
                id: e.id,
                name: e.title.isNotEmpty ? e.title : e.id,
                source: 'memory',
              ),
            )
            .toList();
      }
      // NEW (patch #4 follow-up): chatSummaryFingerprint analog for
      // prompt cache invalidation. Hash the canonical serialization of
      // the selected memory entries (id + content) so the next generation
      // can detect "memory changed since last turn" and invalidate
      // Anthropic/DeepSeek prompt cache. Note: this is a simpler hash than
      // the isolate-path's `computeHash(memoryContent)` because here we
      // do not have the compiled memory injection content (it is built
      // later in the prompt builder from the excerpt selection). The
      // id+content hash is sufficient for cache invalidation — any
      // change to the selected entries' content (append-only newFacts,
      // user edits, agent writes) changes the fingerprint.
      // See docs/plans/PLAN_MEMORY_CONTINUITY.md §2.3.
      final fingerprintBase = memorySelection.entries.isNotEmpty
          ? memorySelection.entries
                .map((e) => '${e.id}:${e.content}')
                .join('||')
          : '';
      final memoryInjectionFingerprint = fingerprintBase.isNotEmpty
          ? computeHash(fingerprintBase)
          : '';
      memoryCoverage['memoryInjectionFingerprint'] = memoryInjectionFingerprint;
    }

    // Load committed Studio Ledger canon state from tracker_rows and compile
    // the <studio_session_state> injection block. Loaded whenever Studio Ledger
    // is enabled, regardless of memoryMode. Falls back to null on any error.
    // See docs/plans/PLAN_STUDIO_LEDGER_MEMORY.md §Prompt Injection.
    String? studioSessionStateContent;
    if (sessionId != null) {
      try {
        final ledgerTrackers = await _loadEffectiveLedgerTrackers(sessionId);
        if (ledgerTrackers.isNotEmpty) {
          studioSessionStateContent = _compileStudioSessionState(
            ledgerTrackers,
            sessionId,
            latestUserText: _latestUserText(history),
          );
        }
      } catch (e) {
        debugPrint('[PromptBuilder] studio_session_state load failed: $e');
      }
    }

    // Load {{arc}} macro content from Studio Canon arc:* tracker rows.
    // Falls back to null when Studio Ledger has not written any arc state yet
    // (e.g. memoryMode=fast or first turn). Does NOT use the old
    // memory_consolidation_rows — those are disconnected from Studio Canon.
    // See docs/plans/PLAN_STUDIO_LEDGER_MEMORY.md §{{arc}} Macro.
    String? arcContent;
    String? entitiesContent;
    if (memorySettings.memoryMode != 'fast' && sessionId != null) {
      try {
        final allLedger = await _loadEffectiveLedgerTrackers(sessionId);
        arcContent = _buildArcContent(
          allLedger,
          latestUserText: _latestUserText(history),
        );
      } catch (_) {}
      try {
        final entities = await _ref
            .read(memoryEntityRepoProvider)
            .getBySessionId(sessionId);
        if (entities.isNotEmpty) {
          final active = entities.where((e) => e.status == 'active').take(20);
          entitiesContent = active
              .map(
                (e) =>
                    '- ${e.name} (${e.entityType})'
                    '${e.facts.isNotEmpty ? ": ${e.facts.join("; ")}" : ""}',
              )
              .join('\n');
        }
      } catch (_) {}
    }

    return PromptPayload(
      character: character,
      persona: persona,
      preset: preset,
      history: history,
      sessionId: sessionId,
      apiConfig: chatApi,
      sessionVars: sessionVars,
      globalVars: _ref.read(globalVarsProvider),
      lorebooks: lorebooks,
      lorebookSettings: lorebookSettings,
      lorebookActivations: lorebookActivations,
      vectorEntries: vectorEntries,
      summaryContent: summaryContent,
      memoryContent: null,
      memoryMacroContent: null,
      memoryInjectionTarget: memoryInjectionTarget,
      memoryCoverage: memoryCoverage,
      guidanceText: guidanceText,
      authorsNote: session?.authorsNote,
      characterDepthPrompt: character.depthPrompt,
      characterDepthPromptDepth: character.depthPromptDepth,
      characterDepthPromptRole: character.depthPromptRole,
      globalRegexes: _ref.read(globalRegexProvider).value ?? [],
      triggeredMemories: triggeredMemories,
      runtimePromptBlocks: runtimePromptBlocks,
      memorySelection: memorySelection,
      memoryExcerptingEnabled: memorySettings.memoryExcerptingEnabled,
      memoryPackingMode: memorySettings.memoryPackingMode,
      memoryExcerptTokensPerChunk: memorySettings.memoryExcerptTokensPerChunk,
      memoryExcerptChunksPerEntry: memorySettings.memoryExcerptChunksPerEntry,
      chunkFirstTopEntries: memorySettings.chunkFirstTopEntries,
      chunkFirstTopChunks: memorySettings.chunkFirstTopChunks,
      arcContent: arcContent,
      entitiesContent: entitiesContent,
      studioSessionStateContent: studioSessionStateContent,
      recalledMessagesContent: recalledMessagesContent,
    );
  }

  Future<PromptPayload> buildFromPreFetched({
    required String charId,
    required ChatSession? session,
    required Character character,
    required ApiConfig chatApi,
    required Preset? preset,
    required Persona? persona,
    required List<Lorebook> lorebooks,
    String? summaryContent,
    String? memoryContent,
    String? memoryMacroContent,
    String memoryInjectionTarget = 'hard_block',
    Map<String, dynamic> memoryCoverage = const {},
    List<TriggeredEntry> triggeredMemories = const [],
    String? guidanceText,
    bool skipVectorSearch = true,
    List<RuntimePromptBlock> runtimePromptBlocks = const [],
    String? recalledMessagesContent,
  }) async {
    final lorebookSettings = _ref.read(lorebookSettingsProvider);
    final lorebookActivations = _ref.read(lorebookActivationsProvider);

    List<LorebookEntry> vectorEntries = [];
    List<ChatMessage> history = session?.messages ?? [];
    if (session != null) {
      history = await _ref
          .read(extBlocksPromptInjectionProvider)
          .injectIntoHistory(sessionId: session.id, messages: history);
    }
    if (!skipVectorSearch && session != null) {
      vectorEntries = await _runVectorSearch(
        history,
        history.lastOrNull?.content ?? '',
        character.world,
        character,
      );
    }

    final memSettings = _ref.read(memoryGlobalSettingsProvider);
    String? studioSessionStateContent;
    if (session != null) {
      try {
        final ledgerTrackers = await _loadEffectiveLedgerTrackers(session.id);
        if (ledgerTrackers.isNotEmpty) {
          studioSessionStateContent = _compileStudioSessionState(
            ledgerTrackers,
            session.id,
            latestUserText: _latestUserText(history),
          );
        }
      } catch (e) {
        debugPrint('[PromptBuilder] studio_session_state load failed: $e');
      }
    }
    String? arcContent;
    String? entitiesContent;
    if (memSettings.memoryMode != 'fast' && session != null) {
      try {
        final allLedger = await _loadEffectiveLedgerTrackers(session.id);
        arcContent = _buildArcContent(
          allLedger,
          latestUserText: _latestUserText(history),
        );
      } catch (_) {}
      try {
        final entities = await _ref
            .read(memoryEntityRepoProvider)
            .getBySessionId(session.id);
        if (entities.isNotEmpty) {
          final active = entities.where((e) => e.status == 'active').take(20);
          entitiesContent = active
              .map(
                (e) =>
                    '- ${e.name} (${e.entityType})'
                    '${e.facts.isNotEmpty ? ": ${e.facts.join("; ")}" : ""}',
              )
              .join('\n');
        }
      } catch (_) {}
    }

    return PromptPayload(
      character: character,
      persona: persona,
      preset: preset,
      history: history,
      sessionId: session?.id,
      apiConfig: chatApi,
      sessionVars: session?.sessionVars ?? {},
      globalVars: _ref.read(globalVarsProvider),
      lorebooks: lorebooks,
      lorebookSettings: lorebookSettings,
      lorebookActivations: lorebookActivations,
      vectorEntries: vectorEntries,
      summaryContent: summaryContent,
      memoryContent: memoryContent,
      memoryMacroContent: memoryMacroContent,
      memoryInjectionTarget: memoryInjectionTarget,
      memoryCoverage: memoryCoverage,
      guidanceText: guidanceText,
      authorsNote: session?.authorsNote,
      characterDepthPrompt: character.depthPrompt,
      characterDepthPromptDepth: character.depthPromptDepth,
      characterDepthPromptRole: character.depthPromptRole,
      globalRegexes: _ref.read(globalRegexProvider).value ?? [],
      triggeredMemories: triggeredMemories,
      runtimePromptBlocks: runtimePromptBlocks,
      memoryExcerptingEnabled: memSettings.memoryExcerptingEnabled,
      memoryPackingMode: memSettings.memoryPackingMode,
      memoryExcerptTokensPerChunk: memSettings.memoryExcerptTokensPerChunk,
      memoryExcerptChunksPerEntry: memSettings.memoryExcerptChunksPerEntry,
      chunkFirstTopEntries: memSettings.chunkFirstTopEntries,
      chunkFirstTopChunks: memSettings.chunkFirstTopChunks,
      arcContent: arcContent,
      entitiesContent: entitiesContent,
      studioSessionStateContent: studioSessionStateContent,
      recalledMessagesContent: recalledMessagesContent,
    );
  }

  Future<List<LorebookEntry>> _runVectorSearch(
    List<ChatMessage> history,
    String currentText,
    String? charWorld,
    Character? character, {
    String? chatId,
    CancelToken? cancelToken,
  }) async {
    final settings = _ref.read(lorebookSettingsProvider);
    if (settings.searchType == 'keyword') return [];

    final config = _ref.read(embeddingConfigProvider);
    if (config.endpoint.isEmpty) return [];

    final lorebooks = await _ref.read(lorebookRepoProvider).getAll();
    if (lorebooks.isEmpty) return [];

    try {
      final searchService = _ref.read(lorebookVectorSearchProvider);
      final visibleHistory = history
          .where((m) => !m.isHidden && !m.isTyping)
          .toList();
      final searchHistory = visibleHistory
          .map((m) => ChatMessageForSearch(role: m.role, content: m.content))
          .toList();
      final activations = _ref.read(lorebookActivationsProvider);
      final overrideTopK = settings.maxInjectedEntries;
      final results = await searchService.search(
        searchHistory,
        currentText,
        lorebooks,
        settings,
        config,
        charWorld: charWorld,
        character: character,
        activations: activations,
        chatId: chatId,
        overrideTopK: overrideTopK,
        cancelToken: cancelToken,
      );

      // Key by "lorebookId_entryId" to avoid collisions between lorebooks
      // whose entries share the same numeric id.
      final entryMap = <String, LorebookEntry>{};
      for (final lb in lorebooks) {
        for (final entry in lb.entries) {
          entryMap['${lb.id}_${entry.id}'] = entry;
        }
      }
      return results
          .where((r) => entryMap.containsKey('${r.lorebookId}_${r.entryId}'))
          .map((r) => entryMap['${r.lorebookId}_${r.entryId}']!.copyWith())
          .toList();
    } catch (e, st) {
      if (cancelToken?.isCancelled == true ||
          (e is DioException && CancelToken.isCancel(e))) {
        return [];
      }
      debugPrint('VECTOR SEARCH: failed: $e\n$st');
      GlazeToast.showWithoutContext(
        'Vector search failed — try reindexing embeddings',
        duration: 4000,
        position: ToastPosition.top,
        isError: true,
      );
      return [];
    }
  }

  Future<List<Tracker>> _loadEffectiveLedgerTrackers(String sessionId) async {
    final trackerRepo = _ref.read(trackerRepoProvider);
    final snapshot = await _ref
        .read(trackerSnapshotRepoProvider)
        .getLatestCommitted(sessionId);
    final liveLedger = await trackerRepo.getBySessionAndScope(
      sessionId,
      'ledger',
    );

    if (snapshot == null) return liveLedger;

    final byName = <String, Tracker>{
      for (final tracker in snapshot.trackers)
        if (tracker.scope == 'ledger') tracker.name: tracker,
    };

    // Manual overrides/locks are user-owned and can be newer than the latest
    // committed model snapshot. Keep them authoritative without admitting
    // uncommitted model-written rows from tracker_rows.
    for (final tracker in liveLedger) {
      if (tracker.name.startsWith('canon_override:') ||
          tracker.name.startsWith('canon_lock:')) {
        byName[tracker.name] = tracker;
      }
    }

    return byName.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }
}

/// Extracts the latest user-role message text from [history] for entity
/// mention detection. Returns empty string when history has no user message.
String _latestUserText(List<ChatMessage> history) {
  for (final m in history.reversed) {
    if (m.role == 'user' && !m.isHidden && !m.isTyping) {
      return m.content;
    }
  }
  return '';
}

/// Builds compact `<arc_state>` block for the `{{arc}}` macro from Studio
/// Canon `arc:*` tracker rows.
///
/// Replaces the old consolidation-summary approach with deterministic arc
/// state derived from ledger tracker rows. Selection rules (plan §{{arc}}):
///   - Completed arcs with do_not_reopen=true are always included (suppress
///     card-baseline regression).
///   - Active/seeded arcs whose entities/topics appear in [latestUserText]
///     are included.
///   - Omit unrelated completed arcs without do_not_reopen.
///   - Returns null when no arc rows exist.
String? _buildArcContent(
  List<Tracker> ledgerRows, {
  String latestUserText = '',
}) {
  // Collect arc:id.field → value
  final arcFields = <String, Map<String, String>>{};
  for (final t in ledgerRows) {
    if (!t.name.startsWith('arc:')) continue;
    if (t.value.isEmpty) continue;
    final rest = t.name.substring('arc:'.length);
    final dotIdx = rest.indexOf('.');
    if (dotIdx < 0) continue;
    final arcId = rest.substring(0, dotIdx);
    final field = rest.substring(dotIdx + 1);
    arcFields.putIfAbsent(arcId, () => {})[field] = t.value;
  }
  if (arcFields.isEmpty) return null;

  final lowerContext = latestUserText.toLowerCase();

  final completed = <String>[];
  final active = <String>[];

  for (final arcId in arcFields.keys) {
    final f = arcFields[arcId]!;
    final status = f['status'] ?? '';
    final doNotReopen = f['do_not_reopen']?.toLowerCase() == 'true';
    final summary = f['summary'] ?? '';
    final title = f['title'] ?? arcId;

    if (status == 'completed' ||
        status == 'failed' ||
        status == 'abandoned' ||
        status == 'superseded') {
      // Include completed arcs with do_not_reopen OR if their title/summary
      // is mentioned in the latest user message.
      final mentioned =
          lowerContext.contains(title.toLowerCase()) ||
          (summary.isNotEmpty &&
              summary
                  .split(' ')
                  .take(5)
                  .any(
                    (w) =>
                        w.length > 3 && lowerContext.contains(w.toLowerCase()),
                  ));
      if (doNotReopen || mentioned) {
        completed.add(arcId);
      }
    } else {
      // active/seeded/paused — include if entities/title mentioned or
      // no filter needed (all active arcs are relevant for near-term)
      active.add(arcId);
    }
  }

  if (completed.isEmpty && active.isEmpty) return null;

  final buf = StringBuffer();
  buf.writeln('<arc_state>');
  buf.writeln(
    'Session canon overrides character-card baseline when conflicting.',
  );

  if (completed.isNotEmpty) {
    buf.writeln('\nCompleted/resolved:');
    for (final id in completed..sort()) {
      final f = arcFields[id]!;
      final title = f['title'] ?? id;
      final summary = f['summary'] ?? '';
      final doNotReopen = f['do_not_reopen']?.toLowerCase() == 'true';
      final cardOverride = f['card_override'] ?? '';
      buf.write('- $title is completed.');
      if (summary.isNotEmpty) buf.write(' $summary');
      if (doNotReopen) {
        buf.write(
          ' Treat card hooks about this as backstory, not an unresolved conflict.',
        );
      }
      if (cardOverride.isNotEmpty) buf.write(' $cardOverride');
      buf.writeln();
    }
  }

  if (active.isNotEmpty) {
    buf.writeln('\nActive:');
    for (final id in active..sort()) {
      final f = arcFields[id]!;
      final title = f['title'] ?? id;
      final summary = f['summary'] ?? '';
      buf.write('- $title');
      if (summary.isNotEmpty) buf.write(': $summary');
      buf.writeln();
    }
  }

  buf.write('</arc_state>');
  return buf.toString().trim();
}

/// Test-accessible alias for [_compileStudioSessionState].
/// Only use in test code — production code calls [_compileStudioSessionState]
/// directly inside [PromptPayloadBuilder.buildFromSession].
// ignore: non_constant_identifier_names
String? kCompileStudioSessionStateForTest(
  List<Tracker> trackers,
  String sessionId, {
  String latestUserText = '',
}) => _compileStudioSessionState(
  trackers,
  sessionId,
  latestUserText: latestUserText,
);

/// Compile ledger tracker rows into a `<studio_session_state>` system block.
///
/// Groups rows by namespace (npc, relationship, arc, world, scene) and
/// applies canon_override:* values when present. Locked rows without an
/// override are emitted as-is. Empty or diagnostic rows are skipped.
///
/// Mentioned-entity detection (plan §Prompt Injection Test 8):
///   - Always include npc/rel/arc rows for entities whose name appears in
///     [latestUserText] or in recent context.
///   - Always include arcs with do_not_reopen=true (card-baseline guard).
///   - Always include world/scene rows (compact; included unconditionally).
///   - If no [latestUserText] is provided, all rows are included (same as
///     original behaviour).
///
/// Present/absent section (plan §Present Characters + Test 21):
///   - scene.present_entities → explicit "Present now" list.
///   - scene.absent_backstory_entities → explicit "Absent/backstory" list.
///   - Prompt instructs model not to give dialogue/actions to absent chars.
///
/// Plan §Prompt Injection — minimum injected block:
/// ```xml
/// <studio_session_state>
/// These are established facts from this chat…
/// Lucyna Kushinada:
/// - relationship_to_user: fragile alliance
/// …
/// </studio_session_state>
/// ```
String? _compileStudioSessionState(
  List<Tracker> trackers,
  String sessionId, {
  String latestUserText = '',
}) {
  // Build a name→value map with override support. Keys:
  //   npc:Name.field, relationship:A:B.field, arc:id.field, world:key, scene.key
  // Override keys: canon_override:npc:Name.field → beats ledger value.
  final overrides = <String, String>{};
  final regular = <String, String>{};

  for (final t in trackers) {
    if (t.name.startsWith('canon_override:')) {
      final key = t.name.substring('canon_override:'.length);
      overrides[key] = t.value;
    } else if (!t.name.startsWith('canon_lock:') &&
        !t.name.startsWith('_ledger:')) {
      regular[t.name] = t.value;
    }
  }

  if (regular.isEmpty && overrides.isEmpty) return null;

  // Apply overrides.
  for (final entry in overrides.entries) {
    regular[entry.key] = entry.value;
  }

  // Group by namespace.
  final npcMap = <String, Map<String, String>>{};
  final relMap = <String, Map<String, String>>{};
  final arcMap = <String, Map<String, String>>{};
  final worldLines = <String>[];
  // scene.present_entities and scene.absent_backstory_entities get special
  // treatment; remaining scene.* go to generic sceneLines.
  String? presentEntities;
  String? absentEntities;
  final sceneLines = <String>[];

  for (final entry in regular.entries) {
    final k = entry.key;
    final v = entry.value;
    if (v.isEmpty) continue;

    if (k.startsWith('npc:')) {
      final rest = k.substring('npc:'.length);
      final dotIdx = rest.indexOf('.');
      if (dotIdx < 0) continue;
      final name = rest.substring(0, dotIdx);
      final field = rest.substring(dotIdx + 1);
      npcMap.putIfAbsent(name, () => {})[field] = v;
    } else if (k.startsWith('relationship:')) {
      final rest = k.substring('relationship:'.length);
      final dotIdx = rest.indexOf('.');
      if (dotIdx < 0) continue;
      final pair = rest.substring(0, dotIdx);
      final field = rest.substring(dotIdx + 1);
      relMap.putIfAbsent(pair, () => {})[field] = v;
    } else if (k.startsWith('arc:')) {
      final rest = k.substring('arc:'.length);
      final dotIdx = rest.indexOf('.');
      if (dotIdx < 0) continue;
      final arcId = rest.substring(0, dotIdx);
      final field = rest.substring(dotIdx + 1);
      arcMap.putIfAbsent(arcId, () => {})[field] = v;
    } else if (k.startsWith('world:')) {
      final field = k.substring('world:'.length);
      worldLines.add('$field: $v');
    } else if (k == 'scene.present_entities') {
      presentEntities = v;
    } else if (k == 'scene.absent_backstory_entities') {
      absentEntities = v;
    } else if (k.startsWith('scene.')) {
      final field = k.substring('scene.'.length);
      sceneLines.add('$field: $v');
    }
  }

  // ── Mentioned-entity filtering (plan §Prompt Injection Test 8) ──────────
  // When latestUserText is non-empty, filter npc/rel/arc to entities whose
  // name/title/id is mentioned. World, scene, and arcs with do_not_reopen
  // are always included regardless (card-baseline guard).
  final lowerCtx = latestUserText.toLowerCase();
  final filterByMention = lowerCtx.isNotEmpty;

  // Helper: true when [name] tokens appear in the lower-cased context.
  bool mentioned(String name) {
    if (!filterByMention) return true;
    final lower = name.toLowerCase();
    // Direct substring match.
    if (lowerCtx.contains(lower)) return true;
    // Partial match: any word ≥ 4 chars of the name appears.
    return lower
        .split(RegExp(r'[\s:]+'))
        .where((w) => w.length >= 4)
        .any(lowerCtx.contains);
  }

  final filteredNpc = filterByMention
      ? Map.fromEntries(npcMap.entries.where((e) => mentioned(e.key)))
      : npcMap;

  final filteredRel = filterByMention
      ? Map.fromEntries(
          relMap.entries.where((e) {
            // pair is "A:B" — check if either entity is mentioned.
            final parts = e.key.split(':');
            return parts.any(mentioned);
          }),
        )
      : relMap;

  final filteredArc = filterByMention
      ? Map.fromEntries(
          arcMap.entries.where((e) {
            final f = e.value;
            final doNotReopen = f['do_not_reopen']?.toLowerCase() == 'true';
            // Always keep do_not_reopen arcs (card-baseline regression guard).
            if (doNotReopen) return true;
            final title = f['title'] ?? e.key;
            return mentioned(title) || mentioned(e.key);
          }),
        )
      : arcMap;

  // ── Build output ─────────────────────────────────────────────────────────
  final buf = StringBuffer();
  buf.writeln('<studio_session_state>');
  buf.writeln(
    'These are established facts from this chat. '
    'They override character-card baseline when conflicting.',
  );

  // ── Present / Absent section (plan §Present Characters + Test 21) ────────
  // Always inject presence data when available — it prevents absent NPCs
  // from acting in the scene.
  if (presentEntities != null || absentEntities != null) {
    buf.writeln();
    if (presentEntities != null) {
      buf.writeln('Present now:');
      for (final name in presentEntities.split(RegExp(r'[;,\n]+'))) {
        final n = name.trim();
        if (n.isNotEmpty) buf.writeln('- $n');
      }
    }
    if (absentEntities != null) {
      buf.writeln('Absent/backstory only:');
      for (final name in absentEntities.split(RegExp(r'[;,\n]+'))) {
        final n = name.trim();
        if (n.isNotEmpty) buf.writeln('- $n');
      }
      buf.writeln(
        'Do not give dialogue or physical actions to absent characters '
        'unless through memory, recording, call, or explicit scene entry.',
      );
    }
  }

  if (filteredNpc.isNotEmpty) {
    for (final name in filteredNpc.keys.toList()..sort()) {
      buf.writeln('\n$name:');
      final fields = filteredNpc[name]!;
      for (final field in fields.keys.toList()..sort()) {
        buf.writeln('- $field: ${fields[field]}');
      }
    }
  }

  if (filteredRel.isNotEmpty) {
    buf.writeln('\nRelationships:');
    for (final pair in filteredRel.keys.toList()..sort()) {
      buf.writeln('$pair:');
      final fields = filteredRel[pair]!;
      for (final field in fields.keys.toList()..sort()) {
        buf.writeln('- $field: ${fields[field]}');
      }
    }
  }

  if (filteredArc.isNotEmpty) {
    final completed = <String>[];
    final active = <String>[];
    final other = <String>[];
    for (final arcId in filteredArc.keys) {
      final f = filteredArc[arcId]!;
      final status = f['status'] ?? '';
      if (status == 'completed' ||
          status == 'failed' ||
          status == 'abandoned' ||
          status == 'superseded') {
        completed.add(arcId);
      } else if (status == 'active') {
        active.add(arcId);
      } else {
        other.add(arcId);
      }
    }
    if (completed.isNotEmpty) {
      buf.writeln('\nResolved arcs:');
      for (final id in completed..sort()) {
        final f = filteredArc[id]!;
        final summary = f['summary'] ?? '';
        final noReopen = f['do_not_reopen']?.toLowerCase() == 'true';
        final override = f['card_override'] ?? '';
        buf.write('- ${f['title'] ?? id} is completed.');
        if (summary.isNotEmpty) buf.write(' $summary');
        if (noReopen) buf.write(' Do not reopen as active conflict.');
        if (override.isNotEmpty) buf.write(' $override');
        buf.writeln();
      }
    }
    if (active.isNotEmpty || other.isNotEmpty) {
      buf.writeln('\nActive arcs:');
      for (final id in [...active, ...other]..sort()) {
        final f = filteredArc[id]!;
        final summary = f['summary'] ?? '';
        if (summary.isNotEmpty) {
          buf.writeln('- ${f['title'] ?? id}: $summary');
        }
      }
    }
  }

  if (worldLines.isNotEmpty) {
    buf.writeln('\nWorld:');
    for (final line in worldLines) {
      buf.writeln('- $line');
    }
  }

  if (sceneLines.isNotEmpty) {
    buf.writeln('\nScene:');
    for (final line in sceneLines) {
      buf.writeln('- $line');
    }
  }

  buf.write('</studio_session_state>');
  final result = _dedupeAndCapStudioState(buf.toString()).trim();
  // If we only wrote the header and footer with no content, skip injection.
  final onlyHeader =
      result ==
      '<studio_session_state>\nThese are established facts from this chat. '
          'They override character-card baseline when conflicting.\n</studio_session_state>';
  if (onlyHeader) return null;
  return result.isEmpty ? null : result;
}

/// Dedupes repeated rendered canon lines and caps the block to a bounded size.
///
/// This is the MVP implementation of plan §Prompt Dedupe / Prompt Budget:
/// it prevents duplicate canon claims inside the high-authority Studio state
/// block and caps tail growth before lower-authority recall/memory blocks are
/// considered. The ordering of [_compileStudioSessionState] intentionally puts
/// manual overrides, presence, and resolved do_not_reopen arcs before lower-
/// priority world/scene details, so tail trimming preserves conflict-preventing
/// canon first.
String _dedupeAndCapStudioState(String raw) {
  const maxChars = 6000;
  final seen = <String>{};
  final lines = <String>[];
  for (final line in raw.split('\n')) {
    final trimmed = line.trim();
    // Keep structural blank lines, but dedupe actual claim lines.
    if (trimmed.isNotEmpty) {
      // CanonClaim-lite normalization: for bullet claims, dedupe by the fact
      // value after the first colon so the same claim rendered under two low-
      // authority field names appears once.
      final claimText = trimmed.startsWith('- ') && trimmed.contains(':')
          ? trimmed.substring(trimmed.indexOf(':') + 1).trim()
          : trimmed;
      final normalized = claimText.toLowerCase().replaceAll(
        RegExp(r'\s+'),
        ' ',
      );
      if (!seen.add(normalized)) continue;
    }
    lines.add(line);
  }
  var out = lines.join('\n');
  if (out.length <= maxChars) return out;
  final close = '</studio_session_state>';
  final trimNotice = '[trimmed lower-priority canon details]';
  final budget = maxChars - close.length - trimNotice.length - 2;
  if (budget <= 0) return out.substring(0, maxChars);
  final packed = <String>[];
  var used = 0;
  for (final line in lines) {
    final cost = line.length + 1;
    if (used + cost > budget) break;
    packed.add(line);
    used += cost;
  }
  out = packed.join('\n').trimRight();
  return '$out\n$trimNotice\n$close';
}

class _GenerationAbortedException implements Exception {
  const _GenerationAbortedException();
}

final promptPayloadBuilderProvider = Provider<PromptPayloadBuilder>((ref) {
  return PromptPayloadBuilder(ref);
});
