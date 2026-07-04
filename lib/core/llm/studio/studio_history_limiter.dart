import '../history_assembler.dart';
import '../../models/studio_config.dart';

/// History-trimming + text-truncation specialist extracted from
/// `StudioMessageBuilder` (plan Phase 5b). Pure static methods — no deps.
class StudioHistoryLimiter {
  /// Hard cap on tracker context size (Marinara MAX_AGENT_CONTEXT_MESSAGES).
  static const maxTrackerContextSize = 200;

  static const _trimMarker =
      '\n\n[Trimmed to keep this agent request compact]\n\n';

  static final _htmlTagRegex = RegExp(r'</?[a-zA-Z][^>]*>');
  static final _multiNewlineRegex = RegExp(r'\n{3,}');
  static final _fontTagRegex = RegExp(r'</?font\b[^>]*>', caseSensitive: false);

  /// Cap how many trailing chat messages reach the FINAL responder.
  ///
  /// Intermediate agents always analyze the full transcript; the final writer
  /// is intentionally limited (default 15) so it relies on the compact agent
  /// briefs instead of re-reading the whole history. We keep the most recent
  /// [StudioConfig.maxFinalHistoryMessages] messages, which always preserves
  /// the current user turn (it is last). 0 (or negative) means no limit.
  static List<PromptMessage> limitFinalHistory(
    List<PromptMessage> history,
    StudioConfig config, {
    int pipelineOverride = 0,
  }) {
    final limit = pipelineOverride > 0
        ? pipelineOverride
        : config.maxFinalHistoryMessages;
    final sliced = (limit <= 0 || history.length <= limit)
        ? history
        : history.sublist(history.length - limit);
    return sliced
        .map(
          (m) => PromptMessage(
            role: m.role,
            content: stripFontTags(m.content),
          ),
        )
        .toList();
  }

  /// Trim trailing chat history for a tracker (intermediate agent).
  ///
  /// Returns the last [contextSize] messages (clamped to
  /// `1..[maxTrackerContextSize]`), each truncated via [truncateAgentText]
  /// and stripped of HTML via [stripHtmlTags].
  static List<PromptMessage> limitTrackerHistory(
    List<PromptMessage> history,
    int contextSize,
  ) {
    final normalized = contextSize.clamp(1, maxTrackerContextSize);
    if (history.length <= normalized) {
      return history
          .map(
            (m) => PromptMessage(
              role: m.role,
              content: truncateAgentText(stripHtmlTags(m.content), 2000),
            ),
          )
          .toList();
    }
    final trimmed = history.sublist(history.length - normalized);
    return trimmed
        .map(
          (m) => PromptMessage(
            role: m.role,
            content: truncateAgentText(stripHtmlTags(m.content), 2000),
          ),
        )
        .toList();
  }

  /// Port of Marinara `truncateAgentText`. If the text is longer than
  /// [maxChars], keeps the head (40%) + a trim marker + the tail (60%),
  /// preserving both the beginning and the end of the message. Character
  /// counting uses `String.runes` for Unicode/emoji safety.
  static String truncateAgentText(String text, int maxChars) {
    if (text.length <= maxChars) return text;
    final runes = text.runes.toList();
    if (runes.length <= maxChars) return text;
    final headCount = (maxChars * 0.4).round();
    final tailCount = maxChars - headCount;
    final head = String.fromCharCodes(runes.sublist(0, headCount));
    final tail = String.fromCharCodes(runes.sublist(runes.length - tailCount));
    return '$head$_trimMarker$tail';
  }

  /// Port of Marinara `stripHtmlTags`. Removes HTML/XML-like tags, collapses
  /// 3+ newlines to 2, trims. Conservative: only strips tags that start with
  /// a letter (avoids eating `==...==` custom markers or fenced code).
  static String stripHtmlTags(String text) {
    final stripped = text.replaceAll(_htmlTagRegex, '');
    final collapsed = stripped.replaceAll(_multiNewlineRegex, '\n\n');
    return collapsed.trim();
  }

  /// Strips only `<font>` tags from text, preserving the inner content and
  /// all other HTML (e.g. `<lumiaooc>`, `<i>`, `<b>`). Used for the final
  /// responder's chat history so the model does not see cosmetic color
  /// styling applied by the post-cleaner and does not mimic it.
  static String stripFontTags(String text) {
    return text.replaceAll(_fontTagRegex, '');
  }
}
