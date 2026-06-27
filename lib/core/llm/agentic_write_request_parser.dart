import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/agent_operation_record.dart';
import '../models/pipeline_settings.dart';
import '../models/tracker.dart';
import 'memory_agentic_tools.dart';
import 'sidecar_llm_client.dart';

/// Builds the agentic write-loop prompt + parses the LLM's JSON response
/// into tracker/memory write requests. Extracted from
/// `MemoryAgenticWriteService._askLlmForWrites` (plan §7.2).
///
/// Pure prompt/parse pair aside from the injected [SidecarLlmClient] (used
/// for the actual LLM call with retry/timeout). Behavior preserved verbatim.
/// The write-execution (`_executeTrackerWrites` / `_executeMemoryWrites`)
/// stays in `MemoryAgenticWriteService` — this specialist is only the
/// request-shaping layer.
class AgenticWriteRequestParser {
  final SidecarLlmClient _llm;

  AgenticWriteRequestParser(this._llm);

  /// Build the write-loop prompt, fire one sidecar LLM call, and parse the
  /// JSON response into an [AgenticWriteLlmOutcome]. Null `response` means
  /// the LLM returned null/unparseable text; `attempts`/`totalElapsedMs`
  /// are still surfaced for diagnostics.
  Future<AgenticWriteLlmOutcome> askLlmForWrites({
    required SidecarApiConfig config,
    required PipelineSettings settings,
    required String recentHistoryText,
    required List<Tracker> currentTrackers,
    required CancelToken cancelToken,
  }) async {
    final trackersBlock = currentTrackers.isEmpty
        ? '(no active trackers)'
        : currentTrackers.map((t) => '- ${t.name}: ${t.value}').join('\n');

    final prompt =
        '''You are a memory agent for a roleplay conversation. After each turn, you decide what facts to persist so they survive context truncation.

Recent conversation:
$recentHistoryText

Current trackers:
$trackersBlock

Decide what to write. You have two tools:

1. updateTracker — lightweight key-value state that persists across turns (mood, location, relationship status, inventory, ongoing promises).
2. writeMemory — a pending memory draft for significant events, revelations, promises. These require user approval before becoming active.

Respond with ONLY a JSON object (no markdown, no explanation):
{
  "trackers": [
    {"name": "mood", "value": "happy", "scope": "chat"},
    {"name": "location", "value": "tavern"}
  ],
  "memories": [
    {"title": "Lucy reveals the chip", "content": "...", "keys": ["Lucy", "chip"]}
  ]
}

Rules:
- Only write trackers that CHANGED or are NEW. Don't repeat unchanged trackers.
- Only create memory drafts for SIGNIFICANT events (not every turn).
- If nothing is worth persisting, return: {"trackers": [], "memories": []}
- Keep tracker values short (1-5 words).
- Memory content should be 1-3 sentences describing what happened and why it matters.''';

    final outcome = await _llm.callOnceWithLog(
      config: config,
      prompt: prompt,
      maxTokens: 1000,
      temperature: 0.2,
      timeoutMs: settings.sidecarTimeoutMs,
      cancelToken: cancelToken,
    );
    if (!outcome.isOk || outcome.text == null) {
      return AgenticWriteLlmOutcome(
        response: null,
        attempts: outcome.attempts,
        totalElapsedMs: outcome.totalElapsedMs,
      );
    }
    AgenticWriteResponse? response;
    try {
      final decoded = jsonDecode(outcome.text!);
      if (decoded is! Map<String, dynamic>) {
        response = null;
      } else {
        final trackerRequests = <TrackerWriteRequest>[];
        final trackerRaw = decoded['trackers'];
        if (trackerRaw is List) {
          for (final item in trackerRaw) {
            if (item is Map<String, dynamic>) {
              final req = TrackerWriteRequest.fromJson(item);
              if (req.name.isNotEmpty && req.value.isNotEmpty) {
                trackerRequests.add(req);
              }
            }
          }
        }

        final memoryRequests = <MemoryWriteRequest>[];
        final memoryRaw = decoded['memories'];
        if (memoryRaw is List) {
          for (final item in memoryRaw) {
            if (item is Map<String, dynamic>) {
              final req = MemoryWriteRequest.fromJson(item);
              if (req.title.isNotEmpty && req.content.isNotEmpty) {
                memoryRequests.add(req);
              }
            }
          }
        }

        response = AgenticWriteResponse(
          trackerRequests: trackerRequests,
          memoryRequests: memoryRequests,
        );
      }
    } catch (_) {
      response = null;
    }
    return AgenticWriteLlmOutcome(
      response: response,
      attempts: outcome.attempts,
      totalElapsedMs: outcome.totalElapsedMs,
    );
  }
}

/// Parsed LLM response: the tracker + memory write requests the model
/// proposed for this turn. Public so the write-execution service can read
/// the fields after the parser returns.
class AgenticWriteResponse {
  final List<TrackerWriteRequest> trackerRequests;
  final List<MemoryWriteRequest> memoryRequests;

  const AgenticWriteResponse({
    this.trackerRequests = const [],
    this.memoryRequests = const [],
  });
}

/// Outcome of the write-loop LLM call: the parsed [AgenticWriteResponse]
/// (null on null/unparseable text) plus the per-attempt log and total
/// elapsed time for diagnostics.
class AgenticWriteLlmOutcome {
  final AgenticWriteResponse? response;
  final List<AgentOperationAttempt> attempts;
  final int totalElapsedMs;

  const AgenticWriteLlmOutcome({
    this.response,
    this.attempts = const [],
    this.totalElapsedMs = 0,
  });
}
