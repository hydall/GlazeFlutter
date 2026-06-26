import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/agent_operation_record.dart';
import '../models/memory_book.dart';
import 'memory_selector.dart';
import 'memory_sidecar_http_client.dart';

typedef MemorySidecarTextClient =
    Future<String> Function(
      MemorySidecarRequest request,
      CancelToken cancelToken,
    );

class MemorySidecarRequest {
  final MemoryBookSettings settings;
  final List<MemoryCandidateScore> candidates;
  final MemorySelection fallbackSelection;
  final Set<String> visibleMessageIds;
  final int? maxInjectionTokens;
  final int maxInjectedEntries;

  const MemorySidecarRequest({
    required this.settings,
    required this.candidates,
    required this.fallbackSelection,
    this.visibleMessageIds = const {},
    this.maxInjectionTokens,
    required this.maxInjectedEntries,
  });
}

class MemorySidecarDecision {
  final List<String> selectedEntryIds;
  final Map<String, String> selectedReasons;
  final Map<String, String> rejectedReasons;

  const MemorySidecarDecision({
    this.selectedEntryIds = const [],
    this.selectedReasons = const {},
    this.rejectedReasons = const {},
  });

  factory MemorySidecarDecision.fromJson(Map<String, dynamic> json) {
    return MemorySidecarDecision(
      selectedEntryIds: _stringList(json['selectedEntryIds']),
      selectedReasons: _stringMap(json['selectedReasons']),
      rejectedReasons: _stringMap(json['rejectedReasons']),
    );
  }

  static List<String> _stringList(Object? raw) {
    if (raw is! List) return const [];
    return raw.whereType<String>().toList(growable: false);
  }

  static Map<String, String> _stringMap(Object? raw) {
    if (raw is! Map) return const {};
    return raw.map((key, value) => MapEntry('$key', '$value'));
  }
}

class MemorySidecarResult {
  final String status;
  final MemorySelection selection;
  final MemorySidecarDecision? decision;
  final String? error;
  final List<AgentOperationAttempt> attempts;
  final int totalElapsedMs;

  const MemorySidecarResult({
    required this.status,
    required this.selection,
    this.decision,
    this.error,
    this.attempts = const [],
    this.totalElapsedMs = 0,
  });

  bool get usedModel => status == 'ok';
}

class MemorySidecarRerankerService {
  final MemorySidecarTextClient _client;
  final MemorySidecarCallWithLog? _callWithLog;

  /// When provided, [rerank] uses this typed call (which carries the retry
  /// log) instead of the bare [_client]. Null in tests / legacy wiring.
  MemorySidecarRerankerService(
    this._client, {
    MemorySidecarCallWithLog? callWithLog,
  }) : _callWithLog = callWithLog;

  Future<MemorySidecarResult> rerank(
    MemorySidecarRequest request, {
    CancelToken? cancelToken,
  }) async {
    if (!request.settings.sidecarEnabled) {
      return MemorySidecarResult(
        status: 'disabled',
        selection: request.fallbackSelection,
      );
    }
    final token = cancelToken ?? CancelToken();
    if (token.isCancelled) {
      return MemorySidecarResult(
        status: 'aborted',
        selection: request.fallbackSelection,
      );
    }

    List<AgentOperationAttempt> attempts = const [];
    var totalMs = 0;
    try {
      final String raw;
      if (_callWithLog != null) {
        final outcome = await _callWithLog(request, token).timeout(
          Duration(milliseconds: request.settings.sidecarTimeoutMs),
          onTimeout: () => throw TimeoutException('memory sidecar timed out'),
        );
        attempts = outcome.attempts;
        totalMs = outcome.totalElapsedMs;
        if (!outcome.isOk || outcome.text == null) {
          return _fallback(
            request,
            _statusLabel(outcome.status),
            outcome.attempts.isNotEmpty ? outcome.attempts.last.error : null,
            attempts: attempts,
            totalElapsedMs: totalMs,
          );
        }
        raw = outcome.text!;
      } else {
        raw = await _client(request, token).timeout(
          Duration(milliseconds: request.settings.sidecarTimeoutMs),
          onTimeout: () => throw TimeoutException('memory sidecar timed out'),
        );
      }
      if (token.isCancelled) {
        return MemorySidecarResult(
          status: 'aborted',
          selection: request.fallbackSelection,
          attempts: attempts,
          totalElapsedMs: totalMs,
        );
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return _fallback(
          request,
          'invalid_output',
          'sidecar output was not an object',
          attempts: attempts,
          totalElapsedMs: totalMs,
        );
      }
      final decision = MemorySidecarDecision.fromJson(decoded);
      final selection = _enforceSelection(request, decision);
      return MemorySidecarResult(
        status: 'ok',
        selection: selection,
        decision: decision,
        attempts: attempts,
        totalElapsedMs: totalMs,
      );
    } on TimeoutException {
      return _fallback(
        request,
        'timeout',
        null,
        attempts: attempts,
        totalElapsedMs: totalMs,
      );
    } catch (e) {
      if (token.isCancelled || (e is DioException && CancelToken.isCancel(e))) {
        return MemorySidecarResult(
          status: 'aborted',
          selection: request.fallbackSelection,
          attempts: attempts,
          totalElapsedMs: totalMs,
        );
      }
      return _fallback(
        request,
        'invalid_output',
        '$e',
        attempts: attempts,
        totalElapsedMs: totalMs,
      );
    }
  }

  static String _statusLabel(AgentOperationStatus status) {
    return switch (status) {
      AgentOperationStatus.ok => 'ok',
      AgentOperationStatus.disabled => 'disabled',
      AgentOperationStatus.aborted => 'aborted',
      AgentOperationStatus.timeout => 'timeout',
      AgentOperationStatus.httpError => 'http_error',
      AgentOperationStatus.invalidOutput => 'invalid_output',
      AgentOperationStatus.error => 'error',
    };
  }

  static MemorySidecarResult _fallback(
    MemorySidecarRequest request,
    String status,
    String? error, {
    List<AgentOperationAttempt> attempts = const [],
    int totalElapsedMs = 0,
  }) {
    return MemorySidecarResult(
      status: status,
      selection: request.fallbackSelection,
      error: error,
      attempts: attempts,
      totalElapsedMs: totalElapsedMs,
    );
  }

  static MemorySelection _enforceSelection(
    MemorySidecarRequest request,
    MemorySidecarDecision decision,
  ) {
    final candidateById = {
      for (final candidate in request.candidates)
        candidate.entry.id: candidate.entry,
    };
    final selected = decision.selectedEntryIds
        .map((id) => candidateById[id])
        .whereType<MemoryEntry>()
        .toList(growable: false);
    if (selected.isEmpty) return const MemorySelection();

    final sidecarScores = <String, double>{};
    for (var i = 0; i < selected.length; i++) {
      sidecarScores[selected[i].id] = (selected.length - i).toDouble();
    }
    return MemorySelector.select(
      MemorySelectionInput(
        entries: selected,
        vectorScores: sidecarScores,
        visibleMessageIds: request.visibleMessageIds,
        maxInjectionTokens: request.maxInjectionTokens,
        maxInjectedEntries: request.maxInjectedEntries,
        sourceWindowExclusion: true,
        diversityAware: false,
        recencyBoost: false,
        importanceBoost: false,
      ),
    );
  }
}
