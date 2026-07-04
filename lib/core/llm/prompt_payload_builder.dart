import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../../features/settings/api_list_provider.dart';
import '../models/api_config.dart';
import '../models/character.dart';
import '../models/chat_message.dart';
import '../utils/cast_helpers.dart';
import '../models/lorebook.dart';
import '../models/memory_book.dart';
import '../models/persona.dart';
import '../models/preset.dart';
import '../state/active_selection_provider.dart';
import '../state/db_provider.dart';
import '../state/global_regex_provider.dart';
import '../state/lorebook_provider.dart';
import '../state/memory_settings_provider.dart';
import 'lorebook_providers.dart';
import 'memory_injection_service.dart';
import 'message_recall_service.dart';
import 'memory_selector.dart';
import '../../features/extensions/services/ext_blocks_prompt_injection.dart';
import '../../features/extensions/services/runtime_prompt_injection_service.dart';
import 'prompt_builder.dart';
import 'prompt/arc_state_builder.dart';
import 'prompt/ledger_tracker_loader.dart';
import 'prompt/lorebook_vector_searcher.dart';
import 'prompt/studio_session_state_compiler.dart';
import 'prompt_inputs.dart';
import 'prompt_inputs_collector.dart';
import 'summary_service.dart';

// Re-export for backward compat — tests import this from here.
export 'prompt/studio_session_state_compiler.dart'
    show kCompileStudioSessionStateForTest;

class PromptPayloadBuilder {
  final Ref _ref;
  late final PromptInputsCollector _inputsCollector = PromptInputsCollector(
    _ref,
  );
  late final LedgerTrackerLoader _ledgerTrackerLoader = LedgerTrackerLoader(
    _ref,
  );
  late final LorebookVectorSearcher _vectorSearcher = LorebookVectorSearcher(
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
    List<RecalledMessageChunk> recalledMessageChunks = const [];
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
          ? _vectorSearcher.search(
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
        recalledMessageChunks = recallResult.matches
            .map(
              (m) => RecalledMessageChunk(
                text: m.text,
                messageIds: m.messageIds,
              ),
            )
            .toList(growable: false);
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
        final ledgerTrackers = await _ledgerTrackerLoader
            .loadEffectiveLedgerTrackers(sessionId);
        if (ledgerTrackers.isNotEmpty) {
          studioSessionStateContent = compileStudioSessionState(
            ledgerTrackers,
            sessionId,
            latestUserText: latestUserTextFromHistory(history),
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
        final allLedger = await _ledgerTrackerLoader
            .loadEffectiveLedgerTrackers(sessionId);
        arcContent = buildArcContent(
          allLedger,
          latestUserText: latestUserTextFromHistory(history),
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
      recalledMessageChunks: recalledMessageChunks,
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
      vectorEntries = await _vectorSearcher.search(
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
        final ledgerTrackers = await _ledgerTrackerLoader
            .loadEffectiveLedgerTrackers(session.id);
        if (ledgerTrackers.isNotEmpty) {
          studioSessionStateContent = compileStudioSessionState(
            ledgerTrackers,
            session.id,
            latestUserText: latestUserTextFromHistory(history),
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
        final allLedger = await _ledgerTrackerLoader
            .loadEffectiveLedgerTrackers(session.id);
        arcContent = buildArcContent(
          allLedger,
          latestUserText: latestUserTextFromHistory(history),
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
      recalledMessageChunks: const [],
    );
  }
}

class _GenerationAbortedException implements Exception {
  const _GenerationAbortedException();
}

final promptPayloadBuilderProvider = Provider<PromptPayloadBuilder>((ref) {
  return PromptPayloadBuilder(ref);
});
