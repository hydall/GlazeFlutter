import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'memory_sidecar_reranker_service.dart';
import 'transport/chat_transport_request.dart';
import 'transport/llm_protocol.dart';
import 'transport/transport_factory.dart';
import '../state/memory_settings_provider.dart';
import '../../features/settings/api_list_provider.dart';

/// Builds a [MemorySidecarTextClient] that resolves the sidecar model config
/// (current vs custom) and makes a non-streaming LLM call via the existing
/// [ChatTransport] abstraction.
///
/// The returned JSON is parsed by [MemorySidecarRerankerService].
MemorySidecarTextClient buildSidecarClient(Ref ref) {
  return (MemorySidecarRequest request, CancelToken cancelToken) async {
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
      endpoint = chatConfig.endpoint ?? '';
      apiKey = chatConfig.apiKey ?? '';
      model = settings.sidecarModel.isNotEmpty
          ? settings.sidecarModel
          : (chatConfig.model ?? '');
      protocol = chatConfig.protocol;
    }

    if (endpoint.isEmpty || model.isEmpty) {
      throw Exception('Sidecar API not configured');
    }

    final prompt = _buildSidecarPrompt(request);

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
    );

    return completer.future;
  };
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
