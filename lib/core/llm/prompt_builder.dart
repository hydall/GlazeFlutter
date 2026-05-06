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
  final List<Lorebook> lorebooks;
  final LorebookGlobalSettings lorebookSettings;
  final LorebookActivations lorebookActivations;
  final List<LorebookEntry> vectorEntries;

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
    this.lorebooks = const [],
    this.lorebookSettings = const LorebookGlobalSettings(),
    this.lorebookActivations = const LorebookActivations(),
    this.vectorEntries = const [],
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
  final String role;
  final String content;
  final int depth;
  const _ResolvedDepthBlock({required this.role, required this.content, required this.depth});
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
    );

    if (notifyObj.varsChanged) {
      currentSessionVars = Map<String, String>.from(notifyObj.sessionVars);
      currentGlobalVars = Map<String, String>.from(notifyObj.globalVars);
    }

    if (resolved == null) continue;

    if (rawBlock.insertionMode == 'depth' && id != 'chat_history') {
      depthBlocks.add(_ResolvedDepthBlock(role: resolved.role, content: resolved.content, depth: rawBlock.depth ?? 0));
    } else {
      relativeBlocks.add(_ResolvedRelativeBlock(id: id, role: resolved.role, content: resolved.content));
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
  );
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
      loreAfter.add(PromptMessage(role: 'system', content: content, isLorebook: true, blockName: 'Lorebook: ${entry.comment.isNotEmpty ? entry.comment : entry.id}'));
    } else {
      loreBefore.add(PromptMessage(role: 'system', content: content, isLorebook: true, blockName: 'Lorebook: ${entry.comment.isNotEmpty ? entry.comment : entry.id}'));
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
}) {
  final messages = <PromptMessage>[];
  String? mergeBuffer;
  String? mergeRole;

  final resolvedDepthMsgs = depthBlocks.map((b) => PromptMessage(role: b.role, content: b.content, depth: b.depth, isDepth: true)).toList();

  bool loreBeforeInjected = false;
  bool loreAfterInjected = false;

  for (final block in relativeBlocks) {
    if (!loreBeforeInjected) { messages.addAll(loreBefore); loreBeforeInjected = true; }

    if (block.id == 'chat_history') {
      if (mergeBuffer != null) { messages.add(PromptMessage(role: mergeRole ?? 'system', content: mergeBuffer)); mergeBuffer = null; }
      if (!loreAfterInjected) { messages.addAll(loreAfter); loreAfterInjected = true; }

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
    } else {
      var content = block.content.trim();
      if (content.isEmpty) continue;
      content = content.replaceAll('{{lorebooks}}', macroLoreContent);
      if (content.trim().isEmpty) continue;

      if (preset.mergePrompts && block.role != 'assistant') {
        if (mergeBuffer != null) { mergeBuffer = '$mergeBuffer\n\n$content'; } else { mergeBuffer = content; mergeRole = preset.mergeRole; }
      } else {
        if (mergeBuffer != null) { messages.add(PromptMessage(role: mergeRole ?? 'system', content: mergeBuffer)); mergeBuffer = null; }
        messages.add(PromptMessage(role: block.role, content: content));
      }
    }
  }

  if (!loreBeforeInjected) messages.addAll(loreBefore);
  if (!loreAfterInjected) messages.addAll(loreAfter);
  if (mergeBuffer != null) messages.add(PromptMessage(role: mergeRole ?? 'system', content: mergeBuffer));

  final calculator = ContextCalculator(contextSize: payload.apiConfig.contextSize, maxTokens: payload.apiConfig.maxTokens);
  final allStatic = messages.where((m) => !m.isHistory).toList();
  final historyOnly = messages.where((m) => m.isHistory).toList();

  final breakdown = calculator.calculate(
    staticBlocks: allStatic.map((m) => StaticBlock(id: 'static', content: m.content)).toList(),
    historyMessages: historyOnly,
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

  return PromptResult(messages: finalMessages, breakdown: breakdown, sessionVars: currentSessionVars, globalVars: currentGlobalVars);
}
