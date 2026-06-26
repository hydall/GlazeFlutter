import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/agent_operation_record.dart';
import '../models/memory_book.dart';
import 'memory_agentic_policy.dart';
import 'memory_agentic_tools.dart';
import 'memory_selector.dart';
import 'sidecar_llm_client.dart';
import 'transport/chat_transport_request.dart';
import 'transport/llm_protocol.dart';
import 'transport/transport_factory.dart';
import '../../features/settings/api_list_provider.dart';

/// Agentic memory search service (Phase 10).
///
/// When `memoryMode == 'agentic'`, this service runs a bounded retrieval
/// loop before generation:
/// 1. Present available memory tools to the LLM via a non-streaming call.
/// 2. The LLM requests `searchMemory` with a query.
/// 3. The app executes bounded retrieval (app-enforced caps, exclusion).
/// 4. Results are injected into the final generation prompt.
///
/// The write-loop (trackers + memory drafts) lives in
/// [MemoryAgenticWriteService] — separated per CODE_STYLE (one class = one job).
class MemoryAgenticService {
  final Ref _ref;
  final SidecarLlmClient _llm;

  MemoryAgenticService(this._ref) : _llm = SidecarLlmClient(_ref);

  /// Run the agentic memory loop. Returns selected entries + diagnostics.
  Future<MemoryAgenticResult> runAgentic({
    required MemoryBookSettings settings,
    required List<MemoryEntry> entries,
    required String currentText,
    required Set<String> visibleMessageIds,
    required MemorySelection fallbackSelection,
    CancelToken? cancelToken,
  }) async {
    final policy = MemoryAgenticPolicy(MemoryAgenticSettings(
      enabled: settings.memoryMode == 'agentic',
      readOnly: true,
    ));
    if (!policy.settings.enabled) {
      return MemoryAgenticResult(
        status: 'disabled',
        selection: fallbackSelection,
      );
    }

    final token = cancelToken ?? CancelToken();
    if (token.isCancelled) {
      return MemoryAgenticResult(
        status: 'aborted',
        selection: fallbackSelection,
      );
    }

    try {
      final llmOutcome = await _askLlmForSearchQuery(
        settings: settings,
        currentText: currentText,
        candidateTitles: fallbackSelection.allScores
            .where((s) => !s.excludedBySourceWindow && s.score > 0)
            .map((s) => s.entry.title)
            .toList(),
        cancelToken: token,
      );

      final searchQuery = llmOutcome.searchQuery;
      if (searchQuery == null || searchQuery.isEmpty) {
        return MemoryAgenticResult(
          status: 'ok',
          selection: fallbackSelection,
          searchQuery: searchQuery,
          attempts: llmOutcome.attempts,
          totalElapsedMs: llmOutcome.totalElapsedMs,
        );
      }

      final handler = MemoryAgenticToolHandler(policy);
      final result = handler.searchMemory(
        entries: entries,
        query: searchQuery,
        visibleMessageIds: visibleMessageIds,
        maxResults: settings.maxInjectedEntries,
        vectorScores: const {},
        keywordMatchedTerms: const {},
      );

      if (result.hits.isEmpty) {
        return MemoryAgenticResult(
          status: 'ok',
          selection: fallbackSelection,
          searchQuery: searchQuery,
          searchResult: result,
          attempts: llmOutcome.attempts,
          totalElapsedMs: llmOutcome.totalElapsedMs,
        );
      }

      final hitIds = result.hits.map((h) => h.entryId).toSet();
      final selectedEntries =
          entries.where((e) => hitIds.contains(e.id)).toList();

      final agenticScores = <String, double>{};
      for (var i = 0; i < selectedEntries.length; i++) {
        agenticScores[selectedEntries[i].id] =
            (selectedEntries.length - i).toDouble();
      }

      final selection = MemorySelector.select(
        MemorySelectionInput(
          entries: selectedEntries,
          vectorScores: agenticScores,
          visibleMessageIds: visibleMessageIds,
          maxInjectionTokens: fallbackSelection.budgetTokens,
          maxInjectedEntries: settings.maxInjectedEntries,
          sourceWindowExclusion: true,
          diversityAware: false,
          recencyBoost: false,
          importanceBoost: false,
        ),
      );

      return MemoryAgenticResult(
        status: 'ok',
        selection: selection,
        searchQuery: searchQuery,
        searchResult: result,
        attempts: llmOutcome.attempts,
        totalElapsedMs: llmOutcome.totalElapsedMs,
      );
    } on TimeoutException {
      return MemoryAgenticResult(
        status: 'timeout',
        selection: fallbackSelection,
      );
    } catch (e) {
      if (token.isCancelled ||
          (e is DioException && CancelToken.isCancel(e))) {
        return MemoryAgenticResult(
          status: 'aborted',
          selection: fallbackSelection,
        );
      }
      return MemoryAgenticResult(
        status: 'invalid_output',
        selection: fallbackSelection,
        error: '$e',
      );
    }
  }

  Future<_SearchLlmOutcome> _askLlmForSearchQuery({
    required MemoryBookSettings settings,
    required String currentText,
    required List<String> candidateTitles,
    required CancelToken cancelToken,
  }) async {
    final config = await _llm.resolveConfig(settings, errorLabel: 'agentic mode');

    final candidatesBlock = candidateTitles.isEmpty
        ? '(no candidates from deterministic retrieval)'
        : candidateTitles.map((t) => '- $t').join('\n');

    final prompt = '''You are a memory retrieval agent. The user's message may need old context from stored memories.

User message:
$currentText

Deterministic retrieval found these candidates:
$candidatesBlock

If you need to search for specific memories, respond with ONLY a JSON object:
{"searchQuery": "your search query describing what memories you need"}

If the deterministic candidates are sufficient or no old context is needed, respond with:
{"searchQuery": ""}

Respond with ONLY the JSON object, no markdown or explanation.''';

    final outcome = await _llm.callOnceWithLog(
      config: config,
      prompt: prompt,
      maxTokens: 200,
      temperature: 0.1,
      timeoutMs: settings.sidecarTimeoutMs,
      cancelToken: cancelToken,
    );
    if (!outcome.isOk || outcome.text == null) {
      return _SearchLlmOutcome(
        searchQuery: null,
        attempts: outcome.attempts,
        totalElapsedMs: outcome.totalElapsedMs,
      );
    }
    String? searchQuery;
    try {
      final decoded = jsonDecode(outcome.text!);
      if (decoded is Map<String, dynamic>) {
        searchQuery = decoded['searchQuery'] as String?;
      }
    } catch (_) {
      searchQuery = null;
    }
    return _SearchLlmOutcome(
      searchQuery: searchQuery,
      attempts: outcome.attempts,
      totalElapsedMs: outcome.totalElapsedMs,
    );
  }
}

class _SearchLlmOutcome {
  final String? searchQuery;
  final List<AgentOperationAttempt> attempts;
  final int totalElapsedMs;

  const _SearchLlmOutcome({
    this.searchQuery,
    this.attempts = const [],
    this.totalElapsedMs = 0,
  });
}

class MemoryAgenticResult {
  final String status;
  final MemorySelection selection;
  final String? searchQuery;
  final MemorySearchResult? searchResult;
  final String? error;
  final List<AgentOperationAttempt> attempts;
  final int totalElapsedMs;

  const MemoryAgenticResult({
    required this.status,
    required this.selection,
    this.searchQuery,
    this.searchResult,
    this.error,
    this.attempts = const [],
    this.totalElapsedMs = 0,
  });

  bool get usedModel => status == 'ok' && (searchQuery?.isNotEmpty ?? false);
}
