import '../models/character.dart';
import '../models/persona.dart';
import 'macro_engine.dart';

class NotifyObj {
  Map<String, String> sessionVars = {};
  Map<String, String> globalVars = {};
  bool varsChanged = false;
}

class ResolvedContent {
  final String role;
  final String content;
  const ResolvedContent({required this.role, required this.content});
}

ResolvedContent? resolveBlockContent({
  required String id,
  required String rawContent,
  required String role,
  required Character char,
  required Persona? persona,
  required MacroContext macroCtx,
  required Map<String, String> sessionVars,
  required Map<String, String> globalVars,
  required NotifyObj notifyObj,
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
      return ResolvedContent(role: resolvedRole, content: '');
    case 'summary':
      if (summaryContent != null && summaryContent.isNotEmpty) {
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

  return ResolvedContent(role: resolvedRole, content: macroResult.text);
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
