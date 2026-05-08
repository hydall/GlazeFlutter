import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/llm/lorebook_scanner.dart';
import '../../../core/llm/prompt_isolate.dart';
import '../../../core/llm/prompt_payload_builder.dart';
import '../../../core/llm/summary_service.dart';
import '../../../core/state/active_selection_provider.dart';
import '../../../core/state/db_provider.dart';
import '../../../core/state/lorebook_provider.dart';
import '../../image_gen/image_gen_provider.dart';
import '../chat_provider.dart';
import 'magic_drawer_models.dart';

class MagicDrawerStatsService {
  final WidgetRef _ref;

  MagicDrawerStatsService(this._ref);

  Future<MagicDrawerStats> computeStats(String charId) async {
    final chatState = _ref.read(chatProvider(charId)).value;
    final session = chatState?.session;
    final charRepo = _ref.read(characterRepoProvider);
    final presetRepo = _ref.read(presetRepoProvider);
    final personaRepo = _ref.read(personaRepoProvider);
    final apiRepo = _ref.read(apiConfigRepoProvider);
    final lorebookRepo = _ref.read(lorebookRepoProvider);
    final memoryRepo = _ref.read(memoryBookRepoProvider);

    final character = await charRepo.getById(charId);
    final presets = await presetRepo.getAll();
    final personas = await personaRepo.getAll();
    final apiConfigs = await apiRepo.getAll();
    final lorebooks = await lorebookRepo.getAll();
    final activePresetId = _ref.read(activePresetIdProvider);
    final activePersonaId = _ref.read(activePersonaIdProvider);
    final activePreset = activePresetId != null
        ? presets.where((p) => p.id == activePresetId).firstOrNull
        : presets.firstOrNull;
    final activePersona = activePersonaId != null
        ? personas.where((p) => p.id == activePersonaId).firstOrNull
        : personas.firstOrNull;
    final chatApi = apiConfigs
        .where((cfg) => cfg.mode != 'embedding')
        .firstOrNull;
    final regexes = await _ref.read(activeRegexesProvider.future);

    var summaryChars = 0;
    var memoryEntries = 0;
    var sessionCount = 0;
    var messageCount = 0;

    if (session != null) {
      final summary = await _ref
          .read(summaryServiceProvider)
          .getSummary(session.id);
      summaryChars = summary?.length ?? 0;
      final memoryBook = await memoryRepo.getBySessionId(session.id);
      memoryEntries = memoryBook?.entries.length ?? 0;
      sessionCount =
          (await _ref.read(chatRepoProvider).getByCharacterId(charId)).length;
      messageCount = session.messages.length;
    }

    final lorebookActivations = _ref.read(lorebookActivationsProvider);
    final lorebookSettings = _ref.read(lorebookSettingsProvider);
    final triggeredEntries = session != null
        ? scanLorebooks(
            history: session.messages,
            char: character,
            textToScan: session.messages.isNotEmpty
                ? session.messages.last.content
                : '',
            chatId: session.id,
            lorebooks: lorebooks,
            globalSettings: lorebookSettings,
            activations: lorebookActivations,
          )
        : <ScannedEntry>[];

    bool imageGenEnabled = false;
    try {
      imageGenEnabled = _ref.read(imageGenSettingsProvider).value?.enabled == true;
    } catch (_) {}

    return MagicDrawerStats(
      character: character,
      activePreset: activePreset,
      activePersona: activePersona,
      apiConfig: chatApi,
      session: session,
      sessionCount: sessionCount,
      messageCount: messageCount,
      lorebookEntryCount: triggeredEntries.length,
      memoryEntryCount: memoryEntries,
      regexCount: regexes.length,
      summaryChars: summaryChars,
      promptTokens: 0,
      contextSize: chatApi?.contextSize ?? 0,
      characterTokens: 0,
      presetTokens: 0,
      personaTokens: 0,
      summaryTokens: 0,
      imageGenEnabled: imageGenEnabled,
    );
  }

  Future<MagicDrawerStats> computeTokenStats(String charId, MagicDrawerStats base) async {
    final chatState = _ref.read(chatProvider(charId)).value;
    final session = chatState?.session;
    final character = base.character;
    final chatApi = base.apiConfig;

    if (session == null || character == null || chatApi == null) return base;

    try {
      final builder = _ref.read(promptPayloadBuilderProvider);
      final payload = await builder.buildFromSession(charId: charId, session: session);
      final promptResult = await buildPromptInIsolate(payload);
      final sourceTokens = promptResult.breakdown.sourceTokens;
      return base.copyWith(
        promptTokens: promptResult.breakdown.totalTokens,
        characterTokens: sourceTokens['character'] ?? 0,
        presetTokens: sourceTokens['preset'] ?? 0,
        personaTokens: sourceTokens['persona'] ?? 0,
        summaryTokens: sourceTokens['summary'] ?? 0,
      );
    } catch (_) {
      return base;
    }
  }
}
