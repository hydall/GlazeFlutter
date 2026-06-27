import 'dart:convert';

/// Best-effort repair of JSON that an LLM has emitted with common formatting
/// defects. Returns a string that is more likely to parse cleanly via
/// [jsonDecode]; does NOT guarantee validity.
///
/// Ported from Marinara `agent-executor.ts:repairJson`. Strips:
/// - `//` line comments and `/* */` block comments that appear OUTSIDE string
///   literals (a hand-rolled char scanner tracks `inString` / `escaped`
///   flags so comments inside JSON string values are preserved verbatim).
/// - `...` ellipsis placeholders that LLMs love to emit for "more items
///   here" (only outside strings).
/// - Trailing commas immediately before `]` or `}` (the classic
///   "last element in array has a comma" mistake). Detected inside the same
///   string-aware scanner, so a literal `, ]` / `, }` inside a string value
///   is preserved verbatim.
///
/// Use this right before `jsonDecode` when the upstream text was extracted
/// from an LLM response (e.g. via `_extractJsonObject`). If [jsonDecode]
/// still fails after repair, the caller should fall back to its
/// non-JSON path (e.g. prose extraction).
///
/// Limitation: stripping `...` produces a malformed array with a missing
/// middle element (`["a", , "z"]`); this function does NOT collapse missing
/// elements — the downstream `jsonDecode` is the final authority and the
/// caller should fall back to its non-JSON path when the slot is still
/// malformed. Marinara's `repairJson` has the same limitation.
///
/// Example:
/// ```dart
/// final raw = _extractJsonObject(text);
/// if (raw == null) return null;
/// try {
///   return jsonDecode(repairJson(raw));
/// } catch (_) {
///   return null;
/// }
/// ```
String repairJson(String input) {
  if (input.isEmpty) return input;
  final buf = StringBuffer();
  var i = 0;
  var inString = false;
  var escaped = false;
  while (i < input.length) {
    final ch = input[i];
    if (inString) {
      buf.write(ch);
      if (escaped) {
        escaped = false;
      } else if (ch == r'\') {
        escaped = true;
      } else if (ch == '"') {
        inString = false;
      }
      i++;
      continue;
    }
    // Outside a string.
    if (ch == '"') {
      inString = true;
      buf.write(ch);
      i++;
      continue;
    }
    // Line comment `// ...` up to end-of-line.
    if (ch == '/' && i + 1 < input.length && input[i + 1] == '/') {
      i += 2;
      while (i < input.length && input[i] != '\n' && input[i] != '\r') {
        i++;
      }
      continue;
    }
    // Block comment `/* ... */`.
    if (ch == '/' && i + 1 < input.length && input[i + 1] == '*') {
      i += 2;
      while (i + 1 < input.length &&
          !(input[i] == '*' && input[i + 1] == '/')) {
        i++;
      }
      i += 2; // consume `*/`
      continue;
    }
    // Ellipsis `...` (LLM "more items here" placeholder).
    if (ch == '.' &&
        i + 2 < input.length &&
        input[i + 1] == '.' &&
        input[i + 2] == '.') {
      i += 3;
      continue;
    }
    // Trailing comma: a `,` whose next non-whitespace char (outside any
    // string) is `]` or `}`. Done inside the scanner — NOT as a post-hoc
    // regex — so a literal `, ]` / `, }` INSIDE a JSON string value (e.g.
    // {"rule": "avoid lists like [a, b, ]"}) is never touched. We only
    // reach here when `inString` is false. Peek ahead over whitespace; if
    // the comma is trailing, drop it (skip the `,`, keep the whitespace so
    // line/column shapes stay close to the original).
    if (ch == ',') {
      var j = i + 1;
      while (j < input.length &&
          (input[j] == ' ' ||
              input[j] == '\t' ||
              input[j] == '\n' ||
              input[j] == '\r')) {
        j++;
      }
      if (j < input.length && (input[j] == ']' || input[j] == '}')) {
        // Skip the comma only; the whitespace run is re-emitted by the
        // normal path on the next iterations.
        i++;
        continue;
      }
    }
    buf.write(ch);
    i++;
  }
  return buf.toString();
}
