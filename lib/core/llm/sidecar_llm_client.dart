import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/api_list_provider.dart';
import '../models/memory_book.dart';
import 'transport/chat_transport_request.dart';
import 'transport/llm_protocol.dart';
import 'transport/transport_factory.dart';

/// Resolved sidecar API configuration for a non-streaming LLM call.
class SidecarApiConfig {
  final String endpoint;
  final String apiKey;
  final String model;
  final String protocol;

  const SidecarApiConfig({
    required this.endpoint,
    required this.apiKey,
    required this.model,
    required this.protocol,
  });
}

/// Shared helper for sidecar (non-streaming) LLM calls.
///
/// Extracted from the duplicated pattern in `MemoryAgenticService`
/// (`_askLlmForSearchQuery`, `_askLlmForWrites`) and `PostCleanerService`
/// (`_askLlmForCleanedText`). All three had identical API-config resolution
/// + `transport.stream` + `Completer` + timeout logic.
///
/// Usage:
/// ```dart
/// final client = SidecarLlmClient(ref);
/// final config = await client.resolveConfig(settings, errorLabel: 'write-loop');
/// final raw = await client.callOnce(
///   config: config,
///   prompt: '...',
///   maxTokens: 1000,
///   temperature: 0.2,
///   timeoutMs: settings.sidecarTimeoutMs,
///   cancelToken: cancelToken,
/// );
/// ```
class SidecarLlmClient {
  final Ref _ref;

  SidecarLlmClient(this._ref);

  /// Resolves the API config from [settings]: either the custom sidecar
  /// endpoint or the active chat config. Throws if not configured.
  Future<SidecarApiConfig> resolveConfig(
    MemoryBookSettings settings, {
    String errorLabel = 'sidecar',
  }) async {
    final isCustom = settings.sidecarSource == 'custom';
    if (isCustom) {
      return SidecarApiConfig(
        endpoint: settings.sidecarEndpoint,
        apiKey: settings.sidecarApiKey,
        model: settings.sidecarModel,
        protocol: LlmProtocol.openai,
      );
    }

    await _ref.read(apiListProvider.future);
    final chatConfig = _ref.read(activeApiConfigProvider);
    if (chatConfig == null) {
      throw Exception('No chat API config available for $errorLabel');
    }
    final model = settings.sidecarModel.isNotEmpty
        ? settings.sidecarModel
        : (chatConfig.model ?? '');
    return SidecarApiConfig(
      endpoint: chatConfig.endpoint ?? '',
      apiKey: chatConfig.apiKey ?? '',
      model: model,
      protocol: chatConfig.protocol,
    );
  }

  /// Makes a single non-streaming LLM call and returns the raw text response.
  ///
  /// Throws [TimeoutException] if [timeoutMs] is exceeded.
  /// Throws [DioException] (cancel) if [cancelToken] is cancelled.
  Future<String> callOnce({
    required SidecarApiConfig config,
    required String prompt,
    required int maxTokens,
    required double temperature,
    required int timeoutMs,
    CancelToken? cancelToken,
  }) async {
    if (config.endpoint.isEmpty || config.model.isEmpty) {
      throw Exception('Sidecar API not configured');
    }

    final completer = Completer<String>();
    final transport = pickChatTransport(config.protocol);

    transport.stream(
      request: ChatTransportRequest(
        endpoint: config.endpoint,
        apiKey: config.apiKey,
        model: config.model,
        messages: [
          {'role': 'user', 'content': prompt},
        ],
        maxTokens: maxTokens,
        temperature: temperature,
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

    return completer.future.timeout(Duration(milliseconds: timeoutMs));
  }
}
