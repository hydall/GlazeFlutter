import '../models/preset.dart';
import 'macro_engine.dart';

class PromptBlockResolver {
  final MacroContext macroCtx;

  PromptBlockResolver(this.macroCtx);

  ResolvedBlock resolve(PresetBlock block) {
    final content = _resolveContent(block);
    final macroResult = replaceMacros(content, macroCtx);
    return ResolvedBlock(
      id: block.id,
      role: block.role,
      content: macroResult.text,
      enabled: block.enabled,
      isStatic: block.isStatic,
      insertionMode: block.insertionMode,
      depth: block.depth,
      prefix: block.prefix,
      isStashed: block.isStashed,
      sessionVars: macroResult.sessionVars,
      globalVars: macroResult.globalVars,
      varsChanged: macroResult.varsChanged,
    );
  }

  String _resolveContent(PresetBlock block) {
    return switch (block.id) {
      'char_card' || 'charCard' => _charCardContent(),
      'char_personality' || 'charPersonality' => _charPersonalityContent(),
      'scenario' => _scenarioContent(),
      'example_dialogue' || 'exampleDialogue' => _exampleDialogueContent(),
      'user_persona' || 'userPersona' => _userPersonaContent(),
      'chat_history' || 'chatHistory' => '',
      'summary' => '',
      _ => block.content,
    };
  }

  String _charCardContent() {
    final buf = StringBuffer();
    if (macroCtx.charName.isNotEmpty) {
      buf.writeln('Character Name: ${macroCtx.charName}');
    }
    if (macroCtx.charDescription != null && macroCtx.charDescription!.isNotEmpty) {
      buf.writeln('Description: ${macroCtx.charDescription}');
    }
    return buf.toString().trimRight();
  }

  String _charPersonalityContent() {
    if (macroCtx.charPersonality == null || macroCtx.charPersonality!.isEmpty) {
      return '';
    }
    return 'Personality: ${macroCtx.charPersonality}';
  }

  String _scenarioContent() {
    if (macroCtx.charScenario == null || macroCtx.charScenario!.isEmpty) {
      return '';
    }
    return 'Scenario: ${macroCtx.charScenario}';
  }

  String _exampleDialogueContent() {
    return macroCtx.charMesExample ?? '';
  }

  String _userPersonaContent() {
    final buf = StringBuffer();
    buf.writeln('User Name: ${macroCtx.userName}');
    if (macroCtx.personaPrompt != null && macroCtx.personaPrompt!.isNotEmpty) {
      buf.writeln('User Description: ${macroCtx.personaPrompt}');
    }
    return buf.toString().trimRight();
  }
}

class ResolvedBlock {
  final String id;
  final String role;
  final String content;
  final bool enabled;
  final bool isStatic;
  final String insertionMode;
  final int? depth;
  final String? prefix;
  final bool isStashed;
  final Map<String, String> sessionVars;
  final Map<String, String> globalVars;
  final bool varsChanged;

  const ResolvedBlock({
    required this.id,
    required this.role,
    required this.content,
    required this.enabled,
    required this.isStatic,
    required this.insertionMode,
    this.depth,
    this.prefix,
    required this.isStashed,
    required this.sessionVars,
    required this.globalVars,
    required this.varsChanged,
  });

  bool get isChatHistory =>
      id == 'chat_history' || id == 'chatHistory';
  bool get isDepthBlock => insertionMode == 'depth' && !isChatHistory;
  bool get hasContent => content.trim().isNotEmpty;
}
