import '../models/character.dart';
import '../models/persona.dart';
import '../models/preset.dart';
import '../models/chat_message.dart';
import '../models/api_config.dart';
import 'macro_engine.dart';
import 'prompt_block_resolver.dart';
import 'history_assembler.dart';
import 'context_calculator.dart';
import 'tokenizer.dart';

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

  final macroCtx = MacroContext(
    charName: payload.character.name,
    charDescription: payload.character.description,
    charScenario: payload.character.scenario,
    charPersonality: payload.character.personality,
    charMesExample: payload.character.mesExample,
    userName: payload.persona?.name ?? 'User',
    personaPrompt: payload.persona?.prompt,
    reasoningStart: payload.preset!.reasoningStart,
    reasoningEnd: payload.preset!.reasoningEnd,
    sessionVars: payload.sessionVars,
    globalVars: payload.globalVars,
    charId: payload.character.id,
    sessionId: '',
  );

  final resolver = PromptBlockResolver(macroCtx);
  final preset = payload.preset!;

  final resolvedBlocks = <ResolvedBlock>[];
  var currentSessionVars = Map<String, String>.from(payload.sessionVars);
  var currentGlobalVars = Map<String, String>.from(payload.globalVars);

  for (final block in preset.blocks) {
    if (!block.enabled || block.isStashed) continue;
    final resolved = resolver.resolve(block);
    resolvedBlocks.add(resolved);
    if (resolved.varsChanged) {
      currentSessionVars = resolved.sessionVars;
      currentGlobalVars = resolved.globalVars;
    }
  }

  final relativeBlocks = resolvedBlocks.where((b) => !b.isDepthBlock).toList();
  final depthBlocks = resolvedBlocks.where((b) => b.isDepthBlock).toList();

  final messages = <PromptMessage>[];
  final staticMessages = <PromptMessage>[];
  String? mergeBuffer;
  String? mergeRole;

  for (final block in relativeBlocks) {
    if (block.isChatHistory) {
      if (mergeBuffer != null) {
        staticMessages.add(PromptMessage(
          role: mergeRole ?? 'system',
          content: mergeBuffer,
        ));
        mergeBuffer = null;
      }

      final updatedMacroCtx = MacroContext(
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

      final assembler = HistoryAssembler(updatedMacroCtx);
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
      messages.addAll(historyMsgs);
    } else {
      if (!block.hasContent) continue;

      if (preset.mergePrompts && block.role != 'assistant') {
        if (mergeBuffer != null) {
          mergeBuffer = '$mergeBuffer\n\n${block.content}';
        } else {
          mergeBuffer = block.content;
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
          content: block.content,
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

  if (!messages.any((m) => _isHistoryMessage(m, payload.history))) {
    messages.addAll(staticMessages);
  }

  final calculator = ContextCalculator(
    contextSize: payload.apiConfig.contextSize,
    maxTokens: payload.apiConfig.maxTokens,
  );

  final allStatic = messages.where((m) => !_isHistoryMessage(m, payload.history)).toList();
  final historyMsgs = messages.where((m) => _isHistoryMessage(m, payload.history)).toList();

  final breakdown = calculator.calculate(
    staticBlocks: allStatic.map((m) => ResolvedBlock(
      id: 'static',
      role: m.role,
      content: m.content,
      enabled: true,
      isStatic: true,
      insertionMode: 'relative',
      isStashed: false,
      sessionVars: currentSessionVars,
      globalVars: currentGlobalVars,
      varsChanged: false,
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

PromptResult _buildFallbackPrompt(PromptPayload payload) {
  final messages = <PromptMessage>[];

  messages.add(const PromptMessage(
    role: 'system',
    content: 'You are a helpful assistant.',
  ));

  for (final msg in payload.history) {
    messages.add(PromptMessage(role: msg.role, content: msg.content));
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
