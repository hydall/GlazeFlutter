import 'package:flutter_test/flutter_test.dart';
import 'package:glaze_flutter/core/llm/regex_service.dart';
import 'package:glaze_flutter/core/models/preset.dart';

void main() {
  group('RegexService — ST compatibility (backrefs, flags, substituteRegex)', () {
    RegexApplyContext ctx() => const RegexApplyContext();

    test('Hide html: paired + self-closing tags removed (backrefs + dotAll)', () {
      // ST-style JSON as imported (scriptName/findRegex/replaceString shape)
      final script = PresetRegex.fromJson({
        'id': 'hide-html-1',
        'scriptName': 'Hide html',
        'findRegex':
            r'/<([a-zA-Z0-9]+)(?:[^>]*)?>[\s\S]*?<\/\1>|<[a-zA-Z0-9]+(?:[^>]*)?\s*\/?>/g',
        'replaceString': '',
        'placement': [1, 2, 4],
        'isEnabled': true,
      });

      const input = 'See <div class="x">hello <b>world</b></div> and <br/> and <img src="a.png">';
      final out = applyRegexes(input, 2, 2, [script], ctx());

      // Paired <div>...</div>, <b>...</b>, and self-closing <br/>, <img> should be stripped
      expect(out, equals('See  and  and '));
    });

    test('Braille blank jb: space -> U+2800 (braille blank)', () {
      final script = PresetRegex.fromJson({
        'id': 'braille-blank',
        'scriptName': '[RM] ┌ braille blank jb',
        'findRegex': r'/ /g',
        'replaceString': '\u2800', // braille blank
        'placement': [1, 2, 4],
        'isEnabled': true,
      });

      const input = 'hello world';
      final out = applyRegexes(input, 2, 2, [script], ctx());
      expect(out, equals('hello\u2800world'));
    });

    test('Reverse braille: U+2800 -> space', () {
      final script = PresetRegex.fromJson({
        'id': 'braille-reverse',
        'scriptName': 'Reverse braille',
        'findRegex': r'/\u2800/g',
        'replaceString': ' ',
        'placement': [1, 2, 4],
        'isEnabled': true,
      });

      const input = 'hello\u2800world';
      final out = applyRegexes(input, 2, 2, [script], ctx());
      expect(out, equals('hello world'));
    });

    test('ReplaceSpace with substituteRegex:1 — U+3164 (hangul filler) -> space', () {
      // ST script that uses substituteRegex flag (replacement treated as substitution)
      final script = PresetRegex.fromJson({
        'id': 'replace-space',
        'scriptName': 'ReplaceSpace',
        'findRegex': r'/ㅤ/g', // U+3164
        'replaceString': ' ',
        'substituteRegex': 1,
        'placement': [1, 2, 4],
        'isEnabled': true,
      });

      const input = 'helloㅤworld';
      final out = applyRegexes(input, 2, 2, [script], ctx());
      expect(out, equals('hello world'));
    });

    test('markdownOnly flag restricts to placement 1/2 (history)', () {
      final script = PresetRegex.fromJson({
        'id': 'md-only',
        'name': 'MD only',
        'regex': r'/X/g',
        'replacement': 'Y',
        'markdownOnly': true,
        'placement': [1, 2, 4],
      });

      const input = 'aXb';
      // placement 4 (prompt) should be skipped
      final prompt = applyRegexes(input, 4, 2, [script], ctx());
      expect(prompt, equals('aXb'));

      // placement 1 (user history) should apply
      final userHist = applyRegexes(input, 1, 2, [script], ctx());
      expect(userHist, equals('aYb'));
    });

    test('promptOnly flag restricts to placement 4 (prompt)', () {
      final script = PresetRegex.fromJson({
        'id': 'prompt-only',
        'name': 'Prompt only',
        'regex': r'/X/g',
        'replacement': 'Y',
        'promptOnly': true,
        'placement': [1, 2, 4],
      });

      const input = 'aXb';
      final hist = applyRegexes(input, 2, 2, [script], ctx());
      expect(hist, equals('aXb'));

      final prompt = applyRegexes(input, 4, 2, [script], ctx());
      expect(prompt, equals('aYb'));
    });
  });
}
