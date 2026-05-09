import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import 'lorebook_vector_search.dart';
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

    final apiConfigs = await apiConfigRepo.getAll();
    final chatApi = apiConfigs.where((cfg) => cfg.mode != 'embedding').firstOrNull;
    if (chatApi == null) throw StateError('No chat API config available');

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
    String memoryInjectionTarget = 'summary_block';
    Map<String, dynamic> memoryCoverage = {};
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
      memoryInjectionTarget = memoryResult.injectionTarget;
      if (memoryResult.entries.isNotEmpty) {
        memoryCoverage = {
          for (final e in memoryResult.entries) e.id: {'title': e.title, 'keys': e.keys},
        };
      }

      if (!skipVectorSearch) {
        vectorEntries = await _runVectorSearch(session.messages, session.messages.lastOrNull?.content ?? '', character.world, character);
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
      memoryInjectionTarget: memoryInjectionTarget,
      memoryCoverage: memoryCoverage,
      guidanceText: guidanceText,
      authorsNote: session?.authorsNote,
      characterDepthPrompt: character.depthPrompt,
      characterDepthPromptDepth: character.depthPromptDepth,
      characterDepthPromptRole: character.depthPromptRole,
      globalRegexes: _ref.read(globalRegexProvider).valueOrNull ?? [],
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
    String memoryInjectionTarget = 'summary_block',
    Map<String, dynamic> memoryCoverage = const {},
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
      memoryInjectionTarget: memoryInjectionTarget,
      memoryCoverage: memoryCoverage,
      guidanceText: guidanceText,
      authorsNote: session?.authorsNote,
      characterDepthPrompt: character.depthPrompt,
      characterDepthPromptDepth: character.depthPromptDepth,
      characterDepthPromptRole: character.depthPromptRole,
      globalRegexes: _ref.read(globalRegexProvider).valueOrNull ?? [],
    );
  }

  Future<List<LorebookEntry>> _runVectorSearch(
    List<ChatMessage> history,
    String currentText,
    String? charWorld,
    Character? character,
  ) async {
    final settings = _ref.read(lorebookSettingsProvider);
    if (settings.searchType == 'keys') return [];

    final config = _ref.read(embeddingConfigProvider);
    if (config.endpoint.isEmpty) return [];

    final lorebooks = await _ref.read(lorebookRepoProvider).getAll();
    if (lorebooks.isEmpty) return [];

    try {
      final searchService = _ref.read(lorebookVectorSearchProvider);
      final searchHistory = history
          .map((m) => ChatMessageForSearch(role: m.role, content: m.content))
          .toList();
      final results = await searchService.search(searchHistory, currentText, lorebooks, settings, config, charWorld: charWorld, character: character);

      final entryMap = <String, LorebookEntry>{};
      for (final lb in lorebooks) {
        for (final entry in lb.entries) {
          entryMap[entry.id] = entry;
        }
      }
      return results.where((r) => entryMap.containsKey(r.entryId)).map((r) => entryMap[r.entryId]!.copyWith()).toList();
    } catch (e) {
      debugPrint('VECTOR SEARCH: failed: $e');
      return [];
    }
  }
}

final promptPayloadBuilderProvider = Provider<PromptPayloadBuilder>((ref) {
  return PromptPayloadBuilder(ref);
});
