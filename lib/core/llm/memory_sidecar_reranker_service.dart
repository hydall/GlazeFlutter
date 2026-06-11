import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/memory_book.dart';
import 'memory_selector.dart';

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

  const MemorySidecarResult({
    required this.status,
    required this.selection,
    this.decision,
    this.error,
  });

  bool get usedModel => status == 'ok';
}

class MemorySidecarRerankerService {
  final MemorySidecarTextClient _client;

  const MemorySidecarRerankerService(this._client);

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

    try {
      final raw = await _client(request, token).timeout(
        Duration(milliseconds: request.settings.sidecarTimeoutMs),
        onTimeout: () => throw TimeoutException('memory sidecar timed out'),
      );
      if (token.isCancelled) {
        return MemorySidecarResult(
          status: 'aborted',
          selection: request.fallbackSelection,
        );
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return _fallback(
          request,
          'invalid_output',
          'sidecar output was not an object',
        );
      }
      final decision = MemorySidecarDecision.fromJson(decoded);
      final selection = _enforceSelection(request, decision);
      return MemorySidecarResult(
        status: 'ok',
        selection: selection,
        decision: decision,
      );
    } on TimeoutException {
      return _fallback(request, 'timeout', null);
    } catch (e) {
      if (token.isCancelled || (e is DioException && CancelToken.isCancel(e))) {
        return MemorySidecarResult(
          status: 'aborted',
          selection: request.fallbackSelection,
        );
      }
      return _fallback(request, 'invalid_output', '$e');
    }
  }

  static MemorySidecarResult _fallback(
    MemorySidecarRequest request,
    String status,
    String? error,
  ) {
    return MemorySidecarResult(
      status: status,
      selection: request.fallbackSelection,
      error: error,
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
