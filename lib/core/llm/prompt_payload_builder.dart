import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/api_list_provider.dart';
import '../../shared/widgets/glaze_toast.dart' show GlazeToast, ToastPosition;
import '../models/api_config.dart';
import '../models/character.dart';
import '../models/chat_message.dart';
import '../models/lorebook.dart';
import '../models/persona.dart';
import '../models/preset.dart';
import '../state/active_selection_provider.dart';
import '../state/db_provider.dart';
import '../state/global_regex_provider.dart';
import '../state/lorebook_provider.dart';
import 'embedding_types.dart';
import 'lorebook_providers.dart';
import 'memory_injection_service.dart';
import 'prompt_builder.dart';
import 'summary_service.dart';

class PromptPayloadBuilder {
  final Ref _ref;

  PromptPayloadBuilder(this._ref);

  Future<PromptPayload> buildFromSession({
    required String charId,
    required ChatSession? session,
    String? guidanceText,
    bool skipVectorSearch = false,
  }) async {
    final charRepo = _ref.read(characterRepoProvider);
    final presetRepo = _ref.read(presetRepoProvider);
    final personaRepo = _ref.read(personaRepoProvider);
    final apiConfigRepo = _ref.read(apiConfigRepoProvider);
    final lorebookRepo = _ref.read(lorebookRepoProvider);

    final character = await charRepo.getById(charId);
    if (character == null) throw StateError('Character not found: $charId');

    // Ensure apiListProvider has finished loading before reading the sync provider.
    // On cold start, activeApiConfigProvider returns null until the async load completes.
    await _ref.read(apiListProvider.future);
    final chatApi = _ref.read(activeApiConfigProvider);
    if (chatApi == null || chatApi.mode == 'embedding') throw StateError('No chat API config available');

    final activePresetId = _ref.read(activePresetIdProvider);
    final presets = await presetRepo.getAll();
    final preset = activePresetId != null
        ? presets.where((p) => p.id == activePresetId).firstOrNull
        : (presets.isNotEmpty ? presets.first : null);

    final personas = await personaRepo.getAll();
    final connections = _ref.read(personaConnectionsProvider);
    final activePersonaId = _ref.read(activePersonaIdProvider);
    final sessionId = session?.id;

    final persona = getEffectivePersona(
      personas, charId, sessionId, activePersonaId, connections,
    );

    final lorebooks = await lorebookRepo.getAll();
    final lorebookSettings = _ref.read(lorebookSettingsProvider);
    final lorebookActivations = _ref.read(lorebookActivationsProvider);

    String? summaryContent;
    String? memoryContent;
    String? memoryMacroContent;
    String memoryInjectionTarget = 'summary_block';
    Map<String, dynamic> memoryCoverage = {};
    List<TriggeredEntry> triggeredMemories = [];
    List<ChatMessage> history = session?.messages ?? [];
    Map<String, String> sessionVars = session?.sessionVars ?? {};
    List<LorebookEntry> vectorEntries = [];

    if (session != null) {
      final summaryService = _ref.read(summaryServiceProvider);
      summaryContent = await summaryService.getSummary(session.id);

      final memoryService = _ref.read(memoryInjectionServiceProvider);
      final historyText = session.historyText;
      final embeddingConfig = _ref.read(embeddingConfigProvider);
      final memoryHistory = session.messages
          .where((m) => !m.isHidden && !m.isTyping)
          .map((m) => ChatMessageForSearch(role: m.role, content: m.content))
          .toList();
      final memoryResult = await memoryService.buildInjection(
        sessionId: session.id,
        historyText: historyText,
        messageCount: session.messages.length,
        summaryExcerpt: summaryContent,
        history: memoryHistory,
        currentText: session.messages.lastOrNull?.content ?? '',
        embeddingConfig: embeddingConfig,
      );
      memoryContent = memoryResult.content.isNotEmpty ? memoryResult.content : null;
      memoryMacroContent = memoryResult.macroContent.isNotEmpty ? memoryResult.macroContent : null;
      memoryInjectionTarget = memoryResult.injectionTarget;
      if (memoryResult.entries.isNotEmpty) {
        memoryCoverage = {
          'entryIds': memoryResult.entries.map((e) => e.id).toList(),
          'needsRebuild': false,
          'stale': false,
        };
        triggeredMemories = memoryResult.entries.map((e) => TriggeredEntry(
          id: e.id,
          name: e.title.isNotEmpty ? e.title : e.id,
          source: 'memory',
        )).toList();
      }

      if (!skipVectorSearch) {
        vectorEntries = await _runVectorSearch(session.messages, session.messages.lastOrNull?.content ?? '', character.world, character, chatId: session.id);
      }
    }

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
      memoryContent: memoryContent,
      memoryMacroContent: memoryMacroContent,
      memoryInjectionTarget: memoryInjectionTarget,
      memoryCoverage: memoryCoverage,
      guidanceText: guidanceText,
      authorsNote: session?.authorsNote,
      characterDepthPrompt: character.depthPrompt,
      characterDepthPromptDepth: character.depthPromptDepth,
      characterDepthPromptRole: character.depthPromptRole,
      globalRegexes: _ref.read(globalRegexProvider).valueOrNull ?? [],
      triggeredMemories: triggeredMemories,
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
    String memoryInjectionTarget = 'summary_block',
    Map<String, dynamic> memoryCoverage = const {},
    List<TriggeredEntry> triggeredMemories = const [],
    String? guidanceText,
    bool skipVectorSearch = true,
  }) async {
    final lorebookSettings = _ref.read(lorebookSettingsProvider);
    final lorebookActivations = _ref.read(lorebookActivationsProvider);

    List<LorebookEntry> vectorEntries = [];
    if (!skipVectorSearch && session != null) {
      vectorEntries = await _runVectorSearch(
        session.messages,
        session.messages.lastOrNull?.content ?? '',
        character.world,
        character,
      );
    }

    return PromptPayload(
      character: character,
      persona: persona,
      preset: preset,
      history: session?.messages ?? [],
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
      globalRegexes: _ref.read(globalRegexProvider).valueOrNull ?? [],
      triggeredMemories: triggeredMemories,
    );
  }

  Future<List<LorebookEntry>> _runVectorSearch(
    List<ChatMessage> history,
    String currentText,
    String? charWorld,
    Character? character, {
    String? chatId,
  }) async {
    final settings = _ref.read(lorebookSettingsProvider);
    if (settings.searchType == 'keyword') return [];

    final config = _ref.read(embeddingConfigProvider);
    if (config.endpoint.isEmpty) return [];

    final lorebooks = await _ref.read(lorebookRepoProvider).getAll();
    if (lorebooks.isEmpty) return [];

    try {
      final searchService = _ref.read(lorebookVectorSearchProvider);
      final searchHistory = history
          .map((m) => ChatMessageForSearch(role: m.role, content: m.content))
          .toList();
      final activations = _ref.read(lorebookActivationsProvider);
      // Request up to maxInjectedEntries candidates so that after deduplication
      // with keyword entries we still have enough to fill vectorSlots.
      final overrideTopK = settings.maxInjectedEntries;
      final results = await searchService.search(
        searchHistory, currentText, lorebooks, settings, config,
        charWorld: charWorld,
        character: character,
        activations: activations,
        chatId: chatId,
        overrideTopK: overrideTopK,
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

final promptPayloadBuilderProvider = Provider<PromptPayloadBuilder>((ref) {
  return PromptPayloadBuilder(ref);
});
