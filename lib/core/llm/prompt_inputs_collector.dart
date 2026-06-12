import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/api_list_provider.dart';
import '../../features/extensions/services/ext_blocks_prompt_injection.dart';
import '../../features/extensions/services/runtime_prompt_injection_service.dart';
import '../models/chat_message.dart';
import '../state/active_selection_provider.dart';
import '../state/db_provider.dart';
import '../state/global_regex_provider.dart';
import '../state/lorebook_provider.dart';
import '../state/memory_settings_provider.dart';
import 'prompt_builder.dart';
import 'prompt_inputs.dart';
import 'summary_service.dart';

class PromptInputsCollector {
  final Ref _ref;

  PromptInputsCollector(this._ref);

  /// Collects raw inputs from DB/providers for isolate-based processing.
  /// Fast path: DB reads only, no memory injection or vector search.
  Future<PromptInputs> collectInputs({
    required String charId,
    required ChatSession? session,
    String? guidanceText,
  }) async {
    final charRepo = _ref.read(characterRepoProvider);
    final presetRepo = _ref.read(presetRepoProvider);
    final personaRepo = _ref.read(personaRepoProvider);
    final lorebookRepo = _ref.read(lorebookRepoProvider);

    final character = await charRepo.getById(charId);
    if (character == null) throw StateError('Character not found: $charId');

    await _ref.read(apiListProvider.future);
    final chatApi = _ref.read(activeApiConfigProvider);
    if (chatApi == null || chatApi.mode == 'embedding') {
      throw StateError('No chat API config available');
    }

    final activePresetId = _ref.read(activePresetIdProvider);
    final presetConnections = _ref.read(presetConnectionsProvider);
    final presets = await presetRepo.getAll();
    final preset = getEffectivePreset(
      presets,
      charId,
      session?.id,
      activePresetId,
      presetConnections,
    );

    final personas = await personaRepo.getAll();
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
    final lorebookSettings = _ref.read(lorebookSettingsProvider);
    final lorebookActivations = _ref.read(lorebookActivationsProvider);

    String? summaryContent;
    if (session != null) {
      final summaryService = _ref.read(summaryServiceProvider);
      summaryContent = await summaryService.getSummary(session.id);
    }

    final memoryBook = session != null
        ? await _ref.read(memoryBookRepoProvider).getBySessionId(session.id)
        : null;
    final memoryEntries = memoryBook?.entries ?? [];

    final memorySettings = _ref.read(memoryGlobalSettingsProvider);

    var history = session?.messages ?? [];
    var runtimePromptBlocks = const <RuntimePromptBlock>[];
    if (session != null) {
      history = await _ref
          .read(extBlocksPromptInjectionProvider)
          .injectIntoHistory(sessionId: session.id, messages: history);
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
    }

    return PromptInputs(
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
      summaryContent: summaryContent,
      guidanceText: guidanceText,
      authorsNote: session?.authorsNote,
      characterDepthPrompt: character.depthPrompt,
      characterDepthPromptDepth: character.depthPromptDepth,
      characterDepthPromptRole: character.depthPromptRole,
      globalRegexes: _ref.read(globalRegexProvider).value ?? [],
      memoryEntries: memoryEntries,
      memoryEnabled: memorySettings.enabled,
      memoryMode: memorySettings.memoryMode,
      memoryMaxInjected: memorySettings.maxInjectedEntries,
      memoryKeyMatchMode: memorySettings.keyMatchMode,
      memoryInjectionTarget: memorySettings.injectionTarget,
      memoryMaxInjectedTokens: memoryBook?.settings.maxInjectedTokens,
      memoryMaxInjectionBudgetPercent:
          memoryBook?.settings.maxInjectionBudgetPercent ?? 0.35,
      memoryDiversityAware: memoryBook?.settings.diversityAware ?? true,
      memoryDiversityPenalty: memoryBook?.settings.diversityPenalty ?? 0.15,
      memoryRecencyBoost: memoryBook?.settings.recencyBoost ?? true,
      memoryRecencyHalfLifeDays:
          memoryBook?.settings.recencyHalfLifeDays ?? 100,
      memoryImportanceBoost: memoryBook?.settings.importanceBoost ?? true,
      memoryImportanceWeight: memoryBook?.settings.importanceWeight ?? 0.5,
      memorySourceWindowExclusion:
          memoryBook?.settings.sourceWindowExclusion ?? true,
      memoryQueryIncludeAssistant:
          memoryBook?.settings.queryIncludeAssistant ?? true,
      memoryQueryRecentTurns: memoryBook?.settings.queryRecentTurns ?? 6,
      memoryQueryMaxChars: memoryBook?.settings.queryMaxChars ?? 1500,
      memoryContextBudgetTokens: chatApi.contextSize,
      runtimePromptBlocks: runtimePromptBlocks,
    );
  }
}

final promptInputsCollectorProvider = Provider<PromptInputsCollector>((ref) {
  return PromptInputsCollector(ref);
});
