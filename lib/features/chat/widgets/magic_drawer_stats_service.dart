import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/llm/lorebook_scanner.dart';
import '../../../core/llm/prompt_builder.dart';
import '../../../core/llm/prompt_isolate.dart';
import '../../../core/llm/prompt_payload_builder.dart';
import '../../../core/llm/summary_service.dart';
import '../../../core/state/active_selection_provider.dart';
import '../../../core/state/db_provider.dart';
import '../../../core/state/lorebook_provider.dart';
import '../../image_gen/image_gen_provider.dart';
import '../chat_provider.dart';
import 'cached_token_breakdown.dart';
import 'magic_drawer_models.dart';

class _StatsContext {
  final List<ScannedEntry> scannedEntries;
  const _StatsContext({required this.scannedEntries});
}

class MagicDrawerStatsService {
  final WidgetRef _ref;

  MagicDrawerStatsService(this._ref);

  _StatsContext? _lastStatsContext;

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
    String? summaryContent;
    String? memoryContent;
    String memoryInjectionTarget = 'summary_block';
    Map<String, dynamic> memoryCoverage = {};

    if (session != null) {
      final summary = await _ref
          .read(summaryServiceProvider)
          .getSummary(session.id);
      summaryContent = summary;
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

    _lastStatsContext = _StatsContext(scannedEntries: triggeredEntries);

    bool imageGenEnabled = false;
    try {
      imageGenEnabled = _ref.read(imageGenSettingsProvider).value?.enabled == true;
    } catch (_) {}

    final cached = _ref.read(cachedTokenBreakdownProvider(charId));

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
      promptTokens: cached?.totalTokens ?? 0,
      contextSize: chatApi?.contextSize ?? 0,
      characterTokens: cached?.sourceTokens['character'] ?? 0,
      presetTokens: cached?.sourceTokens['preset'] ?? 0,
      personaTokens: cached?.sourceTokens['persona'] ?? 0,
      summaryTokens: cached?.sourceTokens['summary'] ?? 0,
      imageGenEnabled: imageGenEnabled,
      lorebooks: lorebooks,
      summaryContent: summaryContent,
      memoryContent: memoryContent,
      memoryInjectionTarget: memoryInjectionTarget,
      memoryCoverage: memoryCoverage,
    );
  }

  Future<MagicDrawerStats> computeTokenStats(String charId, MagicDrawerStats base) async {
    final session = base.session;
    final character = base.character;
    final chatApi = base.apiConfig;

    if (session == null || character == null || chatApi == null) return base;

    try {
      final builder = _ref.read(promptPayloadBuilderProvider);
      final payload = await builder.buildFromPreFetched(
        charId: charId,
        session: session,
        character: character,
        chatApi: chatApi,
        preset: base.activePreset,
        persona: base.activePersona,
        lorebooks: base.lorebooks,
        summaryContent: base.summaryContent,
        memoryContent: base.memoryContent,
        memoryInjectionTarget: base.memoryInjectionTarget,
        memoryCoverage: base.memoryCoverage,
        skipVectorSearch: true,
      );
      final payloadWithScan = PromptPayload(
        character: payload.character,
        persona: payload.persona,
        preset: payload.preset,
        history: payload.history,
        apiConfig: payload.apiConfig,
        sessionVars: payload.sessionVars,
        globalVars: payload.globalVars,
        lorebooks: payload.lorebooks,
        lorebookSettings: payload.lorebookSettings,
        lorebookActivations: payload.lorebookActivations,
        vectorEntries: payload.vectorEntries,
        summaryContent: payload.summaryContent,
        memoryContent: payload.memoryContent,
        memoryInjectionTarget: payload.memoryInjectionTarget,
        memoryCoverage: payload.memoryCoverage,
        guidanceText: payload.guidanceText,
        authorsNote: payload.authorsNote,
        characterDepthPrompt: payload.characterDepthPrompt,
        characterDepthPromptDepth: payload.characterDepthPromptDepth,
        characterDepthPromptRole: payload.characterDepthPromptRole,
        globalRegexes: payload.globalRegexes,
        preScannedEntries: _lastStatsContext?.scannedEntries,
      );
      final promptResult = await buildPromptInIsolate(payloadWithScan);
      final sourceTokens = promptResult.breakdown.sourceTokens;

      _ref.read(cachedTokenBreakdownProvider(charId).notifier).state =
          promptResult.breakdown;

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
