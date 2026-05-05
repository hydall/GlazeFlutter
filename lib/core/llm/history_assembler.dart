import '../models/chat_message.dart';
import 'macro_engine.dart';

class HistoryAssembler {
  final MacroContext macroCtx;

  HistoryAssembler(this.macroCtx);

  List<PromptMessage> assemble(
    List<ChatMessage> history,
    List<PromptMessage> depthBlocks,
    bool noAssistant,
  ) {
    if (history.isEmpty) return [];

    if (noAssistant) {
      return _buildNoAssistantHistory(history);
    }

    return _buildNormalHistory(history, depthBlocks);
  }

  List<PromptMessage> _buildNormalHistory(
    List<ChatMessage> history,
    List<PromptMessage> depthBlocks,
  ) {
    final messages = <PromptMessage>[];

    for (int i = 0; i < history.length; i++) {
      final msg = history[i];
      final macroResult = replaceMacros(msg.content, macroCtx);
      messages.add(PromptMessage(
        role: msg.role,
        content: macroResult.text,
      ));

      if (depthBlocks.isNotEmpty) {
        final remainingFromEnd = history.length - i - 1;
        final toInsert = depthBlocks.where((b) {
          final d = b.depth ?? 0;
          return d > 0 && d == remainingFromEnd + 1;
        }).toList();
        messages.addAll(toInsert);
      }
    }

    final preHistoryBlocks = depthBlocks.where((b) {
      final d = b.depth ?? 0;
      return d >= history.length;
    }).toList();

    if (preHistoryBlocks.isNotEmpty) {
      return [...preHistoryBlocks, ...messages];
    }

    return messages;
  }

  List<PromptMessage> _buildNoAssistantHistory(List<ChatMessage> history) {
    final buf = StringBuffer();
    for (final msg in history) {
      final macroResult = replaceMacros(msg.content, macroCtx);
      final prefix = msg.role == 'user' ? macroCtx.userName : macroCtx.charName;
      buf.writeln('$prefix: ${macroResult.text}');
    }
    return [PromptMessage(role: 'assistant', content: buf.toString().trimRight())];
  }
}

class PromptMessage {
  final String role;
  final String content;
  final int? depth;

  const PromptMessage({required this.role, required this.content, this.depth});

  Map<String, String> toApiMap() => {'role': role, 'content': content};
}
