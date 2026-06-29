import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:glaze_flutter/core/llm/beauty_state_parser.dart';

void main() {
  group('parseBeautyState', () {
    test('no marker — returns text untouched, stateJson null', () {
      const text = 'Just a normal roleplay response.\nNo marker here.';
      final result = parseBeautyState(text);
      expect(result.markerFound, isFalse);
      expect(result.stateJson, isNull);
      expect(result.cleanedText, text);
    });

    test('empty string — no marker, empty cleaned text', () {
      final result = parseBeautyState('');
      expect(result.markerFound, isFalse);
      expect(result.stateJson, isNull);
      expect(result.cleanedText, '');
    });

    test('well-formed marker — state extracted, tag stripped', () {
      final state = {
        'speakers': {'Alice': '#abc123'},
        'bg': '#1a1a1a',
      };
      final text = 'Narrative response here.\n\n'
          '<glaze_beauty_state>${jsonEncode(state)}</glaze_beauty_state>';
      final result = parseBeautyState(text);
      expect(result.markerFound, isTrue);
      expect(result.cleanedText, 'Narrative response here.');
      final decoded = jsonDecode(result.stateJson!) as Map<String, dynamic>;
      expect(decoded['speakers'], {'Alice': '#abc123'});
      expect(decoded['bg'], '#1a1a1a');
    });

    test('multiple markers — LAST one wins', () {
      final first = {'speakers': {'Alice': '#aaa'}};
      final second = {'speakers': {'Alice': '#bbb', 'Bob': '#ccc'}};
      final text = '<glaze_beauty_state>${jsonEncode(first)}</glaze_beauty_state>'
          ' narrative '
          '<glaze_beauty_state>${jsonEncode(second)}</glaze_beauty_state>';
      final result = parseBeautyState(text);
      expect(result.markerFound, isTrue);
      final decoded = jsonDecode(result.stateJson!) as Map<String, dynamic>;
      expect(decoded['speakers'], {'Alice': '#bbb', 'Bob': '#ccc'});
      expect(result.cleanedText, 'narrative');
    });

    test('marker with whitespace body — stateJson null, tag stripped', () {
      const text = 'narrative\n<glaze_beauty_state>   </glaze_beauty_state>';
      final result = parseBeautyState(text);
      expect(result.markerFound, isTrue);
      expect(result.stateJson, isNull);
      expect(result.cleanedText, 'narrative');
    });

    test('malformed JSON inside marker — stateJson null, tag stripped', () {
      const text = 'narrative\n<glaze_beauty_state>{not valid json</glaze_beauty_state>';
      final result = parseBeautyState(text);
      expect(result.markerFound, isTrue);
      expect(result.stateJson, isNull);
      expect(result.cleanedText, 'narrative');
    });

    test('JSON with trailing comma — repaired by repairJson, state parsed', () {
      const body = '{"speakers": {"Alice": "#abc",}, "bg": "#111",}';
      const text = 'narrative\n<glaze_beauty_state>$body</glaze_beauty_state>';
      final result = parseBeautyState(text);
      expect(result.markerFound, isTrue);
      expect(result.stateJson, isNotNull);
      final decoded = jsonDecode(result.stateJson!) as Map<String, dynamic>;
      expect(decoded['speakers'], {'Alice': '#abc'});
      expect(decoded['bg'], '#111');
    });

    test('marker is case-insensitive', () {
      const text = 'narrative\n<GLAZE_BEAUTY_STATE>{"x":1}</GLAZE_BEAUTY_STATE>';
      final result = parseBeautyState(text);
      expect(result.markerFound, isTrue);
      expect(result.stateJson, isNotNull);
      expect(result.cleanedText, 'narrative');
    });

    test('marker preserves surrounding text including HTML artifacts', () {
      const text = '<div style="color:red">scene</div>\n'
          '<glaze_beauty_state>{"palette":"dark"}</glaze_beauty_state>';
      final result = parseBeautyState(text);
      expect(result.markerFound, isTrue);
      expect(result.cleanedText, '<div style="color:red">scene</div>');
      final decoded = jsonDecode(result.stateJson!) as Map<String, dynamic>;
      expect(decoded['palette'], 'dark');
    });

    test('nested JSON object with arrays — parsed correctly', () {
      final state = {
        'speakers': {
          'Alice': '#abc',
          'Bob': '#def',
        },
        'thoughts': <String, String>{},
        'palette': 'dark',
        'font': 'sans-serif',
        'art_style': 'street_art_anime',
        'reserved': {'lumia_ooc': '#9370DB'},
      };
      final text = 'response\n<glaze_beauty_state>${jsonEncode(state)}</glaze_beauty_state>';
      final result = parseBeautyState(text);
      expect(result.markerFound, isTrue);
      final decoded = jsonDecode(result.stateJson!) as Map<String, dynamic>;
      expect(decoded['speakers'], {'Alice': '#abc', 'Bob': '#def'});
      expect(decoded['reserved'], {'lumia_ooc': '#9370DB'});
      expect(decoded['art_style'], 'street_art_anime');
    });

    test('trimmed output — leading/trailing whitespace removed from cleaned', () {
      const text = '  narrative  \n<glaze_beauty_state>{"x":1}</glaze_beauty_state>  ';
      final result = parseBeautyState(text);
      expect(result.cleanedText, 'narrative');
    });

    test('JSON array root (not object) — stateJson null', () {
      const text = 'narrative\n<glaze_beauty_state>["a","b","c"]</glaze_beauty_state>';
      final result = parseBeautyState(text);
      expect(result.markerFound, isTrue);
      expect(result.stateJson, isNull);
    });
  });

  group('beautyStateVarKey', () {
    test('exposes the session-vars key used by {{getvar::}}', () {
      expect(beautyStateVarKey, 'glaze_beauty_state');
    });
  });
}
