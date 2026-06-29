import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:glaze_flutter/core/llm/studio_beauty_extractor.dart';
import 'package:glaze_flutter/core/models/preset.dart';

PresetBlock _block({
  required String id,
  String name = '',
  String role = 'system',
  String content = '',
}) {
  return PresetBlock(id: id, name: name, role: role, content: content);
}

void main() {
  group('StudioBeautyExtractor prompt', () {
    test(
      'explicitly separates reusable style from artifacts and Lumia/meta',
      () {
        final extractor = StudioBeautyExtractor(
          (prompt, {apiConfig, cancelToken}) async => null,
        );
        final prompt = extractor.buildPromptForTest([
          _block(
            id: 'style',
            name: 'Colored Dialogue',
            content: 'reuse colors',
          ),
          _block(id: 'lumia', name: 'Lumia OOC', content: '#9370DB'),
          _block(id: 'phone', name: 'Phone UI', content: 'taxi-call menu'),
        ]);

        expect(prompt, contains('reusable visual styling settings'));
        expect(prompt, contains('DO NOT SELECT'));
        expect(prompt, contains('Lumia/OOC/meta-persona'));
        expect(prompt, contains('phone screens'));
        expect(prompt, contains('reserved_style_notes'));
      },
    );
  });

  group('StudioBeautyExtractor.parse', () {
    final extractor = StudioBeautyExtractor(
      (prompt, {apiConfig, cancelToken}) async => null,
    );
    const validIds = {'style', 'lumia', 'phone'};

    test('accepts selected beauty ids and synthetic contract', () {
      final raw = jsonEncode({
        'beauty_block_ids': ['style'],
        'reserved_style_notes': [
          {
            'source_block_id': 'lumia',
            'key': 'lumia_ooc',
            'value': '#9370DB',
            'note': 'reserved for Lumia/OOC',
          },
        ],
        'normalized_style_contract': {
          'palette': 'dark',
          'background': '#111',
          'reserved': {'lumia_ooc': '#9370DB'},
        },
      });

      final result = extractor.parseForTest(raw, validIds);
      expect(result.fromLlm, isTrue);
      expect(result.beautyBlockIds, {'style'});
      expect(result.syntheticContract, contains('normalized_style_contract'));
      expect(result.syntheticContract, contains('reserved_style_notes'));
      expect(result.syntheticContract, contains('#9370DB'));
    });

    test('drops unknown selected block ids', () {
      final raw = jsonEncode({
        'beauty_block_ids': ['style', 'unknown'],
        'normalized_style_contract': {'palette': 'dark'},
      });

      final result = extractor.parseForTest(raw, validIds);
      expect(result.beautyBlockIds, {'style'});
    });

    test('returns empty on malformed JSON', () {
      final result = extractor.parseForTest('not json', validIds);
      expect(result.beautyBlockIds, isEmpty);
      expect(result.syntheticContract, isEmpty);
      expect(result.fromLlm, isFalse);
    });

    test('tolerates markdown fenced JSON', () {
      const raw = '```json\n{"beauty_block_ids":["style"]}\n```';
      final result = extractor.parseForTest(raw, validIds);
      expect(result.beautyBlockIds, {'style'});
      expect(result.fromLlm, isTrue);
    });
  });
}
