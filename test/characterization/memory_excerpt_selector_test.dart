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

    test('prefers vector-matched chunks and can include multiple chunks', () {
      final content = [
        'A quiet setup paragraph about weather and tea.',
        'Ren hid the silver key beneath the chapel floor before sunrise.',
        'The market argument was unrelated and mostly about bread.',
        'Sable later found the chapel map and marked the hidden vault door.',
      ].join('\n\n');

      final selection = MemorySelector.select(
        MemorySelectionInput(
          entries: [_entry(id: 'a', title: 'Chapel clues', content: content)],
          vectorScores: const {'a': 0.9},
          vectorMatchedChunks: const {
            'a': [
              'Ren hid the silver key beneath the chapel floor before sunrise.',
              'Sable later found the chapel map and marked the hidden vault door.',
            ],
          },
          maxInjectionTokens: 28,
          maxInjectedEntries: 1,
          keywordWeight: 0,
          recencyBoost: false,
          importanceBoost: false,
          diversityAware: false,
        ),
        tokenCounter: (entry) => entry.content.split(RegExp(r'\s+')).length,
      );

      final excerpted = MemoryExcerptSelector.select(
        selection,
        maxExcerptTokensPerEntry: 28,
        maxExcerptChunksPerEntry: 2,
        tokenCounter: (text) => text.split(RegExp(r'\s+')).length,
      );

      expect(excerpted.items.single.excerpt, isTrue);
      expect(excerpted.items.single.text, contains('silver key'));
      expect(excerpted.items.single.text, contains('hidden vault'));
      expect(excerpted.items.single.text, isNot(contains('weather and tea')));
    });

    test(
      'uses remaining budget for excerpted entries trimmed by full-entry budget',
      () {
        final selection = MemorySelector.select(
          MemorySelectionInput(
            entries: [
              _entry(
                id: 'a',
                title: 'Full A',
                content: List.filled(40, 'alpha').join(' '),
              ),
              _entry(
                id: 'b',
                title: 'Full B',
                content: List.filled(40, 'bravo').join(' '),
              ),
              _entry(
                id: 'c',
                title: 'Trimmed C',
                content: [
                  List.filled(10, 'boring').join(' '),
                  'needle clue should be excerpted here',
                  List.filled(20, 'tail').join(' '),
                ].join('\n\n'),
                keys: const ['needle'],
              ),
            ],
            keywordMatchedTerms: const {
              'a': ['alpha'],
              'b': ['bravo'],
              'c': ['needle'],
            },
            maxInjectionTokens: 90,
            maxInjectedEntries: 3,
            recencyBoost: false,
            importanceBoost: false,
            diversityAware: false,
          ),
          tokenCounter: (entry) => entry.content.split(RegExp(r'\s+')).length,
        );

        expect(selection.entries.map((e) => e.id), ['a', 'b']);
        expect(selection.budgetTrimmed, isTrue);

        final excerpted = MemoryExcerptSelector.select(
          selection,
          maxExcerptTokensPerEntry: 8,
          maxExcerptChunksPerEntry: 1,
          tokenCounter: (text) => text.split(RegExp(r'\s+')).length,
        );

        expect(excerpted.items.map((item) => item.entry.id), ['a', 'b', 'c']);
        expect(excerpted.items.last.excerpt, isTrue);
        expect(excerpted.items.last.text, contains('needle clue'));
        expect(excerpted.totalTokens, lessThanOrEqualTo(90));
      },
    );

    test(
      'chunk-first packs excerpts for every memory in source chronology',
      () {
        final older = MemoryEntry(
          id: 'older',
          title: 'Older memory',
          content: [
            'setup filler words words words',
            'older needle clue stays first',
          ].join('\n\n'),
          keys: const ['needle'],
          messageRange: const MessageRange(start: 10, end: 20),
          status: 'active',
        );
        final newer = MemoryEntry(
          id: 'newer',
          title: 'Newer memory',
          content: [
            'newer needle clue stays second',
            'tail filler words words words',
          ].join('\n\n'),
          keys: const ['needle'],
          messageRange: const MessageRange(start: 30, end: 40),
          status: 'active',
        );

        final selection = MemorySelection(
          entries: [newer, older],
          allScores: [
            MemoryCandidateScore(
              entry: newer,
              score: 20,
              matchedKeys: const ['needle'],
            ),
            MemoryCandidateScore(
              entry: older,
              score: 10,
              matchedKeys: const ['needle'],
            ),
          ],
          budgetTokens: 20,
          entryCap: 2,
        );

        final excerpted = MemoryExcerptSelector.select(
          selection,
          packingMode: 'chunk_first',
          maxExcerptTokensPerEntry: 6,
          maxExcerptChunksPerEntry: 1,
          tokenCounter: (text) => text.split(RegExp(r'\s+')).length,
        );

        expect(excerpted.items, hasLength(2));
        expect(excerpted.items.every((item) => item.excerpt), isTrue);
        expect(excerpted.items.map((item) => item.entry.id), [
          'older',
          'newer',
        ]);
        expect(excerpted.items.first.text, contains('older needle'));
        expect(excerpted.items.last.text, contains('newer needle'));
      },
    );
  });
}
