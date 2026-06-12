import 'package:flutter_test/flutter_test.dart';

import 'package:glaze_flutter/core/llm/memory_excerpt_selector.dart';
import 'package:glaze_flutter/core/llm/memory_selector.dart';
import 'package:glaze_flutter/core/models/memory_book.dart';

MemoryEntry _entry({
  required String id,
  required String title,
  required String content,
  List<String> keys = const [],
  int createdAt = 0,
}) => MemoryEntry(
  id: id,
  title: title,
  content: content,
  keys: keys,
  createdAt: createdAt,
  status: 'active',
);

void main() {
  group('MemoryExcerptSelector', () {
    test('keeps full entries when selected memories fit the token budget', () {
      final selection = MemorySelector.select(
        MemorySelectionInput(
          entries: [
            _entry(
              id: 'a',
              title: 'Bridge promise',
              content: 'Sable promised Ren she would return the map.',
              keys: const ['bridge', 'map'],
            ),
          ],
          maxInjectionTokens: 100,
          maxInjectedEntries: 1,
          keywordWeight: 0,
          vectorWeight: 0,
          recencyBoost: false,
          importanceBoost: false,
          diversityAware: false,
        ),
      );

      final excerpted = MemoryExcerptSelector.select(selection);

      expect(excerpted.items, hasLength(1));
      expect(excerpted.items.single.excerpt, isFalse);
      expect(excerpted.items.single.text, contains('return the map'));
    });

    test('uses canonical entry content excerpts when budget is tight', () {
      final relevant = [
        'The bridge scene opened with rain and silence.',
        'Sable promised Ren she would hide the ritual map until the debt was paid.',
        'They argued about lanterns and horses for several minutes.',
      ].join('\n\n');
      final other = [
        'Varo waited in the tavern.',
        'Varo still owed Ren a debt after the old card game.',
      ].join('\n\n');

      final selection = MemorySelector.select(
        MemorySelectionInput(
          entries: [
            _entry(
              id: 'a',
              title: 'Bridge memory',
              content: relevant,
              keys: const ['ritual map', 'debt'],
              createdAt: 2,
            ),
            _entry(
              id: 'b',
              title: 'Tavern debt',
              content: other,
              keys: const ['Varo debt'],
              createdAt: 1,
            ),
          ],
          keywordMatchedTerms: const {
            'a': ['ritual map', 'debt'],
            'b': ['Varo debt'],
          },
          maxInjectionTokens: 30,
          maxInjectedEntries: 2,
          vectorWeight: 0,
          recencyBoost: false,
          importanceBoost: false,
          diversityAware: false,
        ),
        tokenCounter: (entry) => entry.content.split(RegExp(r'\s+')).length,
      );

      final excerpted = MemoryExcerptSelector.select(
        selection,
        maxExcerptTokensPerEntry: 12,
        maxExcerptChunksPerEntry: 1,
        tokenCounter: (text) => text.split(RegExp(r'\s+')).length,
      );

      expect(excerpted.items, hasLength(2));
      expect(excerpted.items.first.excerpt, isTrue);
      expect(excerpted.items.first.text, contains('ritual map'));
      expect(excerpted.items.first.text, isNot(contains('catalog')));
      expect(excerpted.totalTokens, lessThanOrEqualTo(30));
    });
  });
}
