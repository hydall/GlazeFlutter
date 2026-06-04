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
import 'lorebook_scanner.dart';
import 'lorebook_merger.dart';
import 'prompt_block_resolver.dart';
import 'fallback_prompt_builder.dart';
import 'regex_service.dart';
import 'tokenizer.dart';

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

  const PromptPayload({
    required this.character,
    this.persona,
    this.preset,
    required this.history,
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
  });
}

class PromptResult {
  final List<PromptMessage> messages;
  final TokenBreakdown breakdown;
  final Map<String, String> sessionVars;
  final Map<String, String> globalVars;
  final List<TriggeredEntry> triggeredLorebooks;
  final List<TriggeredEntry> triggeredMemories;

  const PromptResult({
    required this.messages,
    required this.breakdown,
    required this.sessionVars,
    required this.globalVars,
    this.triggeredLorebooks = const [],
    this.triggeredMemories = const [],
  });

  Map<String, dynamic> toJson() => {
    'messages': messages.map((m) => m.toJson()).toList(),
    'breakdown': breakdown.toJson(),
    'sessionVars': sessionVars,
    'globalVars': globalVars,
    'triggeredLorebooks': triggeredLorebooks.map((t) => t.toJson()).toList(),
    'triggeredMemories': triggeredMemories.map((t) => t.toJson()).toList(),
  };

  factory PromptResult.fromJson(Map<String, dynamic> json) => PromptResult(
    messages: (json['messages'] as List).map((m) => PromptMessage.fromJson(m as Map<String, dynamic>)).toList(),
    breakdown: TokenBreakdown.fromJson(json['breakdown'] as Map<String, dynamic>),
    sessionVars: Map<String, String>.from(json['sessionVars'] as Map),
    globalVars: Map<String, String>.from(json['globalVars'] as Map),
    triggeredLorebooks: (json['triggeredLorebooks'] as List? ?? []).map((t) => TriggeredEntry.fromJson(t as Map<String, dynamic>)).toList(),
    triggeredMemories: (json['triggeredMemories'] as List? ?? []).map((t) => TriggeredEntry.fromJson(t as Map<String, dynamic>)).toList(),
  );
}

class _ResolvedDepthBlock {
  final String id;
  final String role;
  final String content;
  final int depth;
  final bool isSummary;
  const _ResolvedDepthBlock({required this.id, required this.role, required this.content, required this.depth, this.isSummary = false});
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
  );

  var currentSessionVars = Map<String, String>.from(payload.sessionVars);
  var currentGlobalVars = Map<String, String>.from(payload.globalVars);
  var currentMacroCtx = macroCtx;
  final notifyObj = NotifyObj();

  final depthBlocks = <_ResolvedDepthBlock>[];
  final relativeBlocks = <_ResolvedRelativeBlock>[];

  final visibleHistory = payload.history.where((m) => !m.isHidden && !m.isTyping).toList();

  final loreEntries = payload.preScannedEntries ?? scanLorebooks(
    history: visibleHistory,
    char: char,
    textToScan: visibleHistory.where((m) => m.role == 'user').lastOrNull?.content ?? '',
    chatId: null,
    lorebooks: payload.lorebooks,
    globalSettings: payload.lorebookSettings,
    activations: payload.lorebookActivations,
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
  final vectorIdToEntry = <String, LorebookEntry>{};
  for (final e in payload.vectorEntries) {
    vectorIdToEntry[e.id] = e;
  }

  final triggeredLorebooks = <TriggeredEntry>[];
  for (final merged in mergedEntries) {
    final kw = keywordIdToEntry[merged.id];
    if (kw != null) {
      triggeredLorebooks.add(TriggeredEntry(
        id: kw.id,
        name: kw.comment.isNotEmpty ? kw.comment : kw.id,
        lorebookName: kw.lorebookName,
        lorebookId: kw.lorebookId,
        source: kw.constant ? 'constant' : 'keyword',
      ));
      continue;
    }
    final vec = vectorIdToEntry[merged.id];
    if (vec != null) {
      triggeredLorebooks.add(TriggeredEntry(
        id: vec.id,
        name: vec.comment.isNotEmpty ? vec.comment : vec.id,
        source: 'vector',
      ));
    }
  }

  final classified = _classifyLorebooks(mergedEntries, currentMacroCtx, payload.lorebookSettings);
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
    patchedPersonality = patchedPersonality != null && patchedPersonality.isNotEmpty
        ? '$prefix\n\n$patchedPersonality'
        : prefix;
  }
  if (classified.loreDescription.isNotEmpty) {
    final prefix = classified.loreDescription.join('\n\n');
    patchedDescription = patchedDescription != null && patchedDescription.isNotEmpty
        ? '$prefix\n\n$patchedDescription'
        : prefix;
  }

  // Populate lorebooksContent in MacroContext so macro_engine can expand {{lorebooks}}
  // inline at the exact position of the placeholder inside any preset block.
  currentMacroCtx = currentMacroCtx.copyWith(
    lorebooksContent: macroLoreContent,
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
      summaryPrefix: payload.summaryPrefix,
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

    final blockIsSummary = id == 'summary' || rawBlock.content.contains('{{summary}}');

    if (id == 'authors_note' && payload.authorsNote != null) {
      final anMode = payload.authorsNote!.insertionMode.isNotEmpty
          ? payload.authorsNote!.insertionMode
          : rawBlock.insertionMode;
      final anDepth = payload.authorsNote!.depth > 0
          ? payload.authorsNote!.depth
          : rawBlock.depth ?? 0;
      if (anMode == 'depth') {
        depthBlocks.add(_ResolvedDepthBlock(id: id, role: resolved.role, content: resolved.content, depth: anDepth, isSummary: blockIsSummary));
      } else {
        relativeBlocks.add(_ResolvedRelativeBlock(id: id, name: rawBlock.name, role: resolved.role, content: resolved.content, contentForAccounting: resolved.contentForAccounting, isSummary: blockIsSummary, appendToLastMessage: rawBlock.appendToLastMessage));
      }
    } else if (rawBlock.insertionMode == 'depth' && id != 'chat_history') {
      depthBlocks.add(_ResolvedDepthBlock(id: id, role: resolved.role, content: resolved.content, depth: rawBlock.depth ?? 0, isSummary: blockIsSummary));
    } else {
      relativeBlocks.add(_ResolvedRelativeBlock(id: id, name: rawBlock.name, role: resolved.role, content: resolved.content, contentForAccounting: resolved.contentForAccounting, isSummary: blockIsSummary, appendToLastMessage: rawBlock.appendToLastMessage));
    }
  }

  if (payload.characterDepthPrompt.isNotEmpty) {
    final dpContent = replaceMacros(payload.characterDepthPrompt, currentMacroCtx).text;
    if (dpContent.trim().isNotEmpty) {
      depthBlocks.add(_ResolvedDepthBlock(
        id: 'char_depth_prompt',
        role: payload.characterDepthPromptRole.isNotEmpty ? payload.characterDepthPromptRole : 'system',
        content: dpContent,
        depth: payload.characterDepthPromptDepth,
      ));
    }
  }

  final macroTokens = <String, int>{};
  if (currentMacroCtx.lorebooksContent != null && currentMacroCtx.lorebooksContent!.isNotEmpty) {
    macroTokens['lorebooks'] = estimateTokens(currentMacroCtx.lorebooksContent!);
  }
  if (currentMacroCtx.summaryContent != null && currentMacroCtx.summaryContent!.isNotEmpty) {
    macroTokens['summary'] = estimateTokens(currentMacroCtx.summaryContent!);
  }
  if (currentMacroCtx.memoryContent != null && currentMacroCtx.memoryContent!.isNotEmpty) {
    macroTokens['memory'] = estimateTokens(currentMacroCtx.memoryContent!);
  }
  if (currentMacroCtx.charDescription != null && currentMacroCtx.charDescription!.isNotEmpty) {
    macroTokens['description'] = estimateTokens(currentMacroCtx.charDescription!);
  }
  if (currentMacroCtx.charPersonality != null && currentMacroCtx.charPersonality!.isNotEmpty) {
    macroTokens['personality'] = estimateTokens(currentMacroCtx.charPersonality!);
  }
  if (currentMacroCtx.charScenario != null && currentMacroCtx.charScenario!.isNotEmpty) {
    macroTokens['scenario'] = estimateTokens(currentMacroCtx.charScenario!);
  }
  if (currentMacroCtx.personaPrompt != null && currentMacroCtx.personaPrompt!.isNotEmpty) {
    macroTokens['persona'] = estimateTokens(currentMacroCtx.personaPrompt!);
  }
  if (currentMacroCtx.charMesExample != null && currentMacroCtx.charMesExample!.isNotEmpty) {
    macroTokens['mesExamples'] = estimateTokens(currentMacroCtx.charMesExample!);
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
    return (payload.apiConfig.contextSize * settings.reserveValue / 100).round();
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
}) _classifyLorebooks(
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

    final pos = entry.position == 'matchGlobal' ? settings.injectionPosition : entry.position;

    if (pos == 'charScenario') {
      loreScenario.add(content);
    } else if (pos == 'charPersonality') {
      lorePersonality.add(content);
    } else if (pos == 'charDescription') {
      loreDescription.add(content);
    } else if (pos == 'lorebooksMacro') {
      loreMacroBuffer.add(content);
    } else if (pos == 'worldInfoAfter') {
      loreAfter.add(PromptMessage(role: 'system', content: content, isLorebook: true, blockId: 'worldInfoAfter', blockName: 'Lorebook: ${entry.comment.isNotEmpty ? entry.comment : entry.id}'));
    } else {
      loreBefore.add(PromptMessage(role: 'system', content: content, isLorebook: true, blockId: 'worldInfoBefore', blockName: 'Lorebook: ${entry.comment.isNotEmpty ? entry.comment : entry.id}'));
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

  final resolvedDepthMsgs = depthBlocks.map((b) => PromptMessage(role: b.role, content: b.content, blockId: b.id, depth: b.depth, isDepth: true, isSummary: b.isSummary)).toList();

  // Track whether loreBefore/loreAfter were injected via char_card trigger.
  // If the preset has no char_card block, they fall through to the end.
  bool loreBeforeInjected = false;
  bool loreAfterInjected = false;

  void injectLoreBefore() {
    if (loreBeforeInjected || loreBefore.isEmpty) return;
    final combined = loreBefore.map((e) => e.content).join('\n\n');
    messages.add(PromptMessage(role: 'system', content: combined, isLorebook: true, blockId: 'worldInfoBefore', blockName: 'Lorebook (Before)'));
    attributionBlocks.add(StaticBlock(id: 'worldInfoBefore', content: combined));
    loreBeforeInjected = true;
  }

  void injectLoreAfter() {
    if (loreAfterInjected || loreAfter.isEmpty) return;
    final combined = loreAfter.map((e) => e.content).join('\n\n');
    messages.add(PromptMessage(role: 'system', content: combined, isLorebook: true, blockId: 'worldInfoAfter', blockName: 'Lorebook (After)'));
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
      if (mergeBuffer != null) { messages.add(PromptMessage(role: mergeRole ?? 'system', blockId: 'preset', content: mergeBuffer)); mergeBuffer = null; }
      // worldInfoAfter injects just before chat_history (mirrors JS generationWorker.js:680)
      injectLoreAfter();

      final historyMacroCtx = MacroContext(
        charName: macroCtx.charName, charDescription: macroCtx.charDescription,
        charScenario: macroCtx.charScenario, charPersonality: macroCtx.charPersonality,
        charMesExample: macroCtx.charMesExample, userName: macroCtx.userName,
        personaPrompt: macroCtx.personaPrompt, reasoningStart: macroCtx.reasoningStart,
        reasoningEnd: macroCtx.reasoningEnd, sessionVars: currentSessionVars,
        globalVars: currentGlobalVars, charId: macroCtx.charId, sessionId: macroCtx.sessionId,
        macroName: macroCtx.macroName,
      );
      final historyMsgs = HistoryAssembler(historyMacroCtx).assemble(history);
      final appendedForHistory = appendedEntries
          .map((b) => (name: b.name, content: b.content))
          .toList();
      applyAppendToLastMessage(historyMsgs, appendedForHistory);
      messages.addAll(interleaveDepthWithHistory(historyMsgs, resolvedDepthMsgs));
      for (final db in resolvedDepthMsgs) {
        attributionBlocks.add(StaticBlock(id: db.blockId ?? 'preset', content: db.content));
      }
    } else {
      final content = block.content.trim();
      final accountingContent = block.contentForAccounting.trim();

      // setvar-only blocks: no LLM-visible text, but definitions count toward preset.
      if (content.isEmpty) {
        if (accountingContent.isNotEmpty) {
          attributionBlocks.add(StaticBlock(id: block.id, content: accountingContent));
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
      attributionBlocks.add(StaticBlock(id: block.id, content: accountingContent));

      // appendToLastMessage blocks are merged into the last user message in
      // applyAppendToLastMessage (see appendedEntries above). They must NOT
      // also be added to messages here — that would send the same content
      // twice. See docs/INVARIANTS.md INV-PS9.
      if (block.appendToLastMessage) continue;

      if (preset.mergePrompts && block.role != 'assistant') {
        if (mergeBuffer != null) { mergeBuffer = '$mergeBuffer\n\n$content'; } else { mergeBuffer = content; mergeRole = preset.mergeRole; }
      } else {
        if (mergeBuffer != null) { messages.add(PromptMessage(role: mergeRole ?? 'system', blockId: 'preset', content: mergeBuffer)); mergeBuffer = null; }
        messages.add(PromptMessage(role: block.role, blockId: block.id, content: content, isSummary: block.isSummary));
      }

      // worldInfoAfter injects just after char_card (mirrors JS generationWorker.js:792)
      if (block.id == 'char_card') injectLoreAfter();
    }
  }

  // Fallback: if preset had no char_card block, inject remaining lore at the end
  injectLoreBefore();
  injectLoreAfter();
  if (mergeBuffer != null) messages.add(PromptMessage(role: mergeRole ?? 'system', blockId: 'preset', content: mergeBuffer));

  if (payload.memoryContent != null && payload.memoryContent!.isNotEmpty) {
    if (payload.memoryInjectionTarget == 'hard_block') {
      // Skip the hard block if the preset already handles memory via
      // {{memory}} macro or via an explicit `id: 'memory'` block.
      // (See docs/INVARIANTS.md INV-PS5.)
      final hasMemoryBlock = messages.any((m) => m.blockId == 'memory') ||
          appendedEntries.any((b) => b.id == 'memory');
      if (!hasMemoryBlock) {
        _injectMemoryBlock(messages, attributionBlocks, payload.memoryContent!);
      }
    }
    // 'macro' target: skip hard block, user must place {{memory}} in preset
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

  final calculator = ContextCalculator(contextSize: payload.apiConfig.contextSize, maxTokens: payload.apiConfig.maxTokens);
  final historyOnly = messages.where((m) => m.isHistory).toList();

  final breakdown = calculator.calculate(
    staticBlocks: attributionBlocks,
    historyMessages: historyOnly,
    lorebookReserveTokens: lorebookReserve,
    macroTokens: macroTokens,
    vectorLoreTokens: vectorLoreTokens,
  );

  final finalMessages = <PromptMessage>[];
  var historyInserted = false;
  for (final msg in messages) {
    if (msg.isHistory) {
      if (!historyInserted) { finalMessages.addAll(breakdown.trimmedHistory); historyInserted = true; }
    } else if (msg.content.trim().isNotEmpty) {
      finalMessages.add(msg);
    }
  }

  final regexCtx = RegexApplyContext(
    char: char,
    persona: persona,
    sessionVars: currentSessionVars,
    globalVars: currentGlobalVars,
  );

  final presetRegexes = preset.regexes.where((r) => !r.disabled).toList();
  final globalRegexes = payload.globalRegexes.where((r) => !r.disabled).toList();
  final regexScripts = [...presetRegexes, ...globalRegexes];

  for (int i = 0; i < finalMessages.length; i++) {
    final msg = finalMessages[i];
    if (msg.isHistory) {
      final placement = msg.role == 'user' ? 1 : 2;
      final depth = finalMessages.where((m) => m.isHistory).length - 1 -
          finalMessages.sublist(0, i).where((m) => m.isHistory).length;
      final ctx = RegexApplyContext(
        char: char, persona: persona,
        sessionVars: currentSessionVars, globalVars: currentGlobalVars,
        depth: depth,
      );
      finalMessages[i] = PromptMessage(
        role: msg.role,
        content: applyRegexes(
          msg.content,
          placement,
          2,
          regexScripts,
          ctx,
          isPrompt: true,
        ),
        isLorebook: msg.isLorebook,
        blockName: msg.blockName,
        isHistory: msg.isHistory,
        isDepth: msg.isDepth,
        depth: msg.depth,
      );
    } else {
      final placement = msg.isLorebook ? 5 : 4;
      finalMessages[i] = PromptMessage(
        role: msg.role,
        content: applyRegexes(
          msg.content,
          placement,
          2,
          regexScripts,
          regexCtx,
          isPrompt: true,
        ),
        isLorebook: msg.isLorebook,
        blockName: msg.blockName,
        isHistory: msg.isHistory,
        isDepth: msg.isDepth,
        depth: msg.depth,
      );
    }
  }

  return PromptResult(messages: finalMessages, breakdown: breakdown, sessionVars: currentSessionVars, globalVars: currentGlobalVars, triggeredLorebooks: triggeredLorebooks, triggeredMemories: triggeredMemories);
}

void _injectMemoryBlock(List<PromptMessage> messages, List<StaticBlock> attributionBlocks, String content) {
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
