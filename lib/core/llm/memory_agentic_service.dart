import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/agent_operation_record.dart';
import '../models/memory_book.dart';
import '../models/pipeline_settings.dart';
import 'memory_agentic_policy.dart';
import 'memory_agentic_tools.dart';
import 'memory_selector.dart';
import 'sidecar_llm_client.dart';

/// Agentic memory search service.
///
/// This service runs a bounded retrieval loop before generation:
/// 1. Present available memory tools to the LLM via a non-streaming call.
/// 2. The LLM requests `searchMemory` with a query.
/// 3. The app executes bounded retrieval (app-enforced caps, exclusion).
/// 4. Results are injected into the final generation prompt.
///
/// Previously gated by `MemoryBookSettings.memoryMode == 'agentic'`, but the
/// `agentic` mode was removed in Phase 4 of docs/PLAN_AGENTIC_STUDIO.md.
/// Agentic read is now a separate pre-generation tracker concern (wired in
/// Phase 5+); until then this service is effectively disabled.
///
/// The write-loop (trackers + memory drafts) lives in
/// [MemoryAgenticWriteService] — separated per CODE_STYLE (one class = one job).
class MemoryAgenticService {
  final SidecarLlmClient _llm;

  MemoryAgenticService(Ref ref) : _llm = SidecarLlmClient(ref);

  /// Run the agentic memory loop. Returns selected entries + diagnostics.
  Future<MemoryAgenticResult> runAgentic({
    required MemoryBookSettings settings,
    required PipelineSettings pipeline,
    required List<MemoryEntry> entries,
    required String currentText,
    required Set<String> visibleMessageIds,
    required MemorySelection fallbackSelection,
    CancelToken? cancelToken,
  }) async {
    // The `agentic` MemoryBook mode was removed in Phase 4. Agentic read
    // will be wired as a pre-generation memory tracker in a later phase;
    // until then this service is disabled.
    return MemoryAgenticResult(
      status: 'disabled',
      selection: fallbackSelection,
    );
  }

  Future<_SearchLlmOutcome> _askLlmForSearchQuery({
    required PipelineSettings pipeline,
    required String currentText,
    required List<String> candidateTitles,
    required CancelToken cancelToken,
  }) async {
    final config = await _llm.resolveConfig(pipeline, errorLabel: 'agentic mode');

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
      timeoutMs: pipeline.sidecarTimeoutMs,
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
