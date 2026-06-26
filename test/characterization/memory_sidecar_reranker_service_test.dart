import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glaze_flutter/core/llm/memory_sidecar_reranker_service.dart';
import 'package:glaze_flutter/core/llm/memory_selector.dart';
import 'package:glaze_flutter/core/models/memory_book.dart';
import 'package:glaze_flutter/core/models/pipeline_settings.dart';

MemoryEntry _entry(
  String id, {
  String content = 'memory content memory content',
  List<String> messageIds = const [],
}) {
  return MemoryEntry(
    id: id,
    title: id,
    content: content,
    messageIds: messageIds,
  );
}

void main() {
  const settings = PipelineSettings(
    sidecarEnabled: true,
    sidecarTimeoutMs: 50,
  );

  MemorySelection fallback(List<MemoryEntry> entries) {
    return MemorySelection(
      entries: entries,
      allScores: [
        for (final entry in entries)
          MemoryCandidateScore(entry: entry, score: 1),
      ],
    );
  }

  test('disabled sidecar returns fallback without calling client', () async {
    var called = false;
    final service = MemorySidecarRerankerService((_, _) async {
      called = true;
      return '{}';
    });
    final entry = _entry('a');

    final result = await service.rerank(
      MemorySidecarRequest(
        settings: const PipelineSettings(sidecarEnabled: false),
        candidates: [MemoryCandidateScore(entry: entry, score: 1)],
        fallbackSelection: fallback([entry]),
        maxInjectedEntries: 3,
      ),
    );

    expect(result.status, 'disabled');
    expect(result.selection.entries.map((entry) => entry.id), ['a']);
    expect(called, isFalse);
  });

  test('reranks selected ids and preserves structured reasons', () async {
    final service = MemorySidecarRerankerService((_, _) async {
      return '{"selectedEntryIds":["b","a"],"selectedReasons":{"b":"best match"},"rejectedReasons":{"c":"weak"}}';
    });
    final a = _entry('a');
    final b = _entry('b');
    final c = _entry('c');

    final result = await service.rerank(
      MemorySidecarRequest(
        settings: settings,
        candidates: [
          MemoryCandidateScore(entry: a, score: 1),
          MemoryCandidateScore(entry: b, score: 1),
          MemoryCandidateScore(entry: c, score: 1),
        ],
        fallbackSelection: fallback([a]),
        maxInjectedEntries: 3,
      ),
    );

    expect(result.status, 'ok');
    expect(result.selection.entries.map((entry) => entry.id), ['b', 'a']);
    expect(result.decision!.selectedReasons['b'], 'best match');
    expect(result.decision!.rejectedReasons['c'], 'weak');
  });

  test('enforces entry cap, budget, and source-window exclusion', () async {
    final service = MemorySidecarRerankerService((_, _) async {
      return '{"selectedEntryIds":["visible","large","small"]}';
    });
    final visible = _entry('visible', messageIds: const ['m1']);
    final large = _entry('large', content: 'large ' * 400);
    final small = _entry('small', content: 'small memory');

    final result = await service.rerank(
      MemorySidecarRequest(
        settings: settings,
        candidates: [
          MemoryCandidateScore(entry: visible, score: 1),
          MemoryCandidateScore(entry: large, score: 1),
          MemoryCandidateScore(entry: small, score: 1),
        ],
        fallbackSelection: fallback([small]),
        visibleMessageIds: const {'m1'},
        maxInjectionTokens: 20,
        maxInjectedEntries: 1,
      ),
    );

    expect(result.status, 'ok');
    expect(result.selection.entries.map((entry) => entry.id), ['large']);
    expect(result.selection.entries, hasLength(1));
    expect(result.selection.excludedBySourceWindow, 1);
  });

  test('invalid output and timeout fall back safely', () async {
    final entry = _entry('fallback');
    final invalid = MemorySidecarRerankerService((_, _) async => 'not json');
    final invalidResult = await invalid.rerank(
      MemorySidecarRequest(
        settings: settings,
        candidates: [MemoryCandidateScore(entry: entry, score: 1)],
        fallbackSelection: fallback([entry]),
        maxInjectedEntries: 3,
      ),
    );
    expect(invalidResult.status, 'invalid_output');
    expect(invalidResult.selection.entries.single.id, 'fallback');

    final timeout = MemorySidecarRerankerService((_, _) async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return '{}';
    });
    final timeoutResult = await timeout.rerank(
      MemorySidecarRequest(
        settings: settings,
        candidates: [MemoryCandidateScore(entry: entry, score: 1)],
        fallbackSelection: fallback([entry]),
        maxInjectedEntries: 3,
      ),
    );
    expect(timeoutResult.status, 'timeout');
    expect(timeoutResult.selection.entries.single.id, 'fallback');
  });

  test('cancelled token returns aborted fallback', () async {
    final token = CancelToken();
    final entry = _entry('fallback');
    final service = MemorySidecarRerankerService((_, _) async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return '{"selectedEntryIds":["other"]}';
    });

    final future = service.rerank(
      MemorySidecarRequest(
        settings: settings,
        candidates: [MemoryCandidateScore(entry: entry, score: 1)],
        fallbackSelection: fallback([entry]),
        maxInjectedEntries: 3,
      ),
      cancelToken: token,
    );
    token.cancel('abort');

    final result = await future;
    expect(result.status, 'aborted');
    expect(result.selection.entries.single.id, 'fallback');
  });
}
