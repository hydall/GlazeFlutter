import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/agent_operation_record.dart';
import 'memory_sidecar_reranker_service.dart';
import 'sidecar_retry_runner.dart';
import 'transport/chat_transport_request.dart';
import 'transport/llm_protocol.dart';
import 'transport/transport_factory.dart';
import '../../features/settings/api_list_provider.dart';

/// Typed call wrapper used by [MemorySidecarRerankerService] to get the
/// per-attempt retry log alongside the parsed result.
typedef MemorySidecarCallWithLog =
    Future<MemorySidecarCallOutcome> Function(
      MemorySidecarRequest request,
      CancelToken cancelToken,
    );

/// Outcome of a [MemorySidecarTextClient] call, including per-attempt retry
/// log. The reranker service reads [attempts] to record into the operations
/// log.
class MemorySidecarCallOutcome {
  final String? text;
  final AgentOperationStatus status;
  final List<AgentOperationAttempt> attempts;
  final int totalElapsedMs;

  const MemorySidecarCallOutcome({
    this.text,
    required this.status,
    this.attempts = const [],
    this.totalElapsedMs = 0,
  });

  bool get isOk => status == AgentOperationStatus.ok;
}

/// Builds a [MemorySidecarTextClient] that resolves the sidecar model config
/// (current vs custom) and makes a non-streaming LLM call via the existing
/// [ChatTransport] abstraction. Retries 5xx and timeouts with 3 attempts
/// (1s/2s/4s backoff) via [SidecarRetryRunner].
///
/// The returned JSON is parsed by [MemorySidecarRerankerService].
MemorySidecarTextClient buildSidecarClient(Ref ref) {
  return (MemorySidecarRequest request, CancelToken cancelToken) async {
    final outcome = await callSidecarWithLog(
      ref: ref,
      request: request,
      cancelToken: cancelToken,
    );
    if (outcome.isOk && outcome.text != null) return outcome.text!;
    throw _descriptiveError(outcome);
  };
}

/// Same as [buildSidecarClient] but returns a [MemorySidecarCallOutcome] with
/// the per-attempt log for the agentic operations UI.
Future<MemorySidecarCallOutcome> callSidecarWithLog({
  required Ref ref,
  required MemorySidecarRequest request,
  CancelToken? cancelToken,
}) async {
  final settings = request.settings;
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
    await ref.read(apiListProvider.future);
    final chatConfig = ref.read(activeApiConfigProvider);
    if (chatConfig == null) {
      throw Exception('No chat API config available for sidecar');
    }
    endpoint = chatConfig.endpoint;
    apiKey = chatConfig.apiKey;
    model = settings.sidecarModel.isNotEmpty
        ? settings.sidecarModel
        : chatConfig.model;
    protocol = chatConfig.protocol;
  }

  if (endpoint.isEmpty || model.isEmpty) {
    throw Exception('Sidecar API not configured');
  }

  final prompt = _buildSidecarPrompt(request);
  final runner = const SidecarRetryRunner();
  final outcome = await runner.run(
    cancelToken: cancelToken,
    attempt: (i) => _sidecarCallOnce(
      endpoint: endpoint,
      apiKey: apiKey,
      model: model,
      protocol: protocol,
      prompt: prompt,
      cancelToken: cancelToken,
    ),
  );
  return MemorySidecarCallOutcome(
    text: outcome.text,
    status: outcome.status,
    attempts: outcome.attempts,
    totalElapsedMs: outcome.totalElapsedMs,
  );
}

Future<String> _sidecarCallOnce({
  required String endpoint,
  required String apiKey,
  required String model,
  required String protocol,
  required String prompt,
  CancelToken? cancelToken,
}) async {
  final completer = Completer<String>();
  final transport = pickChatTransport(protocol);
  unawaited(
    transport.stream(
    request: ChatTransportRequest(
      endpoint: endpoint,
      apiKey: apiKey,
      model: model,
      messages: [
        {'role': 'user', 'content': prompt},
      ],
      maxTokens: 500,
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
    ),
  );
  return completer.future;
}

Object _descriptiveError(MemorySidecarCallOutcome outcome) {
  if (outcome.attempts.isEmpty) return Exception('Sidecar call failed');
  final last = outcome.attempts.last;
  if (last.status == 'timeout') {
    return TimeoutException('Sidecar timed out after retries');
  }
  if (last.statusCode != 0) {
    return DioException(
      requestOptions: RequestOptions(path: ''),
      response: Response(
        requestOptions: RequestOptions(path: ''),
        statusCode: last.statusCode,
      ),
      type: DioExceptionType.badResponse,
      message: last.error ?? 'HTTP ${last.statusCode}',
    );
  }
  return Exception(last.error ?? 'Sidecar call failed');
}

String _buildSidecarPrompt(MemorySidecarRequest request) {
  final candidatesBlock = request.candidates.map((c) {
    final keys = c.matchedKeys.isEmpty ? '' : ' (keys: ${c.matchedKeys.join(", ")})';
    return '- ID: ${c.entry.id} | Title: ${c.entry.title} | Score: ${c.score.toStringAsFixed(2)}$keys';
  }).join('\n');

  final budget = request.maxInjectionTokens ?? 6000;

  return '''You are a memory reranker. Select the most relevant memories for the current conversation from the candidates below.

Candidates (sorted by initial score):
$candidatesBlock

Constraints:
- Max entries to select: ${request.maxInjectedEntries}
- Token budget: $budget tokens
- Source-window exclusion is enforced by the app separately

Respond with ONLY a JSON object (no markdown, no explanation):
{
  "selectedEntryIds": ["id1", "id2"],
  "selectedReasons": {"id1": "why this was selected", "id2": "why"},
  "rejectedReasons": {"id3": "why this was rejected"}
}

Select only entries that are genuinely relevant. Prefer diversity over redundancy.''';
}
