import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/api_config.dart';
import '../state/pipeline_settings_provider.dart';
import '../../features/settings/api_list_provider.dart';
import 'transport/chat_transport_request.dart';
import 'transport/llm_protocol.dart';
import 'transport/transport_factory.dart';

/// One-shot, non-streaming LLM call used at BUILD time by
/// `StudioDecompositionService` (preset → controller shards) and the
/// `StudioBlockRouter` (block → bucket classification). Extracted from
/// `StudioDecompositionService._callLlm` (plan §3, §1.1).
///
/// This is the single `Ref`-dependent specialist in the build-time stack. Its
/// [call] signature matches `RouterLlmCall`, so `StudioBlockRouter` can be
/// constructed with `client.call` directly.
///
/// Config resolution order (verbatim from the original `_callLlm`):
/// 1. explicit [apiConfig] argument (the resolved build config), else
/// 2. the aux config when `pipelineSettings.auxSource == 'custom'`,
///    else
/// 3. the active chat API config, with the aux model id overriding the
///    chat model when set.
class StudioBuildLlmClient {
  final Ref _ref;

  StudioBuildLlmClient(this._ref);

  Future<String?> call(
    String prompt, {
    ApiConfig? apiConfig,
    CancelToken? cancelToken,
  }) async {
    final settings = _ref.read(pipelineSettingsProvider);
    final isCustom = settings.auxSource == 'custom';
    String endpoint;
    String apiKey;
    String model;
    String protocol;

    if (apiConfig != null) {
      endpoint = apiConfig.endpoint;
      apiKey = apiConfig.apiKey;
      model = apiConfig.model;
      protocol = apiConfig.protocol;
    } else if (isCustom) {
      endpoint = settings.auxEndpoint;
      apiKey = settings.auxApiKey;
      model = settings.auxModel;
      protocol = LlmProtocol.openai;
    } else {
      await _ref.read(apiListProvider.future);
      final chatConfig = _ref.read(activeApiConfigProvider);
      if (chatConfig == null) {
        throw Exception(
          'No chat API config available for studio decomposition',
        );
      }
      endpoint = chatConfig.endpoint;
      apiKey = chatConfig.apiKey;
      model = settings.auxModel.isNotEmpty
          ? settings.auxModel
          : chatConfig.model;
      protocol = chatConfig.protocol;
    }

    if (endpoint.isEmpty || model.isEmpty) {
      throw Exception('Studio decomposition API not configured');
    }

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
          maxTokens: 4000,
          temperature: 0.3,
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

    return completer.future.timeout(const Duration(seconds: 90));
  }
}
