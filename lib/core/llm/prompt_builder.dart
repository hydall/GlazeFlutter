import 'package:flutter/foundation.dart';

import '../models/character.dart';
import '../models/persona.dart';
import '../models/preset.dart';
import '../models/chat_message.dart';
import '../models/api_config.dart';
import 'macro_engine.dart';
import 'history_assembler.dart';
import 'context_calculator.dart';
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

  for (final rawBlock in preset.blocks) {
    final id = normalizeBlockId(rawBlock.id);
    debugPrint('PROMPT: block "$id" (raw="${rawBlock.id}", enabled=${rawBlock.enabled}, stashed=${rawBlock.isStashed}, insertionMode=${rawBlock.insertionMode})');
    if (!rawBlock.enabled) continue;
    if (rawBlock.isStashed) {
      debugPrint('PROMPT:   → SKIPPED (stashed)');
      continue;
    }

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
      }
      debugPrint('PROMPT:   → null (no content, varsChanged=${notifyObj.varsChanged})');
      continue;
    }

    debugPrint('PROMPT:   → resolved, role=${resolved.role}, contentLen=${resolved.content.length}');

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
  final staticMessages = <PromptMessage>[];
  String? mergeBuffer;
  String? mergeRole;

  bool historyInjected = false;

  debugPrint('PROMPT: relativeBlocks count=${relativeBlocks.length}, ids=${relativeBlocks.map((b) => b.id).toList()}');

  for (final block in relativeBlocks) {
    if (block.id == 'chat_history') {
      debugPrint('PROMPT: → found chat_history, history len=${payload.history.length}');
      historyInjected = true;
      if (mergeBuffer != null) {
        staticMessages.add(PromptMessage(
          role: mergeRole ?? 'system',
          content: mergeBuffer,
        ));
        mergeBuffer = null;
      }

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
      final depthMsgs = depthBlocks.map((b) => PromptMessage(
        role: b.role,
        content: b.content,
        depth: b.depth,
      )).toList();

      final historyMsgs = assembler.assemble(
        payload.history,
        depthMsgs,
        false,
      );

      messages.addAll(staticMessages);
      staticMessages.clear();
      messages.addAll(historyMsgs);
    } else {
      final content = block.content.trim();
      if (content.isEmpty) continue;

      if (preset.mergePrompts && block.role != 'assistant') {
        if (mergeBuffer != null) {
          mergeBuffer = '$mergeBuffer\n\n$content';
        } else {
          mergeBuffer = content;
          mergeRole = preset.mergeRole;
        }
      } else {
        if (mergeBuffer != null) {
          staticMessages.add(PromptMessage(
            role: mergeRole ?? 'system',
            content: mergeBuffer,
          ));
          mergeBuffer = null;
        }
        staticMessages.add(PromptMessage(
          role: block.role,
          content: content,
        ));
      }
    }
  }

  if (mergeBuffer != null) {
    staticMessages.add(PromptMessage(
      role: mergeRole ?? 'system',
      content: mergeBuffer,
    ));
  }

  if (!historyInjected) {
    debugPrint('PROMPT: no chat_history block found, appending history at end');
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
    final depthMsgs = depthBlocks.map((b) => PromptMessage(
      role: b.role,
      content: b.content,
      depth: b.depth,
    )).toList();

    final historyMsgs = assembler.assemble(
      payload.history,
      depthMsgs,
      false,
    );

    messages.addAll(staticMessages);
    staticMessages.clear();
    messages.addAll(historyMsgs);
  } else if (staticMessages.isNotEmpty) {
    messages.addAll(staticMessages);
  }

  final calculator = ContextCalculator(
    contextSize: payload.apiConfig.contextSize,
    maxTokens: payload.apiConfig.maxTokens,
  );

  final allStatic = messages.where((m) => !_isHistoryMessage(m, payload.history)).toList();
  final historyMsgs = messages.where((m) => _isHistoryMessage(m, payload.history)).toList();

  final breakdown = calculator.calculate(
    staticBlocks: allStatic.map((m) => StaticBlock(
      id: 'static',
      content: m.content,
    )).toList(),
    historyMessages: historyMsgs,
  );

  final finalMessages = <PromptMessage>[
    ...allStatic,
    ...breakdown.trimmedHistory,
  ];

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

bool _isHistoryMessage(PromptMessage message, List<ChatMessage> history) {
  return history.any((h) => h.content == message.content && h.role == message.role);
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
