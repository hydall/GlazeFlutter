import 'package:flutter_test/flutter_test.dart';

import 'package:glaze_flutter/core/llm/memory_selector.dart';
import 'package:glaze_flutter/core/models/memory_book.dart';

MemoryEntry _entry({
  required String id,
  String title = '',
  String content = 'x x x x x x x x x x',
  List<String> keys = const [],
  List<String> messageIds = const [],
  int? createdAt,
  String arc = '',
  double importance = 0,
  bool temporallyBlind = false,
}) => MemoryEntry(
  id: id,
  title: title,
  keys: keys,
  content: content,
  messageIds: messageIds,
  createdAt: createdAt,
  arc: arc,
  importance: importance,
  temporallyBlind: temporallyBlind,
  status: 'active',
);

void main() {
  group('MemorySelector: source-window exclusion', () {
    test('excludes entries whose messageIds overlap the visible window', () {
      final entries = [
        _entry(
          id: 'a',
          title: 'Bridge collapse',
          content: 'episode about the bridge',
          keys: const ['bridge'],
          messageIds: const ['m1', 'm2'],
          createdAt: 1000,
        ),
        _entry(
          id: 'b',
          title: 'Varo debt',
          content: 'varo still owes a favor',
          keys: const ['Varo'],
          createdAt: 2000,
        ),
      ];
      final result = MemorySelector.select(
        MemorySelectionInput(
          entries: entries,
          visibleMessageIds: const {'m1', 'm2'},
          maxInjectedEntries: 5,
          sourceWindowExclusion: true,
        ),
      );
      expect(result.entries.map((e) => e.id), ['b']);
      expect(result.excludedBySourceWindow, 1);
      final a = result.allScores.firstWhere((s) => s.entry.id == 'a');
      expect(a.excludedBySourceWindow, isTrue);
      expect(a.exclusionReason, 'source_visible_in_prompt');
    });

    test(
      'sourceWindowExclusion: false keeps all candidates even when overlap',
      () {
        final entries = [
          _entry(
            id: 'a',
            content: 'episode',
            messageIds: const ['m1'],
            createdAt: 1,
          ),
          _entry(id: 'b', content: 'episode', createdAt: 2),
        ];
        final result = MemorySelector.select(
          MemorySelectionInput(
            entries: entries,
            visibleMessageIds: const {'m1'},
            maxInjectedEntries: 5,
            sourceWindowExclusion: false,
          ),
        );
        expect(result.entries.length, 2);
        expect(result.excludedBySourceWindow, 0);
      },
    );
  });

  group('MemorySelector: first-entry budget fallback (INV-PS4)', () {
    test('keeps the highest-scored entry even if it alone exceeds budget', () {
      final entries = [
        _entry(id: 'huge', content: 'a ' * 500, createdAt: 1),
        _entry(id: 'tiny', content: 'tiny', createdAt: 2),
      ];
      final result = MemorySelector.select(
        MemorySelectionInput(
          entries: entries,
          maxInjectionTokens: 10,
          maxInjectedEntries: 5,
          // Force equal scoring so the sort uses tiebreaker.
          vectorWeight: 0,
          recencyBoost: false,
          importanceBoost: false,
        ),
      );
      expect(result.entries.length, 1);
      expect(result.entries.first.id, 'huge');
      expect(result.budgetTrimmed, isTrue);
    });

    test('drops tail entries once budget would be exceeded', () {
      final entries = List.generate(
        5,
        (i) => _entry(id: 'e$i', content: 'word ' * 6, createdAt: i + 1),
      );
      final result = MemorySelector.select(
        MemorySelectionInput(
          entries: entries,
          maxInjectionTokens: 25,
          maxInjectedEntries: 5,
          vectorWeight: 0,
          recencyBoost: false,
          importanceBoost: false,
          diversityAware: false,
        ),
      );
      // Should keep head entries (newest, higher id) until budget hits.
      expect(result.entries.length, lessThan(5));
      expect(result.budgetTrimmed, isTrue);
      expect(result.entries.first.id, 'e4');
    });
  });

  group('MemorySelector: diversity penalty', () {
    test('penalises near-duplicate titles/keys when picking later entries', () {
      // All entries have identical titles -> later picks should be penalised.
      // With a high penalty (0.9) and a 4-candidate pool that all share the
      // same tokens, the second-and-later picks should be reranked down to
      // a level where the budget/cap stops accepting them.
      final entries = List.generate(
        4,
        (i) => _entry(
          id: 'e$i',
          title: 'Bridge collapse at the old mill',
          keys: const ['bridge', 'mill'],
          content: 'word ' * 4,
          createdAt: i + 1,
        ),
      );
      final result = MemorySelector.select(
        MemorySelectionInput(
          entries: entries,
          maxInjectedEntries: 4,
          maxInjectionTokens: 100,
          keywordWeight: 0,
          vectorWeight: 0,
          recencyBoost: false,
          importanceBoost: false,
          diversityAware: true,
          diversityPenalty: 0.9,
        ),
      );
      // 4 entries with identical token sets; after the first pick the
      // remaining 3 are reranked 0.9 lower. Since their base score is
      // 0.5 (baseline only), they end up at -0.4 — picked but with
      // recorded diversityPenalty = 0.9.
      expect(result.entries.length, 4);
      // Every picked entry after the first must carry a diversity penalty.
      expect(result.allScores.first.diversityPenalty, 0.0);
      final laterPicks = result.allScores
          .where((s) => s.diversityPenalty > 0)
          .toList();
      expect(laterPicks, isNotEmpty);
      expect(laterPicks.every((s) => s.diversityPenalty >= 0.5), isTrue);
    });

    test('diversityAware=false allows picking several near-duplicates', () {
      final entries = List.generate(
        3,
        (i) => _entry(
          id: 'e$i',
          title: 'Bridge collapse',
          keys: const ['bridge'],
          content: 'word ' * 4,
          createdAt: i + 1,
        ),
      );
      final result = MemorySelector.select(
        MemorySelectionInput(
          entries: entries,
          maxInjectedEntries: 3,
          keywordWeight: 0,
          vectorWeight: 0,
          recencyBoost: false,
          importanceBoost: false,
          diversityAware: false,
        ),
      );
      expect(result.entries.length, 3);
    });
  });

  group('MemorySelector: determinism + recency tiebreak', () {
    test('same input -> same output', () {
      final entries = [
        _entry(id: 'a', content: 'word ' * 4, createdAt: 1),
        _entry(id: 'b', content: 'word ' * 4, createdAt: 2),
      ];
      final r1 = MemorySelector.select(
        MemorySelectionInput(
          entries: entries,
          maxInjectedEntries: 2,
          keywordWeight: 0,
          vectorWeight: 0,
          recencyBoost: false,
          importanceBoost: false,
          diversityAware: false,
        ),
      );
      final r2 = MemorySelector.select(
        MemorySelectionInput(
          entries: entries,
          maxInjectedEntries: 2,
          keywordWeight: 0,
          vectorWeight: 0,
          recencyBoost: false,
          importanceBoost: false,
          diversityAware: false,
        ),
      );
      expect(
        r1.entries.map((e) => e.id).toList(),
        r2.entries.map((e) => e.id).toList(),
      );
    });

    test('temporallyBlind entries are not recency-boosted', () {
      final now = 100000000000;
      final entries = [
        _entry(
          id: 'old_blind',
          content: 'word ' * 4,
          createdAt: now - 30 * 86400000,
          temporallyBlind: true,
        ),
        _entry(id: 'old', content: 'word ' * 4, createdAt: now - 30 * 86400000),
      ];
      final result = MemorySelector.select(
        MemorySelectionInput(
          entries: entries,
          nowMillis: now,
          maxInjectedEntries: 2,
          keywordWeight: 0,
          vectorWeight: 0,
          importanceBoost: false,
          diversityAware: false,
        ),
      );
      // The non-blind old entry has recency boost (small but non-zero).
      // The blind entry has 0 boost. Without the keyword/vector/importance
      // contributions, the blind entry's total score is only the baseline.
      final blind = result.allScores.firstWhere(
        (s) => s.entry.id == 'old_blind',
      );
      final nonBlind = result.allScores.firstWhere((s) => s.entry.id == 'old');
      expect(blind.recencyScore, 0.0);
      expect(nonBlind.recencyScore, greaterThan(0.0));
    });
  });

  group('MemorySelector: diagnostics surface for inspection', () {
    test('allScores contains every input entry with a score and reason', () {
      final entries = [
        _entry(id: 'a', content: 'a ' * 20, createdAt: 1),
        _entry(id: 'b', content: 'b ' * 20, createdAt: 2),
        _entry(
          id: 'c',
          content: 'c ' * 20,
          messageIds: const ['m1'],
          createdAt: 3,
        ),
      ];
      final result = MemorySelector.select(
        MemorySelectionInput(
          entries: entries,
          visibleMessageIds: const {'m1'},
          maxInjectedEntries: 5,
        ),
      );
      expect(result.allScores, hasLength(3));
    });
  });

  group('MemorySelector: legacy mode', () {
    test('uses old messageIds and content-length score boosts', () {
      final entries = [
        _entry(
          id: 'legacy_source',
          content: 'old sourced memory about a bridge',
          keys: const ['bridge'],
          messageIds: const ['m1'],
          createdAt: 1,
        ),
        _entry(
          id: 'newer_plain',
          content: 'newer plain memory about nothing',
          createdAt: 999,
        ),
      ];

      final result = MemorySelector.select(
        MemorySelectionInput(
          selectionMode: 'legacy',
          entries: entries,
          keywordMatchedTerms: const {
            'legacy_source': ['bridge'],
          },
          maxInjectedEntries: 1,
          vectorWeight: 0,
          recencyBoost: true,
          importanceBoost: true,
        ),
      );

      expect(result.entries.single.id, 'legacy_source');
      final score = result.allScores.firstWhere(
        (s) => s.entry.id == 'legacy_source',
      );
      expect(score.score, 9.0);
      expect(score.recencyScore, 0.0);
      expect(score.importanceScore, 0.0);
    });

    test('does not treat every entry key as a keyword match', () {
      final entries = [
        _entry(
          id: 'with_key_only',
          keys: const ['bridge'],
          content: 'plain memory with an unmatched key',
        ),
      ];

      final result = MemorySelector.select(
        MemorySelectionInput(
          selectionMode: 'legacy',
          entries: entries,
          maxInjectedEntries: 1,
        ),
      );

      final score = result.allScores.single;
      expect(score.keywordScore, 0.0);
      expect(score.score, 1.0);
    });

    test('does not apply source-window exclusion or diversity penalties', () {
      final entries = [
        _entry(
          id: 'visible',
          title: 'Bridge collapse',
          keys: const ['bridge'],
          content: 'visible sourced memory about a bridge',
          messageIds: const ['m1'],
          createdAt: 1,
        ),
        _entry(
          id: 'duplicate',
          title: 'Bridge collapse',
          keys: const ['bridge'],
          content: 'duplicate sourced memory about a bridge',
          messageIds: const ['m2'],
          createdAt: 2,
        ),
      ];

      final result = MemorySelector.select(
        MemorySelectionInput(
          selectionMode: 'legacy',
          entries: entries,
          visibleMessageIds: const {'m1'},
          maxInjectedEntries: 2,
          keywordWeight: 0,
          vectorWeight: 0,
          diversityAware: true,
          diversityPenalty: 1,
          sourceWindowExclusion: true,
        ),
      );

      expect(result.entries.map((e) => e.id), ['duplicate', 'visible']);
      expect(result.excludedBySourceWindow, 0);
      expect(result.selectionMode, 'legacy');
      expect(result.allScores.every((s) => s.diversityPenalty == 0), isTrue);
    });
  });
}
