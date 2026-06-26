import 'package:flutter_test/flutter_test.dart';

import 'package:glaze_flutter/core/llm/memory_sidecar_reranker_service.dart';
import 'package:glaze_flutter/core/llm/memory_selector.dart';
import 'package:glaze_flutter/core/models/memory_book.dart';

void main() {
  group('MemorySidecarRerankerService integration (Track 1)', () {
    test('disabled when sidecarEnabled is false', () async {
      final service = MemorySidecarRerankerService((_, _) async => '{}');
      final fallback = const MemorySelection();
      final result = await service.rerank(MemorySidecarRequest(
        settings: const MemoryBookSettings(sidecarEnabled: false),
        candidates: const [],
        fallbackSelection: fallback,
        maxInjectedEntries: 5,
      ));
      expect(result.status, 'disabled');
      expect(identical(result.selection, fallback), isTrue);
    });

    test('parses valid sidecar decision and enforces selection', () async {
      final entries = [
        MemoryEntry(id: 'm1', title: 'Bridge', content: 'x ' * 20),
        MemoryEntry(id: 'm2', title: 'Promise', content: 'y ' * 20),
      ];
      final fallback = MemorySelector.select(MemorySelectionInput(
        entries: entries,
        maxInjectedEntries: 5,
      ));

      const json = '''
{"selectedEntryIds": ["m1"], "selectedReasons": {"m1": "directly relevant"}, "rejectedReasons": {"m2": "not relevant"}}
''';
      final service = MemorySidecarRerankerService((_, _) async => json);
      final result = await service.rerank(MemorySidecarRequest(
        settings: const MemoryBookSettings(
          sidecarEnabled: true,
          sidecarTimeoutMs: 5000,
        ),
        candidates: fallback.allScores,
        fallbackSelection: fallback,
        maxInjectedEntries: 5,
      ));
      expect(result.status, 'ok');
      expect(result.decision!.selectedEntryIds, contains('m1'));
      expect(result.selection.entries.any((e) => e.id == 'm1'), isTrue);
    });

    test('falls back on invalid JSON', () async {
      final fallback = const MemorySelection();
      final service =
          MemorySidecarRerankerService((_, _) async => 'not json');
      final result = await service.rerank(MemorySidecarRequest(
        settings: const MemoryBookSettings(
          sidecarEnabled: true,
          sidecarTimeoutMs: 5000,
        ),
        candidates: const [],
        fallbackSelection: fallback,
        maxInjectedEntries: 5,
      ));
      expect(result.status, 'invalid_output');
      expect(identical(result.selection, fallback), isTrue);
    });

    test('falls back on timeout', () async {
      final fallback = const MemorySelection();
      final service = MemorySidecarRerankerService((_, _) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return '{}';
      });
      final result = await service.rerank(MemorySidecarRequest(
        settings: const MemoryBookSettings(
          sidecarEnabled: true,
          sidecarTimeoutMs: 50,
        ),
        candidates: const [],
        fallbackSelection: fallback,
        maxInjectedEntries: 5,
      ));
      expect(result.status, 'timeout');
      expect(identical(result.selection, fallback), isTrue);
    });

    test('empty selection when sidecar selects no valid entries', () async {
      const json = '{"selectedEntryIds": [], "selectedReasons": {}, "rejectedReasons": {}}';
      final service = MemorySidecarRerankerService((_, _) async => json);
      final result = await service.rerank(MemorySidecarRequest(
        settings: const MemoryBookSettings(
          sidecarEnabled: true,
          sidecarTimeoutMs: 5000,
        ),
        candidates: const [],
        fallbackSelection: const MemorySelection(),
        maxInjectedEntries: 5,
      ));
      expect(result.status, 'ok');
      expect(result.selection.entries, isEmpty);
    });
  });
}
