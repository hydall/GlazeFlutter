import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'memory_needs_classifier_service.dart';
import 'transport/chat_transport_request.dart';
import 'transport/llm_protocol.dart';
import 'transport/transport_factory.dart';
import '../../features/settings/api_list_provider.dart';

/// Builds a [MemoryClassifierTextClient] that resolves the classifier model
/// config (current vs custom) and makes a non-streaming LLM call via the
/// existing [ChatTransport] abstraction.
///
/// The returned JSON is parsed by [MemoryNeedsClassifierService].
MemoryClassifierTextClient buildClassifierClient(Ref ref) {
  return (MemoryClassifierRequest request, CancelToken cancelToken) async {
    final settings = request.settings;
    final isCustom = settings.classifierSource == 'custom';
    String endpoint;
    String apiKey;
    String model;
    String protocol;

    if (isCustom) {
      endpoint = settings.classifierEndpoint;
      apiKey = settings.classifierApiKey;
      model = settings.classifierModel;
      protocol = LlmProtocol.openai;
    } else {
      await ref.read(apiListProvider.future);
      final chatConfig = ref.read(activeApiConfigProvider);
      if (chatConfig == null) {
        throw Exception('No chat API config available for classifier');
      }
      endpoint = chatConfig.endpoint;
      apiKey = chatConfig.apiKey;
      model = settings.classifierModel.isNotEmpty
          ? settings.classifierModel
          : chatConfig.model;
      protocol = chatConfig.protocol;
    }

    if (endpoint.isEmpty || model.isEmpty) {
      throw Exception('Classifier API not configured');
    }

    final prompt = _buildClassifierPrompt(request);

    final completer = Completer<String>();
    final transport = pickChatTransport(protocol);

    unawaited(transport.stream(
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
    ));

    return completer.future;
  };
}

String _buildClassifierPrompt(MemoryClassifierRequest request) {
  final candidatesBlock = request.candidateTitles.isEmpty
      ? '(no candidates retrieved)'
      : request.candidateTitles.map((t) => '- $t').join('\n');

  final reasonsBlock = request.missingContextReasons.isEmpty
      ? '(none)'
      : request.missingContextReasons.map((r) => '- $r').join('\n');

  return '''You are a memory retrieval classifier. Analyze whether the user's message likely needs old context from stored memories.

Current user message:
${request.currentText}

Retrieved candidate titles:
$candidatesBlock

Missing-context signals:
$reasonsBlock

Respond with ONLY a JSON object (no markdown, no explanation):
{
  "needsMemory": true/false,
  "reliableCandidateFound": true/false,
  "confidence": 0.0-1.0,
  "queryExpansion": ["additional", "search", "terms"],
  "reasons": ["brief reason"]
}

- needsMemory: true if the user likely references prior events/characters/facts
- reliableCandidateFound: true only if a strong candidate was retrieved
- confidence: how sure you are (0.0-1.0)
- queryExpansion: extra search terms if retrieval should broaden
- reasons: brief explanation''';
}
