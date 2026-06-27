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
///   "last element in array has a comma" mistake).
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
    buf.write(ch);
    i++;
  }
  // Trailing-comma removal: `,\n]` → `\n]` and `,\n}` → `\n}`. Cheap regex pass
  // after comment stripping — doesn't need string awareness because a
  // trailing comma inside a string literal is extremely rare and the
  // downstream jsonDecode is the final authority. Use replaceAllMapped
  // (not replaceAll) because the replacement string `$1` would otherwise
  // be emitted literally rather than as a backreference.
  return buf
      .toString()
      .replaceAllMapped(RegExp(r',\s*([\]}])'), (m) => m.group(1)!);
}
