import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/memory_book.dart';
import '../models/tracker.dart';
import '../state/db_provider.dart';
import '../utils/id_generator.dart';
import '../utils/time_helpers.dart';
import '../../features/settings/api_list_provider.dart';
import 'memory_agentic_policy.dart';
import 'memory_agentic_tools.dart';
import 'memory_selector.dart';
import 'transport/chat_transport_request.dart';
import 'transport/llm_protocol.dart';
import 'transport/transport_factory.dart';

/// Agentic memory service (Phase 10).
///
/// When `memoryMode == 'agentic'`, this service runs a bounded retrieval
/// loop before generation:
/// 1. Present available memory tools to the LLM via a non-streaming call.
/// 2. The LLM requests `searchMemory` with a query.
/// 3. The app executes bounded retrieval (app-enforced caps, exclusion).
/// 4. Results are injected into the final generation prompt.
///
/// This is the sidecar-style approach (non-streaming JSON) for MVP.
/// Native streaming tool calls can be added later via [ChatTransportRequest.tools].
///
/// Timeouts and fallback to deterministic selection are enforced.
class MemoryAgenticService {
  final Ref _ref;

  MemoryAgenticService(this._ref);

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
      // Step 1: Ask the LLM what it wants to search for
      final searchQuery = await _askLlmForSearchQuery(
        settings: settings,
        currentText: currentText,
        candidateTitles: fallbackSelection.allScores
            .where((s) => !s.excludedBySourceWindow && s.score > 0)
            .map((s) => s.entry.title)
            .toList(),
        cancelToken: token,
      );

      if (searchQuery == null || searchQuery.isEmpty) {
        return MemoryAgenticResult(
          status: 'ok',
          selection: fallbackSelection,
          searchQuery: searchQuery,
        );
      }

      // Step 2: Execute bounded retrieval
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
        );
      }

      // Step 3: Build selection from agentic results
      final hitIds = result.hits.map((h) => h.entryId).toSet();
      final selectedEntries = entries.where((e) => hitIds.contains(e.id)).toList();

      // Re-run selector on just the agentic-selected entries
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

  Future<String?> _askLlmForSearchQuery({
    required MemoryBookSettings settings,
    required String currentText,
    required List<String> candidateTitles,
    required CancelToken cancelToken,
  }) async {
    final isCustom = settings.sidecarSource == 'custom';
    String endpoint;
    String apiKey;
    String model;
    String protocol;

    if (isCustom) {
      endpoint = settings.sidecarEndpoint;
      apiKey = settings.sidecarApiKey;
      model = settings.sidecarModel;
      protocol = LlmProtocol.openai;
    } else {
      await _ref.read(apiListProvider.future);
      final chatConfig = _ref.read(activeApiConfigProvider);
      if (chatConfig == null) {
        throw Exception('No chat API config available for agentic mode');
      }
      endpoint = chatConfig.endpoint ?? '';
      apiKey = chatConfig.apiKey ?? '';
      model = settings.sidecarModel.isNotEmpty
          ? settings.sidecarModel
          : (chatConfig.model ?? '');
      protocol = chatConfig.protocol;
    }

    if (endpoint.isEmpty || model.isEmpty) {
      throw Exception('Agentic API not configured');
    }

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

    final completer = Completer<String>();
    final transport = pickChatTransport(protocol);

    transport.stream(
      request: ChatTransportRequest(
        endpoint: endpoint,
        apiKey: apiKey,
        model: model,
        messages: [
          {'role': 'user', 'content': prompt},
        ],
        maxTokens: 200,
        temperature: 0.1,
        topP: 1.0,
        stream: false,
      ),
      cancelToken: cancelToken,
      onComplete: (text, _, {rawResponseJson}) {
        if (!completer.isCompleted) completer.complete(text);
      },
      onError: (error) {
        if (!completer.isCompleted) completer.completeError(error);
      },
    );

    final raw = await completer.future.timeout(
      Duration(milliseconds: settings.sidecarTimeoutMs),
    );

    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return decoded['searchQuery'] as String?;
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Stage 1: Agentic write-loop (post-turn)
  // -------------------------------------------------------------------------

  /// Run the agentic write-loop after a turn is finalized.
  ///
  /// The agent receives the recent conversation text and current trackers,
  /// then decides what to persist: trackers (lightweight state) and/or memory
  /// drafts (pending human-approval entries).
  ///
  /// Uses the sidecar JSON approach (same as searchMemory): one non-streaming
  /// LLM call, model returns JSON with write requests, app executes them
  /// through the policy gate.
  ///
  /// Returns [MemoryWriteLoopResult] with counts of writes/denials/errors.
  /// Never throws — errors are captured in the result.
  Future<MemoryWriteLoopResult> runWriteLoop({
    required String sessionId,
    required MemoryBookSettings settings,
    required String recentHistoryText,
    required List<Tracker> currentTrackers,
    CancelToken? cancelToken,
  }) async {
    if (!settings.agenticWriteEnabled) {
      return const MemoryWriteLoopResult(status: 'disabled');
    }

    final policy = MemoryAgenticPolicy(MemoryAgenticSettings(
      enabled: true,
      readOnly: false,
      writeToolsEnabled: true,
      requireExplicitDiffApproval: false,
    ));

    final token = cancelToken ?? CancelToken();
    if (token.isCancelled) {
      return const MemoryWriteLoopResult(status: 'aborted');
    }

    try {
      // Step 1: Ask the LLM what to write
      final response = await _askLlmForWrites(
        settings: settings,
        sessionId: sessionId,
        recentHistoryText: recentHistoryText,
        currentTrackers: currentTrackers,
        cancelToken: token,
      );

      if (token.isCancelled) {
        return const MemoryWriteLoopResult(status: 'aborted');
      }

      if (response == null) {
        return const MemoryWriteLoopResult(status: 'ok');
      }

      // Step 2: Execute tracker writes
      final trackerResult = await _executeTrackerWrites(
        policy: policy,
        sessionId: sessionId,
        requests: response.trackerRequests,
        provenance: 'memory_agent',
      );

      if (token.isCancelled) {
        return MemoryWriteLoopResult(
          status: 'aborted',
          trackerResult: trackerResult,
        );
      }

      // Step 3: Execute memory draft writes
      final memoryResult = await _executeMemoryWrites(
        policy: policy,
        sessionId: sessionId,
        settings: settings,
        requests: response.memoryRequests,
      );

      return MemoryWriteLoopResult(
        status: 'ok',
        trackerResult: trackerResult,
        memoryResult: memoryResult,
      );
    } on TimeoutException {
      return const MemoryWriteLoopResult(status: 'timeout');
    } catch (e) {
      if (token.isCancelled ||
          (e is DioException && CancelToken.isCancel(e))) {
        return const MemoryWriteLoopResult(status: 'aborted');
      }
      return MemoryWriteLoopResult(status: 'error', error: '$e');
    }
  }

  Future<_WriteLoopResponse?> _askLlmForWrites({
    required MemoryBookSettings settings,
    required String sessionId,
    required String recentHistoryText,
    required List<Tracker> currentTrackers,
    required CancelToken cancelToken,
  }) async {
    final isCustom = settings.sidecarSource == 'custom';
    String endpoint;
    String apiKey;
    String model;
    String protocol;

    if (isCustom) {
      endpoint = settings.sidecarEndpoint;
      apiKey = settings.sidecarApiKey;
      model = settings.sidecarModel;
      protocol = LlmProtocol.openai;
    } else {
      await _ref.read(apiListProvider.future);
      final chatConfig = _ref.read(activeApiConfigProvider);
      if (chatConfig == null) {
        throw Exception('No chat API config available for agentic write-loop');
      }
      endpoint = chatConfig.endpoint ?? '';
      apiKey = chatConfig.apiKey ?? '';
      model = settings.sidecarModel.isNotEmpty
          ? settings.sidecarModel
          : (chatConfig.model ?? '');
      protocol = chatConfig.protocol;
    }

    if (endpoint.isEmpty || model.isEmpty) {
      throw Exception('Agentic API not configured for write-loop');
    }

    final trackersBlock = currentTrackers.isEmpty
        ? '(no active trackers)'
        : currentTrackers.map((t) => '- ${t.name}: ${t.value}').join('\n');

    final prompt = '''You are a memory agent for a roleplay conversation. After each turn, you decide what facts to persist so they survive context truncation.

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

    final completer = Completer<String>();
    final transport = pickChatTransport(protocol);

    transport.stream(
      request: ChatTransportRequest(
        endpoint: endpoint,
        apiKey: apiKey,
        model: model,
        messages: [
          {'role': 'user', 'content': prompt},
        ],
        maxTokens: 1000,
        temperature: 0.2,
        topP: 1.0,
        stream: false,
      ),
      cancelToken: cancelToken,
      onComplete: (text, _, {rawResponseJson}) {
        if (!completer.isCompleted) completer.complete(text);
      },
      onError: (error) {
        if (!completer.isCompleted) completer.completeError(error);
      },
    );

    final raw = await completer.future.timeout(
      Duration(milliseconds: settings.sidecarTimeoutMs),
    );

    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;

    final trackerRaw = decoded['trackers'];
    final memoryRaw = decoded['memories'];

    final trackerRequests = <TrackerWriteRequest>[];
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

    return _WriteLoopResponse(
      trackerRequests: trackerRequests,
      memoryRequests: memoryRequests,
    );
  }

  Future<TrackerWriteResult> _executeTrackerWrites({
    required MemoryAgenticPolicy policy,
    required String sessionId,
    required List<TrackerWriteRequest> requests,
    required String provenance,
  }) async {
    if (requests.isEmpty) return const TrackerWriteResult();

    final repo = _ref.read(trackerRepoProvider);
    var written = 0;
    var denied = 0;
    final errors = <String>[];

    for (final req in requests) {
      final decision = policy.canUse(MemoryAgenticTool.writeTracker);
      if (!decision.allowed) {
        denied++;
        errors.add('Denied ${req.name}: ${decision.reason}');
        continue;
      }
      try {
        await repo.upsertValue(
          sessionId,
          req.name,
          req.value,
          scope: req.scope,
          provenance: provenance,
        );
        written++;
      } catch (e) {
        errors.add('Error ${req.name}: $e');
      }
    }

    return TrackerWriteResult(
      written: written,
      denied: denied,
      errors: errors,
      requests: requests,
    );
  }

  Future<MemoryWriteResult> _executeMemoryWrites({
    required MemoryAgenticPolicy policy,
    required String sessionId,
    required MemoryBookSettings settings,
    required List<MemoryWriteRequest> requests,
  }) async {
    if (requests.isEmpty) return const MemoryWriteResult();

    final repo = _ref.read(memoryBookRepoProvider);
    var written = 0;
    var denied = 0;
    final errors = <String>[];

    // Read current book, append drafts, save atomically.
    final book = await repo.getBySessionId(sessionId) ??
        MemoryBook(
          id: 'memorybook_$sessionId',
          sessionId: sessionId,
          settings: settings,
        );

    final updatedDrafts = List<MemoryDraft>.from(book.pendingDrafts);

    for (final req in requests) {
      final decision = policy.canUse(MemoryAgenticTool.writeMemory);
      if (!decision.allowed) {
        denied++;
        errors.add('Denied "${req.title}": ${decision.reason}');
        continue;
      }
      try {
        final draft = MemoryDraft(
          id: generateId(),
          title: req.title,
          content: req.content,
          keys: req.keys,
          status: 'pending_generation',
          source: 'agentic',
          createdAt: currentTimestampSeconds(),
        );
        updatedDrafts.add(draft);
        written++;
      } catch (e) {
        errors.add('Error "${req.title}": $e');
      }
    }

    if (written > 0) {
      await repo.put(book.copyWith(pendingDrafts: updatedDrafts));
    }

    return MemoryWriteResult(
      written: written,
      denied: denied,
      errors: errors,
      requests: requests,
    );
  }
}

/// Parsed LLM response for the write-loop.
class _WriteLoopResponse {
  final List<TrackerWriteRequest> trackerRequests;
  final List<MemoryWriteRequest> memoryRequests;

  const _WriteLoopResponse({
    this.trackerRequests = const [],
    this.memoryRequests = const [],
  });
}

/// Result of the agentic write-loop.
class MemoryWriteLoopResult {
  final String status;
  final TrackerWriteResult? trackerResult;
  final MemoryWriteResult? memoryResult;
  final String? error;

  const MemoryWriteLoopResult({
    this.status = 'ok',
    this.trackerResult,
    this.memoryResult,
    this.error,
  });

  int get totalWritten =>
      (trackerResult?.written ?? 0) + (memoryResult?.written ?? 0);

  bool get anyWrites => totalWritten > 0;
}

class MemoryAgenticResult {
  final String status;
  final MemorySelection selection;
  final String? searchQuery;
  final MemorySearchResult? searchResult;
  final String? error;

  const MemoryAgenticResult({
    required this.status,
    required this.selection,
    this.searchQuery,
    this.searchResult,
    this.error,
  });

  bool get usedModel => status == 'ok' && (searchQuery?.isNotEmpty ?? false);
}
