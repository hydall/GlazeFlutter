import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:glaze_flutter/core/llm/json_repair.dart';

void main() {
  group('repairJson', () {
    test('passes through valid JSON unchanged (modulo whitespace)', () {
      const input = '{"a": 1, "b": ["x", "y"]}';
      expect(jsonDecode(repairJson(input)), {'a': 1, 'b': ['x', 'y']});
    });

    test('strips line comments outside strings', () {
      const input = '''
{
  "a": 1, // first comment
  "b": 2 // second comment
}
''';
      final result = jsonDecode(repairJson(input)) as Map<String, dynamic>;
      expect(result['a'], 1);
      expect(result['b'], 2);
      expect(result.length, 2);
    });

    test('strips block comments outside strings', () {
      const input = '''
{
  "a": 1, /* block comment */
  "b": 2
}
''';
      final result = jsonDecode(repairJson(input)) as Map<String, dynamic>;
      expect(result['a'], 1);
      expect(result['b'], 2);
    });

    test('preserves comment-like sequences inside string values', () {
      const input = '{"text": "this // is not a comment, nor /* this */"}';
      final result = jsonDecode(repairJson(input)) as Map<String, dynamic>;
      expect(result['text'], 'this // is not a comment, nor /* this */');
    });

    test('strips ellipsis placeholders outside strings', () {
      const input = '{"items": ["a", ..., "z"]}';
      // Stripping `...` produces `["a", , "z"]` — a malformed array with
      // a missing element. repairJson is a string transform, not a JSON
      // parser; the trailing-comma pass will not rescue a *middle* empty
      // slot. This test asserts the `...` is GONE (the upstream LLM defect
      // is removed) — the caller's jsonDecode is the final authority and
      // the caller should fall back to its non-JSON path when the slot is
      // still malformed. (Marinara's repairJson has the same limitation:
      // it strips `...` tokens but does not collapse missing elements.)
      final repaired = repairJson(input);
      expect(repaired.contains('...'), isFalse);
    });

    test('preserves ellipsis inside string values', () {
      const input = '{"text": "wait... what"}';
      final result = jsonDecode(repairJson(input)) as Map<String, dynamic>;
      expect(result['text'], 'wait... what');
    });

    test('removes trailing comma before closing bracket', () {
      const input = '{"a": [1, 2, 3,]}';
      final result = jsonDecode(repairJson(input)) as Map<String, dynamic>;
      expect(result['a'], [1, 2, 3]);
    });

    test('removes trailing comma before closing brace', () {
      const input = '{"a": 1, "b": 2,}';
      final result = jsonDecode(repairJson(input)) as Map<String, dynamic>;
      expect(result['a'], 1);
      expect(result['b'], 2);
    });

    test('removes trailing comma with whitespace before bracket', () {
      const input = '{"a": [1, 2,\n  3,\n]}';
      final result = jsonDecode(repairJson(input)) as Map<String, dynamic>;
      expect(result['a'], [1, 2, 3]);
    });

    test('preserves a literal ", ]" inside a string value (no corruption)', () {
      // Regression: the trailing-comma pass must be string-aware. A string
      // value that contains a comma followed by whitespace then `]` must NOT
      // have that comma stripped (it would silently mutate the value into
      // valid-but-wrong JSON that jsonDecode accepts).
      const input = '{"rule": "avoid lists like [a, b, ]"}';
      final result = jsonDecode(repairJson(input)) as Map<String, dynamic>;
      expect(result['rule'], 'avoid lists like [a, b, ]');
    });

    test('preserves a literal ", }" inside an embedded-JSON string value', () {
      const input = '{"example": "{\\"x\\": 1, }"}';
      final result = jsonDecode(repairJson(input)) as Map<String, dynamic>;
      expect(result['example'], '{"x": 1, }');
    });

    test('strips real trailing comma but keeps an in-string one in same doc', () {
      const input = '{"rule": "drop a, ]", "items": [1, 2,]}';
      final result = jsonDecode(repairJson(input)) as Map<String, dynamic>;
      expect(result['rule'], 'drop a, ]');
      expect(result['items'], [1, 2]);
    });

    test('handles escaped quotes inside strings correctly', () {
      const input = '{"text": "he said \\"hi\\" // not a comment"}';
      final result = jsonDecode(repairJson(input)) as Map<String, dynamic>;
      expect(result['text'], 'he said "hi" // not a comment');
    });

    test('returns empty string unchanged', () {
      expect(repairJson(''), '');
    });

    test('does not choke on input with no JSON structure', () {
      const input = 'not json at all';
      // repairJson is a string transform; it does not validate JSON.
      // The caller is responsible for catching jsonDecode failures.
      expect(() => repairJson(input), returnsNormally);
    });

    test('combined repair: comments + ellipsis + trailing comma', () {
      const input = '''
{
  // top comment
  "focus": ["a", "b"], /* trailing */
  "constraints": ["c",],
}
''';
      final result = jsonDecode(repairJson(input)) as Map<String, dynamic>;
      expect(result['focus'], ['a', 'b']);
      expect(result['constraints'], ['c']);
    });

    test('does not strip comment-like sequences at the start of a string', () {
      const input = '{"text": "// starts like a comment"}';
      final result = jsonDecode(repairJson(input)) as Map<String, dynamic>;
      expect(result['text'], '// starts like a comment');
    });

    test('preserves nested objects with comments at multiple levels', () {
      const input = '''
{
  "outer": {
    "inner": "value", // inner comment
    "list": [1, 2]
  }
}
''';
      final result = jsonDecode(repairJson(input)) as Map<String, dynamic>;
      final outer = result['outer'] as Map<String, dynamic>;
      expect(outer['inner'], 'value');
      expect(outer['list'], [1, 2]);
    });
  });
}
