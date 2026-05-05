class ResponseNormalizer {
  static ({String content, String? reasoningContent}) extractOpenAiMessage(
    Map<String, dynamic> data,
  ) {
    final choice = data['choices']?[0];
    final message = choice?['message'];
    final content = message?['content'] as String? ?? '';
    final reasoningContent = message?['reasoning_content'] as String? ??
        message?['reasoning'] as String?;
    return (content: content, reasoningContent: reasoningContent);
  }

  static ({String text, String? reasoning}) normalizeReasoningOutput({
    required String content,
    required bool requestReasoning,
    String? rawReasoning,
    bool hasInlineTags = false,
    String? tagStart,
    String? tagEnd,
  }) {
    if (!requestReasoning) {
      return (text: content, reasoning: null);
    }

    String? finalReasoning = rawReasoning;

    if (hasInlineTags && tagStart != null && tagEnd != null) {
      final inline = _extractInlineReasoning(content, tagStart, tagEnd);
      final cleanContent = inline.text;

      if (inline.reasoning.isNotEmpty) {
        if (finalReasoning != null && finalReasoning.isNotEmpty) {
          finalReasoning = '$finalReasoning\n\n---\n\n${inline.reasoning}';
        } else {
          finalReasoning = inline.reasoning;
        }
      }

      return (text: cleanContent, reasoning: finalReasoning);
    }

    return (text: content, reasoning: finalReasoning);
  }

  static ({String text, String reasoning}) _extractInlineReasoning(
    String raw,
    String start,
    String end,
  ) {
    var text = '';
    var reasoning = '';
    var inReasoning = false;
    var remaining = raw;

    while (remaining.isNotEmpty) {
      if (inReasoning) {
        final endIdx = remaining.indexOf(end);
        if (endIdx == -1) {
          reasoning += remaining;
          break;
        }
        reasoning += remaining.substring(0, endIdx);
        remaining = remaining.substring(endIdx + end.length);
        inReasoning = false;
      } else {
        final startIdx = remaining.indexOf(start);
        if (startIdx == -1) {
          text += remaining;
          break;
        }
        text += remaining.substring(0, startIdx);
        remaining = remaining.substring(startIdx + start.length);
        inReasoning = true;
      }
    }

    return (text: text, reasoning: reasoning);
  }
}
