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
import 'tokenizer.dart';
import 'lorebook_scanner.dart';

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

PromptResult buildPrompt(PromptPayload payload) {
  if (payload.preset == null) {
    return _buildFallbackPrompt(payload);
  }

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
  final notifyObj = _NotifyObj();

  final depthBlocks = <_ResolvedDepthBlock>[];
  final relativeBlocks = <_ResolvedRelativeBlock>[];

  final lastUserMsg = payload.history
      .where((m) => m.role == 'user')
      .lastOrNull;
  final textToScan = lastUserMsg?.content ?? '';

  final loreEntries = scanLorebooks(
    history: payload.history,
    char: char,
    textToScan: textToScan,
    chatId: null,
    lorebooks: payload.lorebooks,
    globalSettings: payload.lorebookSettings,
    activations: payload.lorebookActivations,
  );

  final loreBefore = <PromptMessage>[];
  final loreAfter = <PromptMessage>[];
  final loreMacroBuffer = <String>[];

  for (final entry in loreEntries) {
    var content = replaceMacros(entry.content, macroCtx).text;
    if (content.trim().isEmpty) continue;

    final pos = entry.position == 'matchGlobal'
        ? payload.lorebookSettings.injectionPosition
        : entry.position;

    if (pos == 'lorebooksMacro') {
      loreMacroBuffer.add(content);
    } else if (pos == 'worldInfoAfter') {
      loreAfter.add(PromptMessage(role: 'system', content: content));
    } else {
      loreBefore.add(PromptMessage(role: 'system', content: content));
    }
  }

  final macroLoreContent = loreMacroBuffer.join('\n\n');



  for (final rawBlock in preset.blocks) {
    final id = normalizeBlockId(rawBlock.id);
    if (!rawBlock.enabled) continue;
    if (rawBlock.isStashed) continue;

    final resolved = _resolveBlockContent(
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
    if (resolved == null) {
      if (notifyObj.varsChanged) {
        currentSessionVars = Map<String, String>.from(notifyObj.sessionVars);
        currentGlobalVars = Map<String, String>.from(notifyObj.globalVars);
        debugPrint('VARS: Block "$id" updated vars (no content) - session=${currentSessionVars.keys.toList()}, global=${currentGlobalVars.keys.toList()}');
      }
      continue;
    }

    if (notifyObj.varsChanged) {
      debugPrint('VARS: Block "$id" updated vars (has content) - session=${notifyObj.sessionVars.keys.toList()}, global=${notifyObj.globalVars.keys.toList()}');
    }
    currentSessionVars = Map<String, String>.from(notifyObj.sessionVars);
    currentGlobalVars = Map<String, String>.from(notifyObj.globalVars);

    final insertionMode = rawBlock.insertionMode;
    if (insertionMode == 'depth' && id != 'chat_history') {
      depthBlocks.add(_ResolvedDepthBlock(
        role: resolved.role,
        content: resolved.content,
        depth: rawBlock.depth ?? 0,
      ));
    } else {
      relativeBlocks.add(_ResolvedRelativeBlock(
        id: id,
        role: resolved.role,
        content: resolved.content,
      ));
    }
  }

  final messages = <PromptMessage>[];
  String? mergeBuffer;
  String? mergeRole;

  final resolvedDepthMsgs = depthBlocks.map((b) => PromptMessage(
    role: b.role,
    content: b.content,
    depth: b.depth,
    isDepth: true,
  )).toList();

  bool loreBeforeInjected = false;
  bool loreAfterInjected = false;

  for (final block in relativeBlocks) {
    if (!loreBeforeInjected) {
      messages.addAll(loreBefore);
      loreBeforeInjected = true;
    }

    if (block.id == 'chat_history') {
      if (mergeBuffer != null) {
        messages.add(PromptMessage(
          role: mergeRole ?? 'system',
          content: mergeBuffer,
        ));
        mergeBuffer = null;
      }

      if (!loreAfterInjected) {
        messages.addAll(loreAfter);
        loreAfterInjected = true;
      }

      debugPrint('VARS: Before history - session=${currentSessionVars.keys.toList()}, global=${currentGlobalVars.keys.toList()}');
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
      );

      final assembler = HistoryAssembler(historyMacroCtx);
      final historyMsgs = assembler.assemble(payload.history);

      final interleaved = interleaveDepthWithHistory(historyMsgs, resolvedDepthMsgs);
      messages.addAll(interleaved);
    } else {
      var content = block.content.trim();
      if (content.isEmpty) continue;

      content = content
          .replaceAll('{{lorebooks}}', macroLoreContent);

      if (preset.mergePrompts && block.role != 'assistant') {
        if (mergeBuffer != null) {
          mergeBuffer = '$mergeBuffer\n\n$content';
        } else {
          mergeBuffer = content;
          mergeRole = preset.mergeRole;
        }
      } else {
        if (mergeBuffer != null) {
          messages.add(PromptMessage(
            role: mergeRole ?? 'system',
            content: mergeBuffer,
          ));
          mergeBuffer = null;
        }
        messages.add(PromptMessage(
          role: block.role,
          content: content,
        ));
      }
    }
  }

  if (!loreBeforeInjected) messages.addAll(loreBefore);
  if (!loreAfterInjected) messages.addAll(loreAfter);

  if (mergeBuffer != null) {
    messages.add(PromptMessage(
      role: mergeRole ?? 'system',
      content: mergeBuffer,
    ));
  }

  final calculator = ContextCalculator(
    contextSize: payload.apiConfig.contextSize,
    maxTokens: payload.apiConfig.maxTokens,
  );

  final allStatic = messages.where((m) => !m.isHistory).toList();
  final historyOnly = messages.where((m) => m.isHistory).toList();

  final breakdown = calculator.calculate(
    staticBlocks: allStatic.map((m) => StaticBlock(
      id: 'static',
      content: m.content,
    )).toList(),
    historyMessages: historyOnly,
  );

  // IMPORTANT: Replace history messages in-place to preserve block order
  final finalMessages = <PromptMessage>[];
  var historyInserted = false;
  for (final msg in messages) {
    if (msg.isHistory) {
      if (!historyInserted) {
        finalMessages.addAll(breakdown.trimmedHistory);
        historyInserted = true;
      }
      // Skip original history messages, we already inserted trimmed ones
    } else {
      finalMessages.add(msg);
    }
  }

  return PromptResult(
    messages: finalMessages,
    breakdown: breakdown,
    sessionVars: currentSessionVars,
    globalVars: currentGlobalVars,
  );
}

_ResolvedContent? _resolveBlockContent({
  required String id,
  required String rawContent,
  required String role,
  required Character char,
  required Persona? persona,
  required MacroContext macroCtx,
  required Map<String, String> sessionVars,
  required Map<String, String> globalVars,
  required _NotifyObj notifyObj,
  required String? summaryContent,
  required String? summaryPrefix,
}) {
  String content;
  String resolvedRole = role;

  switch (id) {
    case 'char_card':
      content = _charCardContent(char);
    case 'char_personality':
      content = char.personality ?? '';
    case 'scenario':
      content = char.scenario ?? '';
    case 'example_dialogue':
      content = char.mesExample ?? '';
    case 'user_persona':
      content = _userPersonaContent(persona);
    case 'chat_history':
      return _ResolvedContent(role: resolvedRole, content: '');
    case 'summary':
      if (summaryContent != null && summaryContent!.isNotEmpty) {
        final prefix = summaryPrefix ?? 'Summary: ';
        content = '[$prefix$summaryContent]';
      } else {
        return null;
      }
    default:
      content = rawContent;
  }

  if (content.isEmpty) return null;

  final macroResult = replaceMacros(content, macroCtx);
  if (macroResult.varsChanged) {
    notifyObj.sessionVars = macroResult.sessionVars;
    notifyObj.globalVars = macroResult.globalVars;
    notifyObj.varsChanged = true;
  }

  if (macroResult.text.trim().isEmpty) return null;

  return _ResolvedContent(role: resolvedRole, content: macroResult.text);
}

String _charCardContent(Character char) {
  final buf = StringBuffer();
  buf.writeln('Character Name: ${char.name}');
  if (char.description != null && char.description!.isNotEmpty) {
    buf.writeln('Description: ${char.description}');
  }
  return buf.toString().trimRight();
}

String _userPersonaContent(Persona? persona) {
  final buf = StringBuffer();
  buf.writeln('User Name: ${persona?.name ?? 'User'}');
  if (persona?.prompt != null && persona!.prompt!.isNotEmpty) {
    buf.writeln('User Description: ${persona.prompt}');
  }
  return buf.toString().trimRight();
}

PromptResult _buildFallbackPrompt(PromptPayload payload) {
  final macroCtx = MacroContext(
    charName: payload.character.name,
    charDescription: payload.character.description,
    charScenario: payload.character.scenario,
    charPersonality: payload.character.personality,
    charMesExample: payload.character.mesExample,
    userName: payload.persona?.name ?? 'User',
    personaPrompt: payload.persona?.prompt,
    charId: payload.character.id,
    sessionId: '',
    sessionVars: payload.sessionVars,
    globalVars: payload.globalVars,
  );

  final messages = <PromptMessage>[];
  messages.add(const PromptMessage(
    role: 'system',
    content: 'You are a helpful assistant.',
  ));

  for (final msg in payload.history) {
    final macroResult = replaceMacros(msg.content, macroCtx);
    messages.add(PromptMessage(role: msg.role, content: macroResult.text));
  }

  return PromptResult(
    messages: messages,
    breakdown: TokenBreakdown(
      sourceTokens: {'preset': 6},
      staticTotal: 6,
      historyBudget: payload.apiConfig.contextSize - payload.apiConfig.maxTokens - 6,
      historyTokens: messages.fold(0, (sum, m) => sum + estimateTokens(m.content)),
      totalTokens: messages.fold(0, (sum, m) => sum + estimateTokens(m.content)),
      cutoffIndex: 0,
      trimmedHistory: messages.skip(1).toList(),
    ),
    sessionVars: payload.sessionVars,
    globalVars: payload.globalVars,
  );
}

class _NotifyObj {
  Map<String, String> sessionVars = {};
  Map<String, String> globalVars = {};
  bool varsChanged = false;
}

class _ResolvedContent {
  final String role;
  final String content;
  const _ResolvedContent({required this.role, required this.content});
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
