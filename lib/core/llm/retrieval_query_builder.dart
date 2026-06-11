import '../models/chat_message.dart';

/// A compact window of recent turns used as the vector retrieval query.
///
/// Both the live injection service and the isolate worker can build this
/// without touching each other. The output is plain text (no roles, no
/// metadata) so the embedding API sees only the actual retrieval cue.
class RetrievalQueryBuilder {
  const RetrievalQueryBuilder._();

  /// Build the retrieval query from the most recent turns.
  ///
  /// Rules:
  /// - Always include [currentText] (latest user/edited message) first.
  /// - If [includeAssistant] is true (default), include the most recent
  ///   assistant turn that is not hidden/typing/empty.
  /// - Then walk backwards through the [history] collecting up to
  ///   [recentTurns] user/assistant turns (each counts as 1 turn).
  /// - Stop once the accumulated text exceeds [maxChars]; the cap is
  ///   inclusive of the prefix/current text.
  /// - Hidden/typing/empty messages are skipped.
  /// - Output is single-line, trimmed, ready to embed.
  static String build({
    required String currentText,
    required List<ChatMessage> history,
    bool includeAssistant = true,
    int recentTurns = 6,
    int maxChars = 1500,
  }) {
    if (maxChars <= 0) return currentText.trim();
    final buffer = StringBuffer();
    var used = 0;

    void append(String chunk) {
      if (chunk.isEmpty) return;
      if (used + chunk.length > maxChars) return;
      buffer
        ..write(used == 0 ? chunk : '\n$chunk');
      used += chunk.length + (used == 0 ? 0 : 1);
    }

    append(currentText.trim());

    if (includeAssistant) {
      for (int i = history.length - 1; i >= 0; i--) {
        final msg = history[i];
        if (msg.isHidden || msg.isTyping) continue;
        if (msg.role != 'assistant') continue;
        if (msg.content.trim().isEmpty) continue;
        append(msg.content.trim());
        break;
      }
    }

    if (recentTurns > 0) {
      var turns = 0;
      for (int i = history.length - 1; i >= 0; i--) {
        if (turns >= recentTurns) break;
        final msg = history[i];
        if (msg.isHidden || msg.isTyping) continue;
        if (msg.role != 'user' && msg.role != 'assistant') continue;
        if (msg.content.trim().isEmpty) continue;
        append(msg.content.trim());
        turns++;
      }
    }

    return buffer.toString().trim();
  }
}
