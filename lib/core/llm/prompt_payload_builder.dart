import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../../features/settings/api_list_provider.dart';
import '../../shared/widgets/glaze_toast.dart' show GlazeToast, ToastPosition;
import '../models/api_config.dart';
import '../models/character.dart';
import '../models/chat_message.dart';
import '../models/lorebook.dart';
import '../models/memory_book.dart';
import '../models/persona.dart';
import '../models/preset.dart';
import '../state/active_selection_provider.dart';
import '../state/db_provider.dart';
import '../state/global_regex_provider.dart';
import '../state/lorebook_provider.dart';
import '../state/memory_settings_provider.dart';
import 'embedding_types.dart';
import 'lorebook_providers.dart';
import 'memory_injection_service.dart';
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
    bool Function()? shouldAbort,
    CancelToken? cancelToken,
  }) async {
    void throwIfAborted() {
      if (shouldAbort?.call() == true) {
        throw const _GenerationAbortedException();
      }
    }

    throwIfAborted();
    debugPrint('[payload] reading character...');
    final charRepo = _ref.read(characterRepoProvider);
    final presetRepo = _ref.read(presetRepoProvider);
    final personaRepo = _ref.read(personaRepoProvider);
    final lorebookRepo = _ref.read(lorebookRepoProvider);

    final character = await charRepo.getById(charId);
    throwIfAborted();
    if (character == null) throw StateError('Character not found: $charId');

    debugPrint('[payload] reading API config...');
    await _ref.read(apiListProvider.future);
    throwIfAborted();
    final chatApi = _ref.read(activeApiConfigProvider);
    if (chatApi == null || chatApi.mode == 'embedding') {
      throw StateError('No chat API config available');
    }

    debugPrint('[payload] reading preset...');
    final activePresetId = _ref.read(activePresetIdProvider);
    final presets = await presetRepo.getAll();
    throwIfAborted();
    final preset = activePresetId != null
        ? presets.where((p) => p.id == activePresetId).firstOrNull
        : (presets.isNotEmpty ? presets.first : null);

    debugPrint('[payload] reading persona...');
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

    debugPrint('[payload] reading lorebooks...');
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
      debugPrint('[payload] injecting ext blocks into history...');
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

      debugPrint('[payload] getting summary...');
      final summaryService = _ref.read(summaryServiceProvider);
      summaryContent = await summaryService.getSummary(session.id);
      throwIfAborted();

      debugPrint('[payload] building memory injection...');
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
      );

      throwIfAborted();
      final results = await Future.wait([memoryFuture, lorebookFuture]);
      throwIfAborted();
      final memoryResult = results[0] as MemoryCandidateBuildResult;
      memorySelection = memoryResult.selection;
      memorySettings = memoryResult.settings ?? memorySettings;
      memoryInjectionTarget = memorySettings.injectionTarget == 'macro'
          ? 'macro'
          : 'hard_block';
      vectorEntries = results[1] as List<LorebookEntry>;
      throwIfAborted();
      debugPrint(
        '[payload] memory candidates done, picked=${memorySelection.entries.length}, total=${memorySelection.allScores.length}, excludedByWindow=${memorySelection.excludedBySourceWindow}',
      );

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

      if (!skipVectorSearch) {
        debugPrint(
          '[payload] vector search complete, entries=${vectorEntries.length}',
        );
      }
    }

    debugPrint(
      '[payload] building final payload... memorySelection=${memorySelection == null ? 'null' : '${memorySelection!.allScores.length} candidates'}',
    );
    return PromptPayload(
      character: character,
      persona: persona,
      preset: preset,
      history: history,
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

    return PromptPayload(
      character: character,
      persona: persona,
      preset: preset,
      history: history,
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
      memoryExcerptingEnabled: _ref
          .read(memoryGlobalSettingsProvider)
          .memoryExcerptingEnabled,
      memoryPackingMode: _ref
          .read(memoryGlobalSettingsProvider)
          .memoryPackingMode,
      memoryExcerptTokensPerChunk: _ref
          .read(memoryGlobalSettingsProvider)
          .memoryExcerptTokensPerChunk,
      memoryExcerptChunksPerEntry: _ref
          .read(memoryGlobalSettingsProvider)
          .memoryExcerptChunksPerEntry,
      chunkFirstTopEntries: _ref
          .read(memoryGlobalSettingsProvider)
          .chunkFirstTopEntries,
      chunkFirstTopChunks: _ref
          .read(memoryGlobalSettingsProvider)
          .chunkFirstTopChunks,
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
}

class _GenerationAbortedException implements Exception {
  const _GenerationAbortedException();
}

final promptPayloadBuilderProvider = Provider<PromptPayloadBuilder>((ref) {
  return PromptPayloadBuilder(ref);
});
