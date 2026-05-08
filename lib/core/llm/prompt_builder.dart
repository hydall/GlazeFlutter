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
  });
}

class PromptResult {
  final List<PromptMessage> messages;
  final TokenBreakdown breakdown;
  final Map<String, String> sessionVars;
  final Map<String, String> globalVars;

  const PromptResult({
    required this.messages,
    required this.breakdown,
    required this.sessionVars,
    required this.globalVars,
  });
}

class _ResolvedDepthBlock {
  final String id;
  final String role;
  final String content;
  final int depth;
  const _ResolvedDepthBlock({required this.id, required this.role, required this.content, required this.depth});
}

class _ResolvedRelativeBlock {
  final String id;
  final String role;
  final String content;
  const _ResolvedRelativeBlock({required this.id, required this.role, required this.content});
}

PromptResult buildPrompt(PromptPayload payload) {
  if (payload.preset == null) return buildFallbackPrompt(payload);

  final preset = payload.preset!;
  final char = payload.character;
  final persona = payload.persona;
  final macroCtx = MacroContext(
    charName: char.name,
    charDescription: char.description,
    charScenario: char.scenario,
    charPersonality: char.personality,
    charMesExample: char.mesExample,
    userName: persona?.name ?? 'User',
    personaPrompt: persona?.prompt,
    reasoningStart: preset.reasoningStart,
    reasoningEnd: preset.reasoningEnd,
    sessionVars: payload.sessionVars,
    globalVars: payload.globalVars,
    charId: char.id,
    sessionId: '',
    summaryContent: payload.summaryContent,
    guidanceText: payload.guidanceText,
  );

  var currentSessionVars = Map<String, String>.from(payload.sessionVars);
  var currentGlobalVars = Map<String, String>.from(payload.globalVars);
  final notifyObj = NotifyObj();

  final depthBlocks = <_ResolvedDepthBlock>[];
  final relativeBlocks = <_ResolvedRelativeBlock>[];

  final loreEntries = scanLorebooks(
    history: payload.history,
    char: char,
    textToScan: payload.history.where((m) => m.role == 'user').lastOrNull?.content ?? '',
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

  final (loreBefore, loreAfter, loreMacroBuffer) = _classifyLorebooks(mergedEntries, macroCtx, payload.lorebookSettings);
  final macroLoreContent = loreMacroBuffer.join('\n\n');

  for (final rawBlock in preset.blocks) {
    final id = normalizeBlockId(rawBlock.id);
    if (!rawBlock.enabled || rawBlock.isStashed) continue;

    final resolved = resolveBlockContent(
      id: id,
      rawContent: rawBlock.content,
      role: rawBlock.role,
      char: char,
      persona: persona,
      macroCtx: macroCtx,
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
    }

    if (resolved == null) continue;

    if (id == 'authors_note' && payload.authorsNote != null) {
      final anMode = payload.authorsNote!.insertionMode.isNotEmpty
          ? payload.authorsNote!.insertionMode
          : rawBlock.insertionMode;
      final anDepth = payload.authorsNote!.depth > 0
          ? payload.authorsNote!.depth
          : rawBlock.depth ?? 0;
      if (anMode == 'depth') {
        depthBlocks.add(_ResolvedDepthBlock(id: id, role: resolved.role, content: resolved.content, depth: anDepth));
      } else {
        relativeBlocks.add(_ResolvedRelativeBlock(id: id, role: resolved.role, content: resolved.content));
      }
    } else if (rawBlock.insertionMode == 'depth' && id != 'chat_history') {
      depthBlocks.add(_ResolvedDepthBlock(id: id, role: resolved.role, content: resolved.content, depth: rawBlock.depth ?? 0));
    } else {
      relativeBlocks.add(_ResolvedRelativeBlock(id: id, role: resolved.role, content: resolved.content));
    }
  }

  if (payload.characterDepthPrompt.isNotEmpty) {
    final dpContent = replaceMacros(payload.characterDepthPrompt, macroCtx).text;
    if (dpContent.trim().isNotEmpty) {
      depthBlocks.add(_ResolvedDepthBlock(
        id: 'char_depth_prompt',
        role: payload.characterDepthPromptRole.isNotEmpty ? payload.characterDepthPromptRole : 'system',
        content: dpContent,
        depth: payload.characterDepthPromptDepth,
      ));
    }
  }

  return _assembleMessages(
    relativeBlocks: relativeBlocks,
    depthBlocks: depthBlocks,
    loreBefore: loreBefore,
    loreAfter: loreAfter,
    macroLoreContent: macroLoreContent,
    history: payload.history,
    macroCtx: macroCtx,
    currentSessionVars: currentSessionVars,
    currentGlobalVars: currentGlobalVars,
    preset: preset,
    payload: payload,
    char: char,
    persona: persona,
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

(List<PromptMessage> loreBefore, List<PromptMessage> loreAfter, List<String> loreMacroBuffer) _classifyLorebooks(
  List<LorebookEntry> entries,
  MacroContext macroCtx,
  LorebookGlobalSettings settings,
) {
  final loreBefore = <PromptMessage>[];
  final loreAfter = <PromptMessage>[];
  final loreMacroBuffer = <String>[];

  for (final entry in entries) {
    var content = replaceMacros(entry.content, macroCtx).text;
    if (content.trim().isEmpty) continue;

    final pos = entry.position == 'matchGlobal' ? settings.injectionPosition : entry.position;

    if (pos == 'lorebooksMacro') {
      loreMacroBuffer.add(content);
    } else if (pos == 'worldInfoAfter') {
      loreAfter.add(PromptMessage(role: 'system', content: content, isLorebook: true, blockId: 'worldInfoAfter', blockName: 'Lorebook: ${entry.comment.isNotEmpty ? entry.comment : entry.id}'));
    } else {
      loreBefore.add(PromptMessage(role: 'system', content: content, isLorebook: true, blockId: 'worldInfoBefore', blockName: 'Lorebook: ${entry.comment.isNotEmpty ? entry.comment : entry.id}'));
    }
  }
  return (loreBefore, loreAfter, loreMacroBuffer);
}

PromptResult _assembleMessages({
  required List<_ResolvedRelativeBlock> relativeBlocks,
  required List<_ResolvedDepthBlock> depthBlocks,
  required List<PromptMessage> loreBefore,
  required List<PromptMessage> loreAfter,
  required String macroLoreContent,
  required List<ChatMessage> history,
  required MacroContext macroCtx,
  required Map<String, String> currentSessionVars,
  required Map<String, String> currentGlobalVars,
  required Preset preset,
  required PromptPayload payload,
  required Character char,
  Persona? persona,
}) {
  final messages = <PromptMessage>[];
  final attributionBlocks = <StaticBlock>[];
  String? mergeBuffer;
  String? mergeRole;

  final resolvedDepthMsgs = depthBlocks.map((b) => PromptMessage(role: b.role, content: b.content, blockId: b.id, depth: b.depth, isDepth: true)).toList();

  bool loreBeforeInjected = false;
  bool loreAfterInjected = false;

  for (final block in relativeBlocks) {
    if (!loreBeforeInjected) {
      messages.addAll(loreBefore);
      for (final lb in loreBefore) {
        attributionBlocks.add(StaticBlock(id: lb.blockId ?? 'lorebook', content: lb.content));
      }
      loreBeforeInjected = true;
    }

    if (block.id == 'chat_history') {
      if (mergeBuffer != null) { messages.add(PromptMessage(role: mergeRole ?? 'system', blockId: 'preset', content: mergeBuffer)); mergeBuffer = null; }
      if (!loreAfterInjected) {
        messages.addAll(loreAfter);
        for (final la in loreAfter) {
          attributionBlocks.add(StaticBlock(id: la.blockId ?? 'lorebook', content: la.content));
        }
        loreAfterInjected = true;
      }

      final historyMacroCtx = MacroContext(
        charName: macroCtx.charName, charDescription: macroCtx.charDescription,
        charScenario: macroCtx.charScenario, charPersonality: macroCtx.charPersonality,
        charMesExample: macroCtx.charMesExample, userName: macroCtx.userName,
        personaPrompt: macroCtx.personaPrompt, reasoningStart: macroCtx.reasoningStart,
        reasoningEnd: macroCtx.reasoningEnd, sessionVars: currentSessionVars,
        globalVars: currentGlobalVars, charId: macroCtx.charId, sessionId: macroCtx.sessionId,
      );
      final historyMsgs = HistoryAssembler(historyMacroCtx).assemble(history);
      messages.addAll(interleaveDepthWithHistory(historyMsgs, resolvedDepthMsgs));
      for (final db in resolvedDepthMsgs) {
        attributionBlocks.add(StaticBlock(id: db.blockId ?? 'preset', content: db.content));
      }
    } else {
      var content = block.content.trim();
      if (content.isEmpty) continue;
      content = content.replaceAll('{{lorebooks}}', macroLoreContent);
      if (content.trim().isEmpty) continue;

      attributionBlocks.add(StaticBlock(id: block.id, content: content));

      if (preset.mergePrompts && block.role != 'assistant') {
        if (mergeBuffer != null) { mergeBuffer = '$mergeBuffer\n\n$content'; } else { mergeBuffer = content; mergeRole = preset.mergeRole; }
      } else {
        if (mergeBuffer != null) { messages.add(PromptMessage(role: mergeRole ?? 'system', blockId: 'preset', content: mergeBuffer)); mergeBuffer = null; }
        messages.add(PromptMessage(role: block.role, blockId: block.id, content: content));
      }
    }
  }

  if (!loreBeforeInjected) {
    messages.addAll(loreBefore);
    for (final lb in loreBefore) {
      attributionBlocks.add(StaticBlock(id: lb.blockId ?? 'lorebook', content: lb.content));
    }
  }
  if (!loreAfterInjected) {
    messages.addAll(loreAfter);
    for (final la in loreAfter) {
      attributionBlocks.add(StaticBlock(id: la.blockId ?? 'lorebook', content: la.content));
    }
  }
  if (mergeBuffer != null) messages.add(PromptMessage(role: mergeRole ?? 'system', blockId: 'preset', content: mergeBuffer));

  if (payload.memoryContent != null && payload.memoryContent!.isNotEmpty) {
    if (payload.memoryInjectionTarget == 'summary_macro') {
      final attrSummaryIdx = attributionBlocks.indexWhere((b) => b.id == 'summary');
      if (attrSummaryIdx >= 0) {
        attributionBlocks[attrSummaryIdx] = StaticBlock(id: 'summary', content: '${attributionBlocks[attrSummaryIdx].content}\n\n${payload.memoryContent}');
      } else {
        attributionBlocks.add(StaticBlock(id: 'memory', content: payload.memoryContent!));
      }
      final msgSummaryIdx = messages.indexWhere((m) => m.blockId == 'summary');
      if (msgSummaryIdx >= 0) {
        final existing = messages[msgSummaryIdx];
        messages[msgSummaryIdx] = PromptMessage(
          role: existing.role,
          content: '${existing.content}\n\n${payload.memoryContent}',
          blockName: existing.blockName,
          isHistory: existing.isHistory,
          isDepth: existing.isDepth,
          depth: existing.depth,
          isLorebook: existing.isLorebook,
        );
      }
    } else {
      attributionBlocks.add(StaticBlock(id: 'memory', content: payload.memoryContent!));
      final memMsg = PromptMessage(
        role: 'system',
        content: payload.memoryContent!,
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
  }

  final lorebookReserve = _calculateLorebookReserve(payload);

  final calculator = ContextCalculator(contextSize: payload.apiConfig.contextSize, maxTokens: payload.apiConfig.maxTokens);
  final historyOnly = messages.where((m) => m.isHistory).toList();

  final breakdown = calculator.calculate(
    staticBlocks: attributionBlocks,
    historyMessages: historyOnly,
    lorebookReserveTokens: lorebookReserve,
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
        content: applyRegexes(msg.content, placement, 2, regexScripts, ctx),
        isLorebook: msg.isLorebook,
        blockName: msg.blockName,
        isHistory: msg.isHistory,
        isDepth: msg.isDepth,
        depth: msg.depth,
      );
    } else {
      finalMessages[i] = PromptMessage(
        role: msg.role,
        content: applyRegexes(msg.content, 4, 2, regexScripts, regexCtx),
        isLorebook: msg.isLorebook,
        blockName: msg.blockName,
        isHistory: msg.isHistory,
        isDepth: msg.isDepth,
        depth: msg.depth,
      );
    }
  }

  return PromptResult(messages: finalMessages, breakdown: breakdown, sessionVars: currentSessionVars, globalVars: currentGlobalVars);
}
