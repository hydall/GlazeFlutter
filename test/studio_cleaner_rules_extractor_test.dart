import 'package:flutter_test/flutter_test.dart';
import 'package:glaze_flutter/core/llm/studio_cleaner_rules_extractor.dart';
import 'package:glaze_flutter/core/models/api_config.dart';
import 'package:glaze_flutter/core/models/preset.dart';

PresetBlock _block({
  required String id,
  String name = '',
  String role = 'system',
  String content = '',
  bool enabled = true,
}) {
  return PresetBlock(
    id: id,
    name: name,
    role: role,
    content: content,
    enabled: enabled,
  );
}

Preset _preset(List<PresetBlock> blocks, {String id = 'p1', String name = 'Preset'}) {
  return Preset(id: id, name: name, blocks: blocks);
}

void main() {
  group('StudioCleanerRulesExtractor', () {
    test('parses valid JSON with all three fields', () async {
      const response =
          '{"bannedWords":"suddenly,palpable","avoidInstructions":"avoid cliches",'
          '"styleInstructions":"third person, 6-8 paragraphs"}';
      final extractor = StudioCleanerRulesExtractor.forTest(
        (p, {apiConfig, cancelToken}) async => response,
      );
      final rules = await extractor.extract(preset: _preset([_block(id: 'b1')]));
      expect(rules.bannedWords, 'suddenly,palpable');
      expect(rules.avoidInstructions, 'avoid cliches');
      expect(rules.styleInstructions, 'third person, 6-8 paragraphs');
      expect(rules.isEmpty, isFalse);
    });

    test('tolerates markdown fences and surrounding prose', () async {
      const response =
          'Here you go:\n```json\n'
          '{"bannedWords":"word1","avoidInstructions":"av1","styleInstructions":"st1"}\n'
          '```\nDone.';
      final extractor = StudioCleanerRulesExtractor.forTest(
        (p, {apiConfig, cancelToken}) async => response,
      );
      final rules = await extractor.extract(preset: _preset([_block(id: 'b1')]));
      expect(rules.bannedWords, 'word1');
      expect(rules.avoidInstructions, 'av1');
      expect(rules.styleInstructions, 'st1');
    });

    test('trims whitespace from field values', () async {
      const response =
          '{"bannedWords":"  spaced  ","avoidInstructions":"  av  ","styleInstructions":" st "}';
      final extractor = StudioCleanerRulesExtractor.forTest(
        (p, {apiConfig, cancelToken}) async => response,
      );
      final rules = await extractor.extract(preset: _preset([_block(id: 'b1')]));
      expect(rules.bannedWords, 'spaced');
      expect(rules.avoidInstructions, 'av');
      expect(rules.styleInstructions, 'st');
    });

    test('accepts list values and joins with commas', () async {
      const response =
          '{"bannedWords":["a","b","c"],"avoidInstructions":[],"styleInstructions":null}';
      final extractor = StudioCleanerRulesExtractor.forTest(
        (p, {apiConfig, cancelToken}) async => response,
      );
      final rules = await extractor.extract(preset: _preset([_block(id: 'b1')]));
      expect(rules.bannedWords, 'a, b, c');
      expect(rules.avoidInstructions, '');
      expect(rules.styleInstructions, '');
    });

    test('missing fields default to empty strings', () async {
      const response = '{"bannedWords":"x"}';
      final extractor = StudioCleanerRulesExtractor.forTest(
        (p, {apiConfig, cancelToken}) async => response,
      );
      final rules = await extractor.extract(preset: _preset([_block(id: 'b1')]));
      expect(rules.bannedWords, 'x');
      expect(rules.avoidInstructions, '');
      expect(rules.styleInstructions, '');
    });

    test('repairJson tolerates trailing comma before closing brace', () async {
      const response =
          '{"bannedWords":"x","avoidInstructions":"y","styleInstructions":"z",}';
      final extractor = StudioCleanerRulesExtractor.forTest(
        (p, {apiConfig, cancelToken}) async => response,
      );
      final rules = await extractor.extract(preset: _preset([_block(id: 'b1')]));
      expect(rules.bannedWords, 'x');
      expect(rules.avoidInstructions, 'y');
      expect(rules.styleInstructions, 'z');
    });

    test('repairJson strips // line comments outside strings', () async {
      const response =
          '{\n  "bannedWords": "x", // a comment\n  "avoidInstructions": "y",\n  "styleInstructions": "z"\n}';
      final extractor = StudioCleanerRulesExtractor.forTest(
        (p, {apiConfig, cancelToken}) async => response,
      );
      final rules = await extractor.extract(preset: _preset([_block(id: 'b1')]));
      expect(rules.bannedWords, 'x');
      expect(rules.avoidInstructions, 'y');
      expect(rules.styleInstructions, 'z');
    });

    test('throws NoCleanerRulesFoundException when LLM reports {"noRules":true}',
        () async {
      const response = '{"noRules": true}';
      final extractor = StudioCleanerRulesExtractor.forTest(
        (p, {apiConfig, cancelToken}) async => response,
      );
      await expectLater(
        extractor.extract(preset: _preset([_block(id: 'b1')])),
        throwsA(isA<NoCleanerRulesFoundException>()),
      );
    });

    test('throws on null LLM response', () async {
      final extractor = StudioCleanerRulesExtractor.forTest(
        (p, {apiConfig, cancelToken}) async => null,
      );
      await expectLater(
        extractor.extract(preset: _preset([_block(id: 'b1')])),
        throwsA(isA<Exception>()),
      );
    });

    test('throws on empty LLM response', () async {
      final extractor = StudioCleanerRulesExtractor.forTest(
        (p, {apiConfig, cancelToken}) async => '   ',
      );
      await expectLater(
        extractor.extract(preset: _preset([_block(id: 'b1')])),
        throwsA(isA<Exception>()),
      );
    });

    test('throws on non-JSON response', () async {
      final extractor = StudioCleanerRulesExtractor.forTest(
        (p, {apiConfig, cancelToken}) async => 'sorry, I cannot do that',
      );
      await expectLater(
        extractor.extract(preset: _preset([_block(id: 'b1')])),
        throwsA(isA<Exception>()),
      );
    });

    test('throws on malformed JSON', () async {
      const response = '{"bannedWords": "x", "avoidInstructions": "y"';
      final extractor = StudioCleanerRulesExtractor.forTest(
        (p, {apiConfig, cancelToken}) async => response,
      );
      await expectLater(
        extractor.extract(preset: _preset([_block(id: 'b1')])),
        throwsA(isA<Exception>()),
      );
    });

    test('throws NoCleanerRulesFoundException on empty enabled blocks', () async {
      final extractor = StudioCleanerRulesExtractor.forTest(
        (p, {apiConfig, cancelToken}) async => '{"bannedWords":"x"}',
      );
      await expectLater(
        extractor.extract(preset: _preset([_block(id: 'b1', enabled: false)])),
        throwsA(isA<NoCleanerRulesFoundException>()),
      );
    });

    test('passes apiConfig and cancelToken through to the LLM call', () async {
      ApiConfig? seenConfig;
      final extractor = StudioCleanerRulesExtractor.forTest(
        (p, {apiConfig, cancelToken}) async {
          seenConfig = apiConfig;
          return '{"bannedWords":"x","avoidInstructions":"","styleInstructions":""}';
        },
      );
      const config = ApiConfig(
        id: 'api1',
        name: 'Test',
        protocol: 'openai',
        endpoint: 'https://example.com',
        apiKey: 'key',
        model: 'm1',
      );
      await extractor.extract(preset: _preset([_block(id: 'b1')]), apiConfig: config);
      expect(seenConfig, same(config));
    });
  });
}
