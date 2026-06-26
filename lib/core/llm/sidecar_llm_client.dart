import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/api_list_provider.dart';
import '../models/memory_book.dart';
import 'sidecar_retry_runner.dart';
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
      if (settings.sidecarEndpoint.isEmpty || settings.sidecarModel.isEmpty) {
        debugPrint(
          '[Sidecar] custom config incomplete — endpoint='
          "'${settings.sidecarEndpoint}' model='${settings.sidecarModel}'",
        );
        throw Exception('Sidecar custom config incomplete for $errorLabel');
      }
      debugPrint(
        '[Sidecar] resolved custom for $errorLabel '
        'model=${settings.sidecarModel}',
      );
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
      debugPrint('[Sidecar] no active chat API config for $errorLabel');
      throw Exception('No chat API config available for $errorLabel');
    }
    final model = settings.sidecarModel.isNotEmpty
        ? settings.sidecarModel
        : chatConfig.model;
    debugPrint(
      '[Sidecar] resolved chat-fallback for $errorLabel '
      'model=$model endpoint=${chatConfig.endpoint}',
    );
    return SidecarApiConfig(
      endpoint: chatConfig.endpoint,
      apiKey: chatConfig.apiKey,
      model: model,
      protocol: chatConfig.protocol,
    );
  }

  /// Makes a single non-streaming LLM call and returns the raw text response.
  ///
  /// Retries on 5xx server errors (502/503/500) and timeouts using a 3-attempt
  /// backoff (1s/2s/4s) via [SidecarRetryRunner]. Throws [TimeoutException] if
  /// all attempts time out. Throws [DioException] (cancel) if [cancelToken] is
  /// cancelled.
  ///
  /// Prefer [callOnceWithLog] when the caller wants the per-attempt log for
  /// the agentic operations UI.
  Future<String> callOnce({
    required SidecarApiConfig config,
    required String prompt,
    required int maxTokens,
    required double temperature,
    required int timeoutMs,
    CancelToken? cancelToken,
  }) async {
    final outcome = await callOnceWithLog(
      config: config,
      prompt: prompt,
      maxTokens: maxTokens,
      temperature: temperature,
      timeoutMs: timeoutMs,
      cancelToken: cancelToken,
    );
    if (outcome.isOk && outcome.text != null) return outcome.text!;
    throw _descriptiveError(outcome);
  }

  /// Same as [callOnce] but returns a [SidecarCallOutcome] with the per-attempt
  /// log so callers can record it in the agentic operations log.
  Future<SidecarCallOutcome> callOnceWithLog({
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
    final runner = const SidecarRetryRunner();
    return runner.run(
      cancelToken: cancelToken,
      attempt: (i) => _callOnce(
        config: config,
        prompt: prompt,
        maxTokens: maxTokens,
        temperature: temperature,
        timeoutMs: timeoutMs,
        cancelToken: cancelToken,
      ),
    );
  }

  /// Builds a descriptive exception from a non-ok [SidecarCallOutcome] so the
  /// caller's `catch` block can fall back to the original text with a useful
  /// error message.
  Object _descriptiveError(SidecarCallOutcome outcome) {
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

  Future<String> _callOnce({
    required SidecarApiConfig config,
    required String prompt,
    required int maxTokens,
    required double temperature,
    required int timeoutMs,
    CancelToken? cancelToken,
  }) async {
    final completer = Completer<String>();
    final transport = pickChatTransport(config.protocol);

    unawaited(
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
      ),
    );

    return completer.future.timeout(Duration(milliseconds: timeoutMs));
  }
}
