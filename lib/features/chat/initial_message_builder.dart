import '../../core/llm/macro_engine.dart';
import '../../core/models/character.dart';
import '../../core/models/chat_message.dart';
import '../../core/models/persona.dart';

class InitialMessageBuilder {
  static List<ChatMessage> build({
    required Character? character,
    required Persona? persona,
    required String sessionId,
  }) {
    if (character?.firstMes == null || character!.firstMes!.isEmpty) return [];

    final macroCtx = MacroContext(
      charName: character.name,
      charDescription: character.description,
      charScenario: character.scenario,
      charPersonality: character.personality,
      charMesExample: character.mesExample,
      userName: persona?.name ?? 'User',
      personaPrompt: persona?.prompt,
      charId: character.id,
      sessionId: sessionId,
    );
    final resolved = replaceMacros(character.firstMes!, macroCtx);
    return [
      ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toRadixString(36),
        role: 'assistant',
        content: resolved.text,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    ];
  }
}
