import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/agent_operation_record.dart';

import '../models/pipeline_settings.dart';
import '../models/studio_config.dart';
import '../models/tracker.dart';
import 'memory_agentic_tools.dart';
import 'aux_llm_client.dart';
import 'macro_engine.dart';
import 'studio/studio_aux_prompt_assembler.dart';

/// Builds the agentic write-loop prompt + parses the LLM's JSON response
/// into tracker write requests. Extracted from
/// `MemoryAgenticWriteService._askLlmForWrites` (plan §7.2).
///
/// Pure prompt/parse pair aside from the injected [AuxLlmClient] (used
/// for the actual LLM call with retry/timeout). Behavior preserved verbatim.
/// Write execution stays in `MemoryAgenticWriteService`; this specialist is
/// only the request-shaping layer.
class AgenticWriteRequestParser {
  final AuxLlmClient _llm;

  AgenticWriteRequestParser(this._llm);

  /// Build the write-loop prompt, fire one auxiliary LLM call, and parse the
  /// JSON response into an [AgenticWriteLlmOutcome]. Null `response` means
  /// the LLM returned null/unparseable text; `attempts`/`totalElapsedMs`
  /// are still surfaced for diagnostics.
  Future<AgenticWriteLlmOutcome> askLlmForWrites({
    required AuxApiConfig config,
    required PipelineSettings settings,
    required String recentHistoryText,
    required List<Tracker> currentTrackers,
    required CancelToken cancelToken,
    List<StudioPresetBlock> writeloopBlocks = const [],
    MacroContext? macroCtx,
  }) async {
    final trackersBlock = currentTrackers.isEmpty
        ? '(no active trackers)'
        : currentTrackers.map((t) => '- ${t.name}: ${t.value}').join('\n');

    final jsonSuffix = '''
Respond with ONLY a JSON object (no markdown, no explanation):
{
  "trackers": [
    {"name": "mood", "value": "happy", "scope": "chat"},
    {"name": "location", "value": "tavern"}
  ]
}

Rules:
- You are analyzing ~5 turns at once. Focus on significant changes across the batch, not every minor detail.
- Only write trackers that CHANGED or are NEW. Don't repeat unchanged trackers.
- Do not write MemoryBook entries or memory drafts. Long-term history is handled by MemoryBook range summaries and raw-message recall.
- If nothing changed, return: {"trackers": []}
- Keep tracker values short (1-5 words).''';

    final String prompt;
    if (writeloopBlocks.isNotEmpty && macroCtx != null) {
      prompt = const StudioAuxPromptAssembler().assemble(
        blocks: writeloopBlocks,
        section: 'writeloop',
        macroCtx: macroCtx,
        customReplacements: {
          '{{recentHistoryText}}': recentHistoryText,
          '{{trackersBlock}}': trackersBlock,
          '{{existingBlock}}': '',
        },
        runtimeSuffix: jsonSuffix,
      );
    } else {
      prompt =
          '''You are a state-tracking agent for a roleplay conversation. You run every 5 turns and analyze the recent conversation batch to update structured trackers.

Recent conversation (last ~5 turns):
$recentHistoryText

Current trackers:
$trackersBlock

$jsonSuffix''';
    }

    final maxTokens =
        (settings.memoryBookApi.generationMaxTokens != null &&
            settings.memoryBookApi.generationMaxTokens! > 0)
        ? settings.memoryBookApi.generationMaxTokens!
        : 25000;
    final outcome = await _llm.callOnceWithLog(
      config: config,
      prompt: prompt,
      maxTokens: maxTokens,
      temperature: 0.2,
      timeoutMs: settings.memoryPipeline.auxTimeoutMs,
      cancelToken: cancelToken,
    );
    if (!outcome.isOk || outcome.text == null) {
      return AgenticWriteLlmOutcome(
        response: null,
        attempts: outcome.attempts,
        totalElapsedMs: outcome.totalElapsedMs,
      );
    }
    AgenticWriteResponse? response = _parseWriteResponse(outcome.text!);

    // §3: JSON-retry. If the first response was unparseable, retry ONCE with
    // a strict JSON reminder (mirrors Marinara buildInvalidJsonRetryMessages).
    // Transient LLM formatting errors caused silent memory loss before this
    // retry — the catch block returned null with no second attempt.
    if (response == null) {
      final retryPrompt =
          '$prompt\n\n'
          'IMPORTANT: Your previous response was not valid JSON. '
          'Return ONLY a JSON object now — no markdown fences, no prose, '
          'no explanation. Start with `{` and end with `}`.';
      final retryOutcome = await _llm.callOnceWithLog(
        config: config,
        prompt: retryPrompt,
        maxTokens: maxTokens,
        temperature: 0.2,
        timeoutMs: settings.memoryPipeline.auxTimeoutMs,
        cancelToken: cancelToken,
      );
      if (retryOutcome.isOk && retryOutcome.text != null) {
        response = _parseWriteResponse(retryOutcome.text!);
      }
      return AgenticWriteLlmOutcome(
        response: response,
        attempts: [...outcome.attempts, ...retryOutcome.attempts],
        totalElapsedMs: outcome.totalElapsedMs + retryOutcome.totalElapsedMs,
      );
    }
    return AgenticWriteLlmOutcome(
      response: response,
      attempts: outcome.attempts,
      totalElapsedMs: outcome.totalElapsedMs,
    );
  }

  /// Parses the LLM's JSON response into an [AgenticWriteResponse]. Returns
  /// null if the text is not valid JSON or not the expected shape.
  @visibleForTesting
  static AgenticWriteResponse? parseWriteResponse(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) return null;

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

      return AgenticWriteResponse(trackerRequests: trackerRequests);
    } catch (_) {
      return null;
    }
  }

  AgenticWriteResponse? _parseWriteResponse(String text) =>
      parseWriteResponse(text);
}

/// Parsed tracker updates proposed for this turn.
class AgenticWriteResponse {
  final List<TrackerWriteRequest> trackerRequests;

  const AgenticWriteResponse({this.trackerRequests = const []});
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
