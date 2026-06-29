import 'dart:convert';

import 'json_repair.dart';

/// Tag wrapping the persistent beauty-state JSON that the LLM appends to the
/// end of an assistant response. Chosen to be unique enough not to collide
/// with HTML/CSS artifacts that may appear in the same response.
const beautyStateTag = 'glaze_beauty_state';

/// Session variable key under which the latest parsed beauty state is stored
/// in [ChatSession.sessionVars]. Preset blocks read it via
/// `{{getvar::glaze_beauty_state}}`.
const beautyStateVarKey = 'glaze_beauty_state';

final RegExp _beautyStateRegex = RegExp(
  '<$beautyStateTag>([\\s\\S]*?)</$beautyStateTag>',
  caseSensitive: false,
);

/// Result of parsing beauty-state markers from an assistant response.
class BeautyStateParseResult {
  /// Text with every `<glaze_beauty_state>...</glaze_beauty_state>` tag
  /// stripped (so it never reaches the chat bubble).
  final String cleanedText;

  /// Parsed state as a JSON-encoded string suitable for storing in
  /// [ChatSession.sessionVars] under [beautyStateVarKey]. `null` when no
  /// well-formed marker was found in the response.
  final String? stateJson;

  /// True when at least one marker was found (regardless of whether the JSON
  /// payload parsed cleanly). Used for diagnostics.
  final bool markerFound;

  const BeautyStateParseResult({
    required this.cleanedText,
    required this.stateJson,
    required this.markerFound,
  });
}

/// Extracts and strips the LAST `<glaze_beauty_state>{...}</glaze_beauty_state>`
/// marker from an LLM response.
///
/// Contract:
/// * The LLM is instructed to append exactly one marker at the END of its
///   response, but we tolerate multiple markers by taking the LAST one
///   (last-write-wins semantics — the model occasionally re-emits the tag
///   after a CSS artifact block).
/// * The marker body is parsed as JSON via [repairJson] + [jsonDecode] so
///   common LLM formatting defects (trailing commas, `//` comments, ellipsis
///   placeholders) do not lose the whole state. When the payload still fails
///   to parse, [BeautyStateParseResult.stateJson] is `null` — the caller
///   leaves the previous session var untouched (state is sticky).
/// * Every marker occurrence (well-formed or not) is removed from
///   [BeautyStateParseResult.cleanedText].
///
/// Pure & synchronous — safe to call from any isolate / test.
BeautyStateParseResult parseBeautyState(String text) {
  final matches = _beautyStateRegex.allMatches(text).toList();
  if (matches.isEmpty) {
    return BeautyStateParseResult(
      cleanedText: text,
      stateJson: null,
      markerFound: false,
    );
  }

  final last = matches.last;
  String? stateJson;
  final raw = last.group(1)?.trim() ?? '';
  if (raw.isNotEmpty) {
    try {
      final repaired = repairJson(raw);
      final decoded = jsonDecode(repaired);
      if (decoded is Map<String, dynamic>) {
        stateJson = jsonEncode(decoded);
      } else if (decoded is Map) {
        stateJson = jsonEncode(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {
      stateJson = null;
    }
  }

  final cleaned = text.replaceAll(_beautyStateRegex, '').trim();
  return BeautyStateParseResult(
    cleanedText: cleaned,
    stateJson: stateJson,
    markerFound: true,
  );
}
