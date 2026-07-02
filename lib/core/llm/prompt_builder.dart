import 'package:flutter/foundation.dart';

import '../models/character.dart';
import '../models/persona.dart';
import '../models/preset.dart';
import '../models/chat_message.dart';
import '../models/api_config.dart';
import '../models/lorebook.dart';
import 'macro_engine.dart';
import 'history_assembler.dart';
import 'context_calculator.dart';
import 'lorebook_coverage.dart';
import 'lorebook_scanner.dart';
import 'lorebook_merger.dart';
import 'prompt_block_resolver.dart';
import 'prompt_regex_applicator.dart';
import 'fallback_prompt_builder.dart';
import 'tokenizer.dart';
import 'memory_budget.dart';
import 'memory_diagnostics.dart';
import 'memory_excerpt_selector.dart';
import 'memory_formatting.dart';
import 'memory_selector.dart';

const _deferredMemoryPlaceholder = '[[GLAZE_DEFERRED_MEMORY_CONTEXT]]';

class RuntimePromptBlock {
  final String id;
  final String content;
  final int depth;
  final String role;

  const RuntimePromptBlock({
    required this.id,
    required this.content,
    required this.depth,
    required this.role,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'depth': depth,
    'role': role,
  };

  factory RuntimePromptBlock.fromJson(Map<String, dynamic> json) =>
      RuntimePromptBlock(
        id: json['id'] as String,
        content: json['content'] as String,
        depth: json['depth'] as int? ?? 0,
        role: json['role'] as String? ?? 'system',
      );
}

class RecalledMessageChunk {
  final String text;
  final List<String> messageIds;

  const RecalledMessageChunk({required this.text, this.messageIds = const []});

  Map<String, dynamic> toJson() => {'text': text, 'messageIds': messageIds};

  factory RecalledMessageChunk.fromJson(Map<String, dynamic> json) =>
      RecalledMessageChunk(
        text: json['text'] as String? ?? '',
        messageIds: (json['messageIds'] as List? ?? const []).cast<String>(),
      );
}

const _stToInternalBlockId = <String, String>{
  'personaDescription': 'user_persona',
  'charDescription': 'char_card',
  'charPersonality': 'char_personality',
  'dialogueExamples': 'example_dialogue',
  'chatHistory': 'chat_history',
};

String normalizeBlockId(String blockId) {
  return _stToInternalBlockId[blockId] ?? blockId;
}

class PromptPayload {
  final Character character;
  final Persona? persona;
  final Preset? preset;
  final List<ChatMessage> history;
  final String? sessionId;
  final ApiConfig apiConfig;
  final Map<String, String> sessionVars;
  final Map<String, String> globalVars;
  final String? summaryContent;
  final String? summaryPrefix;
  final String? memoryContent;

  /// Raw entry text joined with \n\n — used in summary_macro mode to append
  /// directly onto the summary message (no bullet headers, no summary excerpt).
  /// Mirrors JS memoryInjection.macroContent.
  final String? memoryMacroContent;
  final String memoryInjectionTarget;
  final String? guidanceText;
  final List<Lorebook> lorebooks;
  final LorebookGlobalSettings lorebookSettings;
  final LorebookActivations lorebookActivations;
  final List<LorebookEntry> vectorEntries;
  final AuthorsNote? authorsNote;
  final String characterDepthPrompt;
  final int characterDepthPromptDepth;
  final String characterDepthPromptRole;
  final Map<String, dynamic> memoryCoverage;
  final List<PresetRegex> globalRegexes;
  final List<ScannedEntry>? preScannedEntries;
  final List<TriggeredEntry> triggeredMemories;
  final List<RuntimePromptBlock> runtimePromptBlocks;
  final MemorySelection? memorySelection;
  final bool memoryExcerptingEnabled;
  final String memoryPackingMode;
  final int memoryExcerptTokensPerChunk;
  final int memoryExcerptChunksPerEntry;
  final int chunkFirstTopEntries;
  final int chunkFirstTopChunks;
  final String? arcContent;
  final String? entitiesContent;

  /// Compiled `<studio_session_state>` block from committed ledger tracker rows.
  /// Injected via `{{studio_state}}` macro and as a hard system block at the
  /// start of the prompt. Null/empty when Studio Ledger is disabled or no
  /// state has been committed for this session yet.
  final String? studioSessionStateContent;

  /// Lossless backstop for the lossy MemoryBook compression — top-K raw
  /// chat-message chunks semantically closest to the current user message,
  /// returned by [MessageRecallService]. Injected into the prompt as a
  /// `<recalled_messages>` system block before the first user/assistant
  /// message. See docs/plans/PLAN_MEMORY_CONTINUITY.md §1 (patch #3).
  final String? recalledMessagesContent;

  /// Structured recalled chunks with source message ids. When present, this is
  /// preferred over [recalledMessagesContent] so source-window filtering can
  /// keep raw recall out of the prompt while the source chunk is still visible.
  final List<RecalledMessageChunk> recalledMessageChunks;

  /// When true, MemoryBook entries whose source messages fall inside the
  /// visible window are NOT excluded. Studio tracker briefs are compact
  /// JSON — they never carry the source messages themselves, so
  /// deduplicating MemoryBook entries against visible messages wastes
  /// durable facts that the tracker would otherwise leverage. Default
  /// false = legacy source-window exclusion applies.
  final bool disableSourceWindowExclusion;

  /// Overrides the message ids treated as visible for message-bound memory
  /// source-window exclusion. Empty means use the final token-cutoff window.
  /// Studio uses this to align memory injection with the final generator's
  /// `maxFinalHistoryMessages` window, which is applied after base prompt build.
  final Set<String> sourceWindowVisibleMessageIds;

  /// djb2-style hash of the compiled memory injection content for this
  /// turn. Used by the next generation to detect "memory changed since
  /// last turn" and invalidate prompt cache (Anthropic / DeepSeek prompt
  /// caching). When this fingerprint matches the previous turn's, the
  /// prompt cache is valid; when it differs, the cache misses — but
  /// correctness is unaffected (the new memory content is sent). Mirrors
  /// Marinara's `chatSummaryFingerprint` (djb2 on compiled summary). We
  /// hash the MemoryBook injection content (MemoryBook is our summary
  /// equivalent). Empty when no memory content was injected.
  /// See docs/plans/PLAN_MEMORY_CONTINUITY.md §2.3.
  final String memoryInjectionFingerprint;

  const PromptPayload({
    required this.character,
    this.persona,
    this.preset,
    required this.history,
    this.sessionId,
    required this.apiConfig,
    this.sessionVars = const {},
    this.globalVars = const {},
    this.summaryContent,
    this.summaryPrefix,
    this.memoryContent,
    this.memoryMacroContent,
    this.memoryInjectionTarget = 'summary_block',
    this.guidanceText,
    this.lorebooks = const [],
    this.lorebookSettings = const LorebookGlobalSettings(),
    this.lorebookActivations = const LorebookActivations(),
    this.vectorEntries = const [],
    this.authorsNote,
    this.characterDepthPrompt = '',
    this.characterDepthPromptDepth = 4,
    this.characterDepthPromptRole = 'system',
    this.memoryCoverage = const {},
    this.globalRegexes = const [],
    this.preScannedEntries,
    this.triggeredMemories = const [],
    this.runtimePromptBlocks = const [],
    this.memorySelection,
    this.memoryExcerptingEnabled = true,
    this.memoryPackingMode = 'hybrid',
    this.memoryExcerptTokensPerChunk = defaultMemoryExcerptTokensPerEntry,
    this.memoryExcerptChunksPerEntry = defaultMemoryExcerptChunksPerEntry,
    this.chunkFirstTopEntries = 3,
    this.chunkFirstTopChunks = 1,
    this.arcContent,
    this.entitiesContent,
    this.studioSessionStateContent,
    this.recalledMessagesContent,
    this.recalledMessageChunks = const [],
    this.disableSourceWindowExclusion = false,
    this.sourceWindowVisibleMessageIds = const {},
    this.memoryInjectionFingerprint = '',
  });
}

class PromptResult {
  final List<PromptMessage> messages;
  final TokenBreakdown breakdown;
  final Map<String, String> sessionVars;
  final Map<String, String> globalVars;
  final List<TriggeredEntry> triggeredLorebooks;
  final List<TriggeredEntry> triggeredMemories;
  final Map<String, dynamic> memoryCoverage;

  const PromptResult({
    required this.messages,
    required this.breakdown,
    required this.sessionVars,
    required this.globalVars,
    this.triggeredLorebooks = const [],
    this.triggeredMemories = const [],
    this.memoryCoverage = const {},
  });

  Map<String, dynamic> toJson() => {
    'messages': messages.map((m) => m.toJson()).toList(),
    'breakdown': breakdown.toJson(),
    'sessionVars': sessionVars,
    'globalVars': globalVars,
    'triggeredLorebooks': triggeredLorebooks.map((t) => t.toJson()).toList(),
    'triggeredMemories': triggeredMemories.map((t) => t.toJson()).toList(),
    'memoryCoverage': memoryCoverage,
  };

  factory PromptResult.fromJson(Map<String, dynamic> json) => PromptResult(
    messages: (json['messages'] as List)
        .map((m) => PromptMessage.fromJson(m as Map<String, dynamic>))
        .toList(),
    breakdown: TokenBreakdown.fromJson(
      json['breakdown'] as Map<String, dynamic>,
    ),
    sessionVars: Map<String, String>.from(json['sessionVars'] as Map),
    globalVars: Map<String, String>.from(json['globalVars'] as Map),
    triggeredLorebooks: (json['triggeredLorebooks'] as List? ?? [])
        .map((t) => TriggeredEntry.fromJson(t as Map<String, dynamic>))
        .toList(),
    triggeredMemories: (json['triggeredMemories'] as List? ?? [])
        .map((t) => TriggeredEntry.fromJson(t as Map<String, dynamic>))
        .toList(),
    memoryCoverage: Map<String, dynamic>.from(
      json['memoryCoverage'] as Map? ?? {},
    ),
  );
}

class _ResolvedDepthBlock {
  final String id;
  final String role;
  final String content;
  final int depth;
  final bool isSummary;
  const _ResolvedDepthBlock({
    required this.id,
    required this.role,
    required this.content,
    required this.depth,
    this.isSummary = false,
  });
}

class _ResolvedRelativeBlock {
  final String id;
  final String name;
  final String role;

  /// Fully expanded content — what the LLM sees. Used for `messages` and
  /// `appendedEntries` (which merge into the last user message).
  final String content;

  /// Accounting-only content with dynamic macro injections blanked out.
  /// Used for `attributionBlocks` and `mergeBuffer` so that the preset's
  /// "static chrome" tokens are not double-counted alongside the dedicated
  /// `sourceTokens['memory']` / `sourceTokens['summary']` etc. buckets.
  final String contentForAccounting;
  final bool isSummary;
  final bool appendToLastMessage;
  const _ResolvedRelativeBlock({
    required this.id,
    required this.name,
    required this.role,
    required this.content,
    required this.contentForAccounting,
    this.isSummary = false,
    this.appendToLastMessage = false,
  });
}

PromptResult buildPrompt(PromptPayload payload) {
  if (payload.preset == null) return buildFallbackPrompt(payload);

  final preset = payload.preset!;
  final char = payload.character;
  final persona = payload.persona;

  const defaultTagStart = '<think>';
  const defaultTagEnd = '</think>';
  // Vue-поведение: если preset пустой (null/""), берём теги из API settings (или дефолт).
  final effectiveReasoningTagStart = (preset.reasoningStart?.isNotEmpty == true)
      ? preset.reasoningStart!
      : (payload.apiConfig.reasoningTagStart?.isNotEmpty == true)
      ? payload.apiConfig.reasoningTagStart!
      : defaultTagStart;
  final effectiveReasoningTagEnd = (preset.reasoningEnd?.isNotEmpty == true)
      ? preset.reasoningEnd!
      : (payload.apiConfig.reasoningTagEnd?.isNotEmpty == true)
      ? payload.apiConfig.reasoningTagEnd!
      : defaultTagEnd;

  final macroCtx = MacroContext(
    charName: char.name,
    charDescription: char.description,
    charScenario: char.scenario,
    charPersonality: char.personality,
    charMesExample: char.mesExample,
    userName: persona?.name ?? 'User',
    personaPrompt: persona?.prompt,
    reasoningStart: effectiveReasoningTagStart,
    reasoningEnd: effectiveReasoningTagEnd,
    sessionVars: payload.sessionVars,
    globalVars: payload.globalVars,
    charId: char.id,
    sessionId: '',
    summaryContent: payload.summaryContent,
    guidanceText: payload.guidanceText,
    macroName: char.macroName,
    memoryContent: payload.memoryMacroContent,
    arcContent: payload.arcContent,
    entitiesContent: payload.entitiesContent,
    studioSessionState: payload.studioSessionStateContent,
  );

  var currentSessionVars = Map<String, String>.from(payload.sessionVars);
  var currentGlobalVars = Map<String, String>.from(payload.globalVars);
  var currentMacroCtx = macroCtx;
  final notifyObj = NotifyObj();

  final depthBlocks = <_ResolvedDepthBlock>[];
  final relativeBlocks = <_ResolvedRelativeBlock>[];

  final visibleHistory = payload.history
      .where((m) => !m.isHidden && !m.isTyping)
      .toList();
  final deferMemoryMacro = payload.memorySelection != null;

  final loreEntries =
      payload.preScannedEntries ??
      scanLorebooks(
        history: visibleHistory,
        char: char,
        textToScan:
            visibleHistory.where((m) => m.role == 'user').lastOrNull?.content ??
            '',
        chatId: payload.sessionId,
        lorebooks: payload.lorebooks,
        globalSettings: payload.lorebookSettings,
        activations: payload.lorebookActivations,
        applyPerBookLimits: false,
      );

  final mergedEntries = mergeKeywordVector(
    keywordEntries: loreEntries,
    vectorEntries: payload.vectorEntries,
    settings: payload.lorebookSettings,
  );

  final keywordIdToEntry = <String, ScannedEntry>{};
  for (final e in loreEntries) {
    keywordIdToEntry[e.id] = e;
  }
  final coverageKeywordIdToEntry = <String, CoverageEntry>{};
  if (payload.lorebookSettings.searchType != 'vector') {
    final coverage = computeLorebookCoverage(
      history: visibleHistory,
      char: char,
      textToScan:
          visibleHistory.where((m) => m.role == 'user').lastOrNull?.content ??
          '',
      chatId: payload.sessionId,
      lorebooks: payload.lorebooks,
      globalSettings: payload.lorebookSettings,
      activations: payload.lorebookActivations,
    );
    for (final e in coverage.entries) {
      final isKeywordLike =
          e.constant ||
          (e.activated &&
              e.matchedKeys.isNotEmpty &&
              !e.matchedKeys.contains('[vector]'));
      if (isKeywordLike) coverageKeywordIdToEntry[e.id] = e;
    }
  }
  final vectorIdToEntry = <String, LorebookEntry>{};
  for (final e in payload.vectorEntries) {
    vectorIdToEntry[e.id] = e;
  }

  final triggeredLorebooks = <TriggeredEntry>[];
  for (final merged in mergedEntries) {
    final kw = keywordIdToEntry[merged.id];
    if (kw != null) {
      triggeredLorebooks.add(
        TriggeredEntry(
          id: kw.id,
          name: kw.comment.isNotEmpty ? kw.comment : kw.id,
          lorebookName: kw.lorebookName,
          lorebookId: kw.lorebookId,
          source: kw.constant ? 'constant' : 'keyword',
        ),
      );
      continue;
    }
    final coverageKw = coverageKeywordIdToEntry[merged.id];
    if (coverageKw != null) {
      triggeredLorebooks.add(
        TriggeredEntry(
          id: coverageKw.id,
          name: coverageKw.comment.isNotEmpty
              ? coverageKw.comment
              : coverageKw.id,
          lorebookName: coverageKw.lorebookName,
          lorebookId: coverageKw.lorebookId,
          source: coverageKw.constant ? 'constant' : 'keyword',
        ),
      );
      continue;
    }
    final vec = vectorIdToEntry[merged.id];
    if (vec != null) {
      triggeredLorebooks.add(
        TriggeredEntry(
          id: vec.id,
          name: vec.comment.isNotEmpty ? vec.comment : vec.id,
          source: 'vector',
        ),
      );
    }
  }

  final classified = _classifyLorebooks(
    mergedEntries,
    currentMacroCtx,
    payload.lorebookSettings,
  );
  final loreBefore = classified.loreBefore;
  final loreAfter = classified.loreAfter;
  final macroLoreContent = classified.loreMacroBuffer.join('\n\n');

  // Apply char-field injections: prepend constant lore entries to the corresponding
  // MacroContext field so that {{scenario}}, {{personality}}, {{description}} macros
  // expand with the prepended content everywhere in the preset.
  String? patchedScenario = currentMacroCtx.charScenario;
  String? patchedPersonality = currentMacroCtx.charPersonality;
  String? patchedDescription = currentMacroCtx.charDescription;

  if (classified.loreScenario.isNotEmpty) {
    final prefix = classified.loreScenario.join('\n\n');
    patchedScenario = patchedScenario != null && patchedScenario.isNotEmpty
        ? '$prefix\n\n$patchedScenario'
        : prefix;
  }
  if (classified.lorePersonality.isNotEmpty) {
    final prefix = classified.lorePersonality.join('\n\n');
    patchedPersonality =
        patchedPersonality != null && patchedPersonality.isNotEmpty
        ? '$prefix\n\n$patchedPersonality'
        : prefix;
  }
  if (classified.loreDescription.isNotEmpty) {
    final prefix = classified.loreDescription.join('\n\n');
    patchedDescription =
        patchedDescription != null && patchedDescription.isNotEmpty
        ? '$prefix\n\n$patchedDescription'
        : prefix;
  }

  // Populate lorebooksContent in MacroContext so macro_engine can expand {{lorebooks}}
  // inline at the exact position of the placeholder inside any preset block.
  currentMacroCtx = currentMacroCtx.copyWith(
    lorebooksContent: macroLoreContent,
    memoryContent: deferMemoryMacro ? _deferredMemoryPlaceholder : null,
    charScenario: patchedScenario,
    charPersonality: patchedPersonality,
    charDescription: patchedDescription,
  );

  for (final rawBlock in preset.blocks) {
    final id = normalizeBlockId(rawBlock.id);
    if (!rawBlock.enabled || rawBlock.isStashed) continue;

    final resolved = resolveBlockContent(
      id: id,
      rawContent: rawBlock.content,
      role: rawBlock.role,
      char: char,
      persona: persona,
      macroCtx: currentMacroCtx,
      sessionVars: currentSessionVars,
      globalVars: currentGlobalVars,
      notifyObj: notifyObj,
      summaryContent: payload.summaryContent,
      // Prefix is a per-preset setting on the summary block (falls back to the
      // runtime payload value, then the resolver default).
      summaryPrefix: rawBlock.prefix ?? payload.summaryPrefix,
      authorsNote: payload.authorsNote,
    );

    if (notifyObj.varsChanged) {
      currentSessionVars = Map<String, String>.from(notifyObj.sessionVars);
      currentGlobalVars = Map<String, String>.from(notifyObj.globalVars);
      currentMacroCtx = currentMacroCtx.copyWith(
        sessionVars: currentSessionVars,
        globalVars: currentGlobalVars,
      );
      notifyObj.varsChanged = false;
    }

    if (resolved == null) continue;

    final blockIsSummary =
        id == 'summary' || rawBlock.content.contains('{{summary}}');

    // Author's Note is positioned like any other block: its depth / insertion
    // mode come from the preset block (per-preset), while content and role are
    // injected from the chat session by resolveBlockContent. So it falls
    // through to the generic depth/relative handling below.
    if (rawBlock.insertionMode == 'depth' && id != 'chat_history') {
      depthBlocks.add(
        _ResolvedDepthBlock(
          id: id,
          role: resolved.role,
          content: resolved.content,
          depth: rawBlock.depth ?? 0,
          isSummary: blockIsSummary,
        ),
      );
    } else {
      relativeBlocks.add(
        _ResolvedRelativeBlock(
          id: id,
          name: rawBlock.name,
          role: resolved.role,
          content: resolved.content,
          contentForAccounting: resolved.contentForAccounting,
          isSummary: blockIsSummary,
          appendToLastMessage: rawBlock.appendToLastMessage,
        ),
      );
    }
  }

  if (payload.characterDepthPrompt.isNotEmpty) {
    final dpContent = replaceMacros(
      payload.characterDepthPrompt,
      currentMacroCtx,
    ).text;
    if (dpContent.trim().isNotEmpty) {
      depthBlocks.add(
        _ResolvedDepthBlock(
          id: 'char_depth_prompt',
          role: payload.characterDepthPromptRole.isNotEmpty
              ? payload.characterDepthPromptRole
              : 'system',
          content: dpContent,
          depth: payload.characterDepthPromptDepth,
        ),
      );
    }
  }

  for (final block in payload.runtimePromptBlocks) {
    final content = replaceMacros(block.content, currentMacroCtx).text.trim();
    if (content.isEmpty) continue;
    depthBlocks.add(
      _ResolvedDepthBlock(
        id: 'runtime_prompt:${block.id}',
        role: block.role.isNotEmpty ? block.role : 'system',
        content: content,
        depth: block.depth,
      ),
    );
  }

  final macroTokens = <String, int>{};
  if (currentMacroCtx.lorebooksContent != null &&
      currentMacroCtx.lorebooksContent!.isNotEmpty) {
    macroTokens['lorebooks'] = estimateTokens(
      currentMacroCtx.lorebooksContent!,
    );
  }
  if (currentMacroCtx.summaryContent != null &&
      currentMacroCtx.summaryContent!.isNotEmpty) {
    macroTokens['summary'] = estimateTokens(currentMacroCtx.summaryContent!);
  }
  if (currentMacroCtx.memoryContent != null &&
      currentMacroCtx.memoryContent!.isNotEmpty) {
    macroTokens['memory'] =
        currentMacroCtx.memoryContent == _deferredMemoryPlaceholder
        ? 0
        : estimateTokens(currentMacroCtx.memoryContent!);
  }
  if (currentMacroCtx.charDescription != null &&
      currentMacroCtx.charDescription!.isNotEmpty) {
    macroTokens['description'] = estimateTokens(
      currentMacroCtx.charDescription!,
    );
  }
  if (currentMacroCtx.charPersonality != null &&
      currentMacroCtx.charPersonality!.isNotEmpty) {
    macroTokens['personality'] = estimateTokens(
      currentMacroCtx.charPersonality!,
    );
  }
  if (currentMacroCtx.charScenario != null &&
      currentMacroCtx.charScenario!.isNotEmpty) {
    macroTokens['scenario'] = estimateTokens(currentMacroCtx.charScenario!);
  }
  if (currentMacroCtx.personaPrompt != null &&
      currentMacroCtx.personaPrompt!.isNotEmpty) {
    macroTokens['persona'] = estimateTokens(currentMacroCtx.personaPrompt!);
  }
  if (currentMacroCtx.charMesExample != null &&
      currentMacroCtx.charMesExample!.isNotEmpty) {
    macroTokens['mesExamples'] = estimateTokens(
      currentMacroCtx.charMesExample!,
    );
  }

  return _assembleMessages(
    relativeBlocks: relativeBlocks,
    depthBlocks: depthBlocks,
    loreBefore: loreBefore,
    loreAfter: loreAfter,
    history: payload.history,
    macroCtx: currentMacroCtx,
    currentSessionVars: currentSessionVars,
    currentGlobalVars: currentGlobalVars,
    preset: preset,
    payload: payload,
    char: char,
    persona: persona,
    triggeredLorebooks: triggeredLorebooks,
    triggeredMemories: payload.triggeredMemories,
    macroTokens: macroTokens,
  );
}

int _calculateLorebookReserve(PromptPayload payload) {
  final settings = payload.lorebookSettings;
  if (settings.reserveValue <= 0) return 0;
  if (settings.reserveMode == 'percent') {
    return (payload.apiConfig.contextSize * settings.reserveValue / 100)
        .round();
  }
  return settings.reserveValue;
}

({
  List<PromptMessage> loreBefore,
  List<PromptMessage> loreAfter,
  List<String> loreMacroBuffer,
  List<String> loreScenario,
  List<String> lorePersonality,
  List<String> loreDescription,
})
_classifyLorebooks(
  List<LorebookEntry> entries,
  MacroContext macroCtx,
  LorebookGlobalSettings settings,
) {
  final loreBefore = <PromptMessage>[];
  final loreAfter = <PromptMessage>[];
  final loreMacroBuffer = <String>[];
  final loreScenario = <String>[];
  final lorePersonality = <String>[];
  final loreDescription = <String>[];

  for (final entry in entries) {
    var content = replaceMacros(entry.content, macroCtx).text;
    if (content.trim().isEmpty) continue;

    final pos = entry.position == 'matchGlobal'
        ? settings.injectionPosition
        : entry.position;

    if (pos == 'charScenario') {
      loreScenario.add(content);
    } else if (pos == 'charPersonality') {
      lorePersonality.add(content);
    } else if (pos == 'charDescription') {
      loreDescription.add(content);
    } else if (pos == 'lorebooksMacro') {
      loreMacroBuffer.add(content);
    } else if (pos == 'worldInfoAfter') {
      loreAfter.add(
        PromptMessage(
          role: 'system',
          content: content,
          isLorebook: true,
          blockId: 'worldInfoAfter',
          blockName:
              'Lorebook: ${entry.comment.isNotEmpty ? entry.comment : entry.id}',
        ),
      );
    } else {
      loreBefore.add(
        PromptMessage(
          role: 'system',
          content: content,
          isLorebook: true,
          blockId: 'worldInfoBefore',
          blockName:
              'Lorebook: ${entry.comment.isNotEmpty ? entry.comment : entry.id}',
        ),
      );
    }
  }
  return (
    loreBefore: loreBefore,
    loreAfter: loreAfter,
    loreMacroBuffer: loreMacroBuffer,
    loreScenario: loreScenario,
    lorePersonality: lorePersonality,
    loreDescription: loreDescription,
  );
}

PromptResult _assembleMessages({
  required List<_ResolvedRelativeBlock> relativeBlocks,
  required List<_ResolvedDepthBlock> depthBlocks,
  required List<PromptMessage> loreBefore,
  required List<PromptMessage> loreAfter,
  required List<ChatMessage> history,
  required MacroContext macroCtx,
  required Map<String, String> currentSessionVars,
  required Map<String, String> currentGlobalVars,
  required Preset preset,
  required PromptPayload payload,
  required Character char,
  Persona? persona,
  List<TriggeredEntry> triggeredLorebooks = const [],
  List<TriggeredEntry> triggeredMemories = const [],
  Map<String, int> macroTokens = const {},
}) {
  final messages = <PromptMessage>[];
  final attributionBlocks = <StaticBlock>[];
  String? mergeBuffer;
  String? mergeRole;

  final resolvedDepthMsgs = depthBlocks
      .map(
        (b) => PromptMessage(
          role: b.role,
          content: b.content,
          blockId: b.id,
          depth: b.depth,
          isDepth: true,
          isSummary: b.isSummary,
        ),
      )
      .toList();

  // Track whether loreBefore/loreAfter were injected via char_card trigger.
  // If the preset has no char_card block, they fall through to the end.
  bool loreBeforeInjected = false;
  bool loreAfterInjected = false;

  void injectLoreBefore() {
    if (loreBeforeInjected || loreBefore.isEmpty) return;
    final combined = loreBefore.map((e) => e.content).join('\n\n');
    messages.add(
      PromptMessage(
        role: 'system',
        content: combined,
        isLorebook: true,
        blockId: 'worldInfoBefore',
        blockName: 'Lorebook (Before)',
      ),
    );
    attributionBlocks.add(
      StaticBlock(id: 'worldInfoBefore', content: combined),
    );
    loreBeforeInjected = true;
  }

  void injectLoreAfter() {
    if (loreAfterInjected || loreAfter.isEmpty) return;
    final combined = loreAfter.map((e) => e.content).join('\n\n');
    messages.add(
      PromptMessage(
        role: 'system',
        content: combined,
        isLorebook: true,
        blockId: 'worldInfoAfter',
        blockName: 'Lorebook (After)',
      ),
    );
    attributionBlocks.add(StaticBlock(id: 'worldInfoAfter', content: combined));
    loreAfterInjected = true;
  }

  // Collect blocks with appendToLastMessage set. Macros are already expanded
  // in block.content at this point (resolveBlockContent ran in buildPrompt
  // before relativeBlocks was built). See docs/INVARIANTS.md INV-PSx.
  final appendedEntries = <_ResolvedRelativeBlock>[];
  for (final block in relativeBlocks) {
    if (block.id == 'chat_history') continue;
    if (!block.appendToLastMessage) continue;
    if (block.content.trim().isEmpty) continue;
    appendedEntries.add(block);
  }

  for (final block in relativeBlocks) {
    // worldInfoBefore injects just before char_card (mirrors JS generationWorker.js:739)
    if (block.id == 'char_card') injectLoreBefore();

    if (block.id == 'chat_history') {
      if (mergeBuffer != null) {
        messages.add(
          PromptMessage(
            role: mergeRole ?? 'system',
            blockId: 'preset',
            content: mergeBuffer,
          ),
        );
        mergeBuffer = null;
      }
      // worldInfoAfter injects just before chat_history (mirrors JS generationWorker.js:680)
      injectLoreAfter();

      final historyMacroCtx = MacroContext(
        charName: macroCtx.charName,
        charDescription: macroCtx.charDescription,
        charScenario: macroCtx.charScenario,
        charPersonality: macroCtx.charPersonality,
        charMesExample: macroCtx.charMesExample,
        userName: macroCtx.userName,
        personaPrompt: macroCtx.personaPrompt,
        reasoningStart: macroCtx.reasoningStart,
        reasoningEnd: macroCtx.reasoningEnd,
        sessionVars: currentSessionVars,
        globalVars: currentGlobalVars,
        charId: macroCtx.charId,
        sessionId: macroCtx.sessionId,
        macroName: macroCtx.macroName,
      );
      final historyMsgs = HistoryAssembler(historyMacroCtx).assemble(history);
      final appendedForHistory = appendedEntries
          .map((b) => (name: b.name, content: b.content))
          .toList();
      applyAppendToLastMessage(historyMsgs, appendedForHistory);
      messages.addAll(
        interleaveDepthWithHistory(historyMsgs, resolvedDepthMsgs),
      );
      for (final db in resolvedDepthMsgs) {
        attributionBlocks.add(
          StaticBlock(id: db.blockId ?? 'preset', content: db.content),
        );
      }
    } else {
      final content = block.content.trim();
      final accountingContent = block.contentForAccounting.trim();

      // setvar-only blocks: no LLM-visible text, but definitions count toward preset.
      if (content.isEmpty) {
        if (accountingContent.isNotEmpty) {
          attributionBlocks.add(
            StaticBlock(id: block.id, content: accountingContent),
          );
        }
        if (block.id == 'char_card') injectLoreAfter();
        continue;
      }

      // attributionBlocks feed the token breakdown. We pass the
      // "accounting" content (dynamic macros blanked out) so that the
      // preset's static chrome is attributed to sourceTokens['preset']
      // and NOT double-counted under sourceTokens['memory'] /
      // sourceTokens['summary'] / sourceTokens['lorebooks']. The
      // dynamic injections are counted separately via dedicated
      // StaticBlocks (hard-block injection) and macroTokens.
      attributionBlocks.add(
        StaticBlock(id: block.id, content: accountingContent),
      );

      // appendToLastMessage blocks are merged into the last user message in
      // applyAppendToLastMessage (see appendedEntries above). They must NOT
      // also be added to messages here — that would send the same content
      // twice. See docs/INVARIANTS.md INV-PS9.
      if (block.appendToLastMessage) continue;

      if (preset.mergePrompts && block.role != 'assistant') {
        if (mergeBuffer != null) {
          mergeBuffer = '$mergeBuffer\n\n$content';
        } else {
          mergeBuffer = content;
          mergeRole = preset.mergeRole;
        }
      } else {
        if (mergeBuffer != null) {
          messages.add(
            PromptMessage(
              role: mergeRole ?? 'system',
              blockId: 'preset',
              content: mergeBuffer,
            ),
          );
          mergeBuffer = null;
        }
        messages.add(
          PromptMessage(
            role: block.role,
            blockId: block.id,
            blockName: block.name,
            content: content,
            isSummary: block.isSummary,
          ),
        );
      }

      // worldInfoAfter injects just after char_card (mirrors JS generationWorker.js:792)
      if (block.id == 'char_card') injectLoreAfter();
    }
  }

  // Fallback: if preset had no char_card block, inject remaining lore at the end
  injectLoreBefore();
  injectLoreAfter();
  if (mergeBuffer != null) {
    messages.add(
      PromptMessage(
        role: mergeRole ?? 'system',
        blockId: 'preset',
        content: mergeBuffer,
      ),
    );
  }

  // Memory block injection.
  // - payload.memoryContent set, payload.memorySelection == null:
  //     legacy path — inject hard block before cutoff. Source-window
  //     exclusion has already been applied (or wasn't requested) by
  //     whichever upstream producer assembled the content.
  // - payload.memorySelection set:
  //     defer injection until after the cutoff is known, then refilter
  //     against the visible window. The block is injected as a deferred
  //     marker so attributionBlocks and the message list stay consistent.
  final hasDeferredMemorySelection = payload.memorySelection != null;

  if (!hasDeferredMemorySelection &&
      payload.memoryContent != null &&
      payload.memoryContent!.isNotEmpty) {
    if (payload.memoryInjectionTarget == 'hard_block') {
      // Skip the hard block if the preset already handles memory via
      // {{memory}} macro or via an explicit `id: 'memory'` block.
      // (See docs/INVARIANTS.md INV-PS5.)
      final hasMemoryBlock =
          messages.any((m) => m.blockId == 'memory') ||
          appendedEntries.any((b) => b.id == 'memory');
      if (!hasMemoryBlock) {
        _injectMemoryBlock(messages, attributionBlocks, payload.memoryContent!);
      }
    }
    // 'macro' target: skip hard block, user must place {{memory}} in preset
  }

  // Studio Session State: inject <studio_session_state> canon block so
  // the LLM sees committed entity/relationship/arc/world state overriding
  // character-card baseline. Placed before recalled_messages so it has
  // higher authority in the context window.
  // See docs/plans/PLAN_STUDIO_LEDGER_MEMORY.md §Prompt Injection.
  if (payload.studioSessionStateContent != null &&
      payload.studioSessionStateContent!.isNotEmpty) {
    _injectStudioSessionStateBlock(
      messages,
      attributionBlocks,
      payload.studioSessionStateContent!,
    );
  }

  final lorebookReserve = _calculateLorebookReserve(payload);

  // Count vector-only tokens so the tokenizer can show "Vector Lorebook" as
  // its own row. Without this, vector entries silently inflate the
  // "Lorebook Reserve" row (which is computed as reserve minus keyword+macro
  // usage) and the user can never see how much vector lore was actually
  // injected. We approximate the actual payload bytes by joining the
  // content of every vector entry — the merge with keyword dedups at most
  // maxInjectedEntries, and the user-visible goal is "see vector lore in
  // flight", not an exact budget.
  final vectorContent = payload.vectorEntries
      .map((e) => e.content)
      .join('\n\n');
  final vectorLoreTokens = vectorContent.isEmpty
      ? 0
      : estimateTokens(vectorContent);

  final calculator = ContextCalculator(
    contextSize: payload.apiConfig.contextSize,
    maxTokens: payload.apiConfig.maxTokens,
  );
  var historyOnly = messages.where((m) => m.isHistory).toList();

  var breakdown = calculator.calculate(
    staticBlocks: attributionBlocks,
    historyMessages: historyOnly,
    lorebookReserveTokens: lorebookReserve,
    macroTokens: macroTokens,
    vectorLoreTokens: vectorLoreTokens,
  );

  // Inject <recalled_messages> after the first cutoff calculation so raw
  // message recall can exclude chunks whose source messages are already
  // visible in the active history window. Studio supplies an explicit source
  // window; non-Studio uses the calculated token cutoff window.
  final recallVisibleMessageIds =
      payload.sourceWindowVisibleMessageIds.isNotEmpty
      ? payload.sourceWindowVisibleMessageIds
      : breakdown.visibleMessageIds;
  final recalledMessagesContent = effectiveRecalledMessagesContent(
    payload,
    visibleMessageIds: recallVisibleMessageIds,
  );
  if (recalledMessagesContent != null && recalledMessagesContent.isNotEmpty) {
    _injectRecalledMessagesBlock(
      messages,
      attributionBlocks,
      recalledMessagesContent,
    );
    historyOnly = messages.where((m) => m.isHistory).toList();
    breakdown = calculator.calculate(
      staticBlocks: attributionBlocks,
      historyMessages: historyOnly,
      lorebookReserveTokens: lorebookReserve,
      macroTokens: macroTokens,
      vectorLoreTokens: vectorLoreTokens,
    );
  }
  var finalMemorySelection = payload.memorySelection;
  MemoryExcerptSelection? finalExcerptSelection;
  var memoryMacroMissing = false;

  // Deferred memory finalization: refilter the v2 selection against the
  // visible window now that the cutoff is known, then inject the hard
  // block and update the breakdown with the post-cutoff memory cost.
  if (hasDeferredMemorySelection && payload.memorySelection != null) {
    final result = _finalizeDeferredMemory(
      payload: payload,
      baseBreakdown: breakdown,
      messages: messages,
      appendedEntries: appendedEntries,
      attributionBlocks: attributionBlocks,
      historyOnly: historyOnly,
      macroTokens: macroTokens,
      calculator: calculator,
      lorebookReserve: lorebookReserve,
      vectorLoreTokens: vectorLoreTokens,
    );
    breakdown = result.breakdown;
    finalMemorySelection = result.finalMemorySelection;
    finalExcerptSelection = result.finalExcerptSelection;
    memoryMacroMissing = result.memoryMacroMissing;
  }

  final finalMessages = <PromptMessage>[];
  var historySeen = 0;
  for (final msg in messages) {
    if (msg.isHistory) {
      if (historySeen >= breakdown.cutoffIndex) {
        // Use live history messages so deferred {{memory}} replacement on
        // appendToLastMessage blocks is not lost to a stale trimmed copy.
        finalMessages.add(msg);
      }
      historySeen++;
    } else if (msg.content.trim().isNotEmpty) {
      finalMessages.add(msg);
    }
  }

  final presetRegexes = preset.regexes.where((r) => !r.disabled).toList();
  final globalRegexes = payload.globalRegexes
      .where((r) => !r.disabled)
      .toList();
  final regexScripts = [...presetRegexes, ...globalRegexes];

  final finalMessagesWithRegex = regexScripts.isEmpty
      ? finalMessages
      : applyPromptRegexes(
          messages: finalMessages,
          char: char,
          persona: persona,
          sessionVars: currentSessionVars,
          globalVars: currentGlobalVars,
          regexScripts: regexScripts,
        );

  final finalMemoryCoverage = _finalizeMemoryCoverage(
    payload.memoryCoverage,
    finalMemorySelection,
    finalExcerptSelection,
    memoryMacroMissing: memoryMacroMissing,
  );

  return PromptResult(
    messages: finalMessagesWithRegex,
    breakdown: breakdown,
    sessionVars: currentSessionVars,
    globalVars: currentGlobalVars,
    triggeredLorebooks: triggeredLorebooks,
    triggeredMemories: triggeredMemories,
    memoryCoverage: finalMemoryCoverage,
  );
}

/// Result of deferred memory finalization. [messages], [attributionBlocks],
/// and [macroTokens] are mutated in place by the caller; this record returns
/// only the values that are reassigned.
class _DeferredMemoryResult {
  final TokenBreakdown breakdown;
  final MemorySelection? finalMemorySelection;
  final MemoryExcerptSelection? finalExcerptSelection;
  final bool memoryMacroMissing;

  const _DeferredMemoryResult({
    required this.breakdown,
    required this.finalMemorySelection,
    required this.finalExcerptSelection,
    required this.memoryMacroMissing,
  });
}

/// Refilters the v2 memory selection against the visible window now that the
/// cutoff is known, then injects the hard block (or replaces the deferred
/// `{{memory}}` macro placeholder) and recomputes the breakdown with the
/// post-cutoff memory cost.
///
/// Mutates [messages] (memory block insertion / placeholder replacement),
/// [attributionBlocks] (memory static block), and [macroTokens] (memory macro
/// token count) in place. Returns the updated breakdown and selections.
_DeferredMemoryResult _finalizeDeferredMemory({
  required PromptPayload payload,
  required TokenBreakdown baseBreakdown,
  required List<PromptMessage> messages,
  required List<_ResolvedRelativeBlock> appendedEntries,
  required List<StaticBlock> attributionBlocks,
  required List<PromptMessage> historyOnly,
  required Map<String, int> macroTokens,
  required ContextCalculator calculator,
  required int lorebookReserve,
  required int vectorLoreTokens,
}) {
  var breakdown = baseBreakdown;
  final selection = payload.memorySelection!;
  final visibleMessageIds = payload.sourceWindowVisibleMessageIds.isNotEmpty
      ? payload.sourceWindowVisibleMessageIds
      : breakdown.visibleMessageIds;
  final refiltered = _refilterMemorySelection(
    selection,
    visibleMessageIds: visibleMessageIds,
    chunkBudgeting: payload.memoryPackingMode == 'chunk_first',
    disableSourceWindowExclusion: payload.disableSourceWindowExclusion,
  );
  MemorySelection? finalMemorySelection = refiltered;
  MemoryExcerptSelection? finalExcerptSelection;
  var memoryMacroMissing = false;

  final useExcerptPacking =
      payload.memoryExcerptingEnabled ||
      payload.memoryPackingMode == 'chunk_first';
  final excerpted = !useExcerptPacking
      ? MemoryExcerptSelector.fullEntries(refiltered)
      : MemoryExcerptSelector.select(
          refiltered,
          packingMode: payload.memoryPackingMode,
          maxExcerptTokensPerEntry: payload.memoryExcerptTokensPerChunk,
          maxExcerptChunksPerEntry: payload.memoryExcerptChunksPerEntry,
          chunkFirstTopEntries: payload.chunkFirstTopEntries,
          chunkFirstTopChunks: payload.chunkFirstTopChunks,
        );
  finalExcerptSelection = excerpted;

  var historyMsgs = historyOnly;

  if (excerpted.items.isNotEmpty) {
    final rebuilt = _buildMemoryContentFromSelection(
      refiltered,
      excerptSelection: excerpted,
      summaryExcerpt: payload.summaryContent,
    );
    var memoryContent = rebuilt.content;
    var memoryMacroContent = rebuilt.macroContent;
    final replacedMacro = _replaceDeferredMemoryPlaceholders(
      messages,
      rebuilt.macroContent,
    );
    if (replacedMacro) {
      memoryContent = rebuilt.macroContent;
      memoryMacroContent = rebuilt.macroContent;
      historyMsgs = messages.where((m) => m.isHistory).toList(growable: false);
      macroTokens['memory'] = estimateTokens(memoryMacroContent);
    } else if (payload.memoryInjectionTarget == 'hard_block') {
      memoryContent = rebuilt.content;
      final hasMemoryBlock =
          messages.any((m) => m.blockId == 'memory') ||
          appendedEntries.any((b) => b.id == 'memory');
      if (!hasMemoryBlock) {
        _injectMemoryBlock(messages, attributionBlocks, rebuilt.content);
      }
    } else {
      // injectionTarget == 'macro' but the preset has no {{memory}}
      // placeholder, so the packed memory has nowhere to go and is dropped.
      final hasMemoryBlock =
          messages.any((m) => m.blockId == 'memory') ||
          appendedEntries.any((b) => b.id == 'memory');
      if (!hasMemoryBlock) {
        memoryMacroMissing = true;
      }
    }
    breakdown = _recomputeBreakdownWithMemory(
      calculator: calculator,
      baseBreakdown: breakdown,
      attributionBlocks: attributionBlocks,
      historyMessages: historyMsgs,
      lorebookReserveTokens: lorebookReserve,
      macroTokens: macroTokens,
      vectorLoreTokens: vectorLoreTokens,
      memoryContent: memoryContent,
      memoryMacroContent: memoryMacroContent,
      visibleMessageIds: visibleMessageIds,
    );
  } else if (refiltered.entries.isEmpty &&
      _shouldInjectFactualContinuityGuard(payload)) {
    const guard =
        'Factual continuity note: The latest user message may refer to older context, but no reliable Memory Book entry was selected. Do not invent specific past events; ask for clarification or answer only from visible chat context.';
    final hasMemoryBlock =
        messages.any((m) => m.blockId == 'memory') ||
        appendedEntries.any((b) => b.id == 'memory');
    if (!hasMemoryBlock) {
      _injectMemoryBlock(messages, attributionBlocks, guard);
    }
    breakdown = _recomputeBreakdownWithMemory(
      calculator: calculator,
      baseBreakdown: breakdown,
      attributionBlocks: attributionBlocks,
      historyMessages: historyMsgs,
      lorebookReserveTokens: lorebookReserve,
      macroTokens: macroTokens,
      vectorLoreTokens: vectorLoreTokens,
      memoryContent: guard,
      memoryMacroContent: '',
      visibleMessageIds: visibleMessageIds,
    );
  }

  return _DeferredMemoryResult(
    breakdown: breakdown,
    finalMemorySelection: finalMemorySelection,
    finalExcerptSelection: finalExcerptSelection,
    memoryMacroMissing: memoryMacroMissing,
  );
}

bool _shouldInjectFactualContinuityGuard(PromptPayload payload) {
  final diagnostics = payload.memoryCoverage['diagnostics'];
  if (diagnostics is! Map) return false;
  final active = diagnostics['factualContinuityGuardActive'] == true;
  final reliable = diagnostics['reliableCandidateFound'] == true;
  return active && !reliable;
}

void _injectMemoryBlock(
  List<PromptMessage> messages,
  List<StaticBlock> attributionBlocks,
  String content,
) {
  attributionBlocks.add(StaticBlock(id: 'memory', content: content));
  final memMsg = PromptMessage(
    role: 'system',
    content: content,
    blockId: 'memory',
    blockName: 'Memory Book',
  );
  final historyIdx = messages.indexWhere((m) => m.isHistory);
  if (historyIdx >= 0) {
    messages.insert(historyIdx, memMsg);
  } else {
    messages.add(memMsg);
  }
}

/// Injects the `<recalled_messages>` system block before the first history
/// message (and before the memory block, since this is called first). The
/// raw chunks are the lossless backstop for the lossy MemoryBook compression.
/// See docs/plans/PLAN_MEMORY_CONTINUITY.md §1.
void _injectRecalledMessagesBlock(
  List<PromptMessage> messages,
  List<StaticBlock> attributionBlocks,
  String content,
) {
  attributionBlocks.add(StaticBlock(id: 'recalled_messages', content: content));
  final recallMsg = PromptMessage(
    role: 'system',
    content: content,
    blockId: 'recalled_messages',
    blockName: 'Recalled Messages',
  );
  final historyIdx = messages.indexWhere((m) => m.isHistory);
  if (historyIdx >= 0) {
    messages.insert(historyIdx, recallMsg);
  } else {
    messages.add(recallMsg);
  }
}

/// Injects the `<studio_session_state>` system block before the first history
/// message so the LLM sees committed entity/relationship/arc/world canon state
/// overriding character-card baseline. Placed before recalled_messages to give
/// it higher context-window authority.
/// See docs/plans/PLAN_STUDIO_LEDGER_MEMORY.md §Prompt Injection.
void _injectStudioSessionStateBlock(
  List<PromptMessage> messages,
  List<StaticBlock> attributionBlocks,
  String content,
) {
  attributionBlocks.add(
    StaticBlock(id: 'studio_session_state', content: content),
  );
  final stateMsg = PromptMessage(
    role: 'system',
    content: content,
    blockId: 'studio_session_state',
    blockName: 'Studio Session State',
  );
  final historyIdx = messages.indexWhere((m) => m.isHistory);
  if (historyIdx >= 0) {
    messages.insert(historyIdx, stateMsg);
  } else {
    messages.add(stateMsg);
  }
}

/// Filters [PromptPayload.recalledMessageChunks] by the source-window
/// visibility override, then formats the surviving chunks into a
/// `<recalled_messages>` block. Falls back to
/// [PromptPayload.recalledMessagesContent] when no structured chunks exist.
///
/// When [PromptPayload.sourceWindowVisibleMessageIds] is non-empty, chunks
/// whose *any* [RecalledMessageChunk.messageIds] overlaps with it are
/// excluded (their content is already visible in the prompt history).
/// When empty, the base token-cutoff window is assumed to have already
/// filtered, so all chunks pass through.
@visibleForTesting
String? effectiveRecalledMessagesContent(
  PromptPayload payload, {
  Set<String>? visibleMessageIds,
}) {
  if (payload.recalledMessageChunks.isEmpty) {
    return payload.recalledMessagesContent;
  }
  final visible = visibleMessageIds ?? payload.sourceWindowVisibleMessageIds;
  final chunks = payload.disableSourceWindowExclusion || visible.isEmpty
      ? payload.recalledMessageChunks
      : payload.recalledMessageChunks
            .where(
              (chunk) =>
                  chunk.messageIds.isEmpty ||
                  !chunk.messageIds.any(visible.contains),
            )
            .toList(growable: false);
  if (chunks.isEmpty) return null;

  final block = StringBuffer();
  block.writeln('<recalled_messages>');
  block.writeln(
    'Semantically relevant raw message chunks from earlier in this chat. '
    'Do not explicitly reference "remembering" these — use them as ground '
    'truth context.',
  );
  for (final chunk in chunks) {
    final text = chunk.text.trim();
    if (text.isEmpty) continue;
    block.writeln('---');
    block.writeln(text);
  }
  block.writeln('</recalled_messages>');
  final content = block.toString().trim();
  return content == '<recalled_messages>\n</recalled_messages>'
      ? null
      : content;
}

/// Appends the contents of preset blocks with `appendToLastMessage = true` to
/// the last user-role history message. No-op when [historyMsgs] has no user
/// message or no appendable blocks. Macros in the block content must already
/// be expanded before this is called (handled in [buildPrompt]).
///
/// See docs/INVARIANTS.md INV-PS9 for the full contract.
@visibleForTesting
void applyAppendToLastMessage(
  List<PromptMessage> historyMsgs,
  List<({String name, String content})> appendedEntries,
) {
  if (appendedEntries.isEmpty || historyMsgs.isEmpty) return;

  final lastUserIdx = historyMsgs.lastIndexWhere(
    (m) => m.role == 'user' && m.isHistory,
  );
  if (lastUserIdx < 0) return;

  final original = historyMsgs[lastUserIdx];
  final joined = appendedEntries
      .map((b) => b.content.trim())
      .where((s) => s.isNotEmpty)
      .join('\n\n');
  if (joined.isEmpty) return;

  final blockNames = appendedEntries
      .map((b) => b.name.isNotEmpty ? b.name : 'block')
      .join(', ');

  historyMsgs[lastUserIdx] = PromptMessage(
    role: original.role,
    content: '${original.content}\n\n$joined',
    isHistory: true,
    blockName: '${original.blockName ?? 'Last user'} + $blockNames',
  );
}

class _RebuiltMemoryContent {
  final String content;
  final String macroContent;
  const _RebuiltMemoryContent(this.content, this.macroContent);
}

/// Refilter a [MemorySelection] against the visible-window message ids
/// returned by [TokenBreakdown]. Re-runs the selector with the new
/// exclusion set so anything whose `messageIds` overlaps the visible
/// history is dropped. Preserves the existing budget/cap unless the
/// selection carried them via [MemorySelection.budgetTokens]/entryCap.
MemorySelection _refilterMemorySelection(
  MemorySelection previous, {
  required Set<String> visibleMessageIds,
  bool chunkBudgeting = false,
  bool disableSourceWindowExclusion = false,
}) {
  if (previous.selectionMode == 'legacy') return previous;
  if (visibleMessageIds.isEmpty) return previous;
  final needsRefilter = previous.allScores.any(
    (s) =>
        !s.excludedBySourceWindow &&
        s.entry.messageIds.isNotEmpty &&
        s.entry.messageIds.any(visibleMessageIds.contains),
  );
  if (!needsRefilter) return previous;
  return MemorySelector.select(
    MemorySelectionInput(
      selectionMode: previous.selectionMode,
      entries: previous.allScores.map((s) => s.entry).toList(),
      keywordMatchedTerms: {
        for (final score in previous.allScores)
          if (score.matchedKeys.isNotEmpty) score.entry.id: score.matchedKeys,
      },
      visibleMessageIds: visibleMessageIds,
      maxInjectionTokens: previous.budgetTokens,
      maxInjectedEntries: previous.entryCap > 0
          ? previous.entryCap
          : previous.entries.length,
      sourceWindowExclusion: !disableSourceWindowExclusion,
      diversityAware: false,
      chunkBudgeting: chunkBudgeting,
    ),
  );
}

_RebuiltMemoryContent _buildMemoryContentFromSelection(
  MemorySelection selection, {
  MemoryExcerptSelection? excerptSelection,
  String? summaryExcerpt,
}) {
  final injected = excerptSelection ?? MemoryExcerptSelector.select(selection);
  final macro = formatMemoryItems(injected.items, includeContextHeader: false);
  final parts = <String>[];
  if (summaryExcerpt != null && summaryExcerpt.isNotEmpty) {
    parts.add('Summary excerpt:\n$summaryExcerpt');
  }
  parts.add(formatMemoryItems(injected.items, includeContextHeader: true));
  return _RebuiltMemoryContent(parts.join('\n\n'), macro);
}

bool _replaceDeferredMemoryPlaceholders(
  List<PromptMessage> messages,
  String memoryContent,
) {
  var replaced = false;
  for (var i = 0; i < messages.length; i++) {
    final message = messages[i];
    if (!message.content.contains(_deferredMemoryPlaceholder)) continue;
    messages[i] = PromptMessage(
      role: message.role,
      content: message.content.replaceAll(
        _deferredMemoryPlaceholder,
        memoryContent,
      ),
      blockId: message.blockId,
      depth: message.depth,
      isHistory: message.isHistory,
      isDepth: message.isDepth,
      isLorebook: message.isLorebook,
      isSummary: message.isSummary,
      blockName: message.blockName,
      sourceMessageId: message.sourceMessageId,
    );
    replaced = true;
  }
  return replaced;
}

Map<String, dynamic> _finalizeMemoryCoverage(
  Map<String, dynamic> coverage,
  MemorySelection? selection,
  MemoryExcerptSelection? excerptSelection, {
  bool memoryMacroMissing = false,
}) {
  if (selection == null) {
    if (memoryMacroMissing) {
      return {...coverage, 'memoryMacroMissing': true};
    }
    return coverage;
  }
  final packingMode = coverage['packingMode'] as String? ?? 'hybrid';
  final tokensPerChunk =
      coverage['excerptTokensPerChunk'] as int? ??
      defaultMemoryExcerptTokensPerEntry;
  final chunksPerEntry =
      coverage['excerptChunksPerEntry'] as int? ??
      defaultMemoryExcerptChunksPerEntry;
  final excerpted =
      excerptSelection ??
      MemoryExcerptSelector.select(
        selection,
        packingMode: packingMode,
        maxExcerptTokensPerEntry: tokensPerChunk,
        maxExcerptChunksPerEntry: chunksPerEntry,
      );
  final budget = MemoryBudgetBreakdown(
    effectiveTokens: selection.budgetTokens,
    source: selection.budgetTokens == null ? 'none' : 'effective',
  );
  final diagnostics = MemoryDiagnostics.fromSelection(
    selection,
    budget: budget,
    excerptSelection: excerpted,
    excerptTokensPerChunk: tokensPerChunk,
  ).toJson();
  // The card reads diagnostics directly, so embed the warning there too.
  diagnostics['memoryMacroMissing'] = memoryMacroMissing;
  return {
    ...coverage,
    'packingMode': packingMode,
    'excerptTokensPerChunk': tokensPerChunk,
    'excerptChunksPerEntry': chunksPerEntry,
    'entryIds': excerpted.entries.map((e) => e.id).toList(growable: false),
    'budgetTrimmed': excerpted.budgetTrimmed,
    'memoryMacroMissing': memoryMacroMissing,
    'diagnostics': diagnostics,
  };
}

/// Recompute a [TokenBreakdown] after the memory block is finalized so
/// `memoryTokens` / `historyBudget` / `totalTokens` / `visibleMessageIds`
/// all reflect the post-cutoff state.
TokenBreakdown _recomputeBreakdownWithMemory({
  required ContextCalculator calculator,
  required TokenBreakdown baseBreakdown,
  required List<StaticBlock> attributionBlocks,
  required List<PromptMessage> historyMessages,
  required int lorebookReserveTokens,
  required Map<String, int> macroTokens,
  required int vectorLoreTokens,
  required String memoryContent,
  required String memoryMacroContent,
  required Set<String> visibleMessageIds,
}) {
  // Strip the memory block from attributionBlocks — ContextCalculator
  // would double-count the content otherwise (we pass it explicitly as
  // memoryTokens below).
  final filteredBlocks = attributionBlocks
      .where((b) => b.id != 'memory')
      .toList(growable: false);
  final memoryTokens = estimateTokens(memoryContent);
  return calculator
      .calculate(
        staticBlocks: filteredBlocks,
        historyMessages: historyMessages,
        lorebookReserveTokens: lorebookReserveTokens,
        macroTokens: macroTokens,
        memoryTokens: memoryTokens,
        vectorLoreTokens: vectorLoreTokens,
      )
      .copyWithVisible(visibleMessageIds);
}
