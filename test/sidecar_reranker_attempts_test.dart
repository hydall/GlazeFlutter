import 'package:flutter_test/flutter_test.dart';

import 'package:glaze_flutter/core/llm/memory_sidecar_http_client.dart';
import 'package:glaze_flutter/core/llm/memory_sidecar_reranker_service.dart';
import 'package:glaze_flutter/core/llm/memory_selector.dart';
import 'package:glaze_flutter/core/models/agent_operation_record.dart';
import 'package:glaze_flutter/core/models/memory_book.dart';

void main() {
  group('MemorySidecarRerankerService with callWithLog', () {
    test('records attempts on success', () async {
      final entries = [
        MemoryEntry(id: 'm1', title: 'Bridge', content: 'x ' * 20),
      ];
      final fallback = MemorySelector.select(MemorySelectionInput(
        entries: entries,
        maxInjectedEntries: 5,
      ));
      const json =
          '{"selectedEntryIds": ["m1"], "selectedReasons": {"m1": "relevant"}, "rejectedReasons": {}}';

      final service = MemorySidecarRerankerService(
        (_, _) async => json,
        callWithLog: (_, _) async => const MemorySidecarCallOutcome(
          text: json,
          status: AgentOperationStatus.ok,
          attempts: [
            AgentOperationAttempt(
              attempt: 1,
              statusCode: 200,
              status: 'ok',
              startedAtMs: 1000,
              elapsedMs: 50,
            ),
          ],
          totalElapsedMs: 50,
        ),
      );

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
      expect(result.attempts.length, 1);
      expect(result.attempts.first.statusCode, 200);
      expect(result.totalElapsedMs, 50);
    });

    test('records attempts on 5xx failure with fallback', () async {
      final fallback = const MemorySelection();

      final service = MemorySidecarRerankerService(
        (_, _) async => throw Exception('should not call bare client'),
        callWithLog: (_, _) async => const MemorySidecarCallOutcome(
          status: AgentOperationStatus.httpError,
          attempts: [
            AgentOperationAttempt(
              attempt: 1,
              statusCode: 502,
              status: 'http_5xx',
              error: 'Bad Gateway',
              startedAtMs: 1000,
              elapsedMs: 30,
            ),
            AgentOperationAttempt(
              attempt: 2,
              statusCode: 502,
              status: 'http_5xx',
              error: 'Bad Gateway',
              startedAtMs: 1030,
              elapsedMs: 25,
            ),
            AgentOperationAttempt(
              attempt: 3,
              statusCode: 502,
              status: 'http_5xx',
              error: 'Bad Gateway',
              startedAtMs: 1055,
              elapsedMs: 20,
            ),
          ],
          totalElapsedMs: 75,
        ),
      );

      final result = await service.rerank(MemorySidecarRequest(
        settings: const MemoryBookSettings(
          sidecarEnabled: true,
          sidecarTimeoutMs: 5000,
        ),
        candidates: const [],
        fallbackSelection: fallback,
        maxInjectedEntries: 5,
      ));

      expect(result.status, 'http_error');
      expect(result.attempts.length, 3);
      expect(result.attempts.last.statusCode, 502);
      expect(result.totalElapsedMs, 75);
      expect(identical(result.selection, fallback), isTrue);
    });

    test('records attempts on timeout outcome', () async {
      final fallback = const MemorySelection();

      final service = MemorySidecarRerankerService(
        (_, _) async => '{}',
        callWithLog: (_, _) async => const MemorySidecarCallOutcome(
          status: AgentOperationStatus.timeout,
          attempts: [
            AgentOperationAttempt(
              attempt: 1,
              statusCode: 0,
              status: 'timeout',
              error: 'timed out',
              startedAtMs: 1000,
              elapsedMs: 5000,
            ),
          ],
          totalElapsedMs: 5000,
        ),
      );

      final result = await service.rerank(MemorySidecarRequest(
        settings: const MemoryBookSettings(
          sidecarEnabled: true,
          sidecarTimeoutMs: 5000,
        ),
        candidates: const [],
        fallbackSelection: fallback,
        maxInjectedEntries: 5,
      ));

      expect(result.status, 'timeout');
      expect(result.attempts.length, 1);
      expect(result.attempts.first.status, 'timeout');
    });

    test('legacy bare client path still works without callWithLog',
        () async {
      const json =
          '{"selectedEntryIds": [], "selectedReasons": {}, "rejectedReasons": {}}';
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
      expect(result.attempts, isEmpty);
      expect(result.totalElapsedMs, 0);
    });
  });
}
